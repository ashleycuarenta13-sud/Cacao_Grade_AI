import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

// kApiBaseUrl - where the backend is - lives in constants/ so the services,
// the screens and any future client all read the same value.
import 'package:cacao/constants/app_constants.dart';
import 'package:cacao/models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Attaches the session bearer token to every outgoing request.
///
/// Activity 3, Part A prescribes exactly this: *"dio, with an interceptor that
/// attaches the JWT to every request."* Centralising it here is why no other
/// method in [CacaoApi] has to remember to build an `Authorization` header -
/// and why a new endpoint cannot accidentally ship unauthenticated.
class JwtInterceptor extends Interceptor {
  const JwtInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await CacaoApi.readToken();

      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // A preferences failure must not block the call; the server answers 401
      // and the caller signs in again.
    }

    handler.next(options);
  }
}

/// HTTP client for `/api/*`.
///
/// The signed-in account itself lives in [authProvider] (`providers/state.dart`);
/// this class only owns the bearer token and the transport.
class CacaoApi {
  /// The client every endpoint goes through.
  ///
  /// Tests replace it with `newClient(adapter: ...)` so the interceptor, the
  /// base URL and the status handling behave exactly as they do at runtime.
  static Dio client = newClient();

  static const String _tokenKey = 'cacao_auth_token';

  /// Builds a client. Passing [adapter] swaps only the transport, which is
  /// how the widget tests stand in for the FastAPI backend.
  static Dio newClient({HttpClientAdapter? adapter}) {
    final dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),

      // Every HTTP status is a *response*, not a transport error. The code
      // below decides what each one means, which is what keeps 422 (the photo
      // is unusable - never retry) distinguishable from 502/503 (the CNN
      // service hiccuped - queue it and retry), and the offline queue in
      // providers/pending_uploads.dart depends on that distinction.
      validateStatus: (status) => status != null && status < 600,

      responseType: ResponseType.json,
    ));

    dio.interceptors.add(const JwtInterceptor());

    if (adapter != null) dio.httpClientAdapter = adapter;

    return dio;
  }

  // ---------------------------------------------------------------- helpers

  /// Pulls FastAPI's `detail` out of an error response.
  static String readDetail(Response response) {
    final data = response.data;

    try {
      final Object? body = data is String ? jsonDecode(data) : data;

      if (body is Map) {
        final detail = body['detail'];

        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            return first['msg'].toString();
          }
        }
      }
    } catch (_) {
      // Not JSON - fall through to the generic message.
    }

    return 'Server returned an error (${response.statusCode}).';
  }

  /// Normalises anything dio can throw into the one exception the UI knows.
  static ApiException toApiException(Object error) {
    if (error is ApiException) return error;

    if (error is DioException) {
      final response = error.response;

      if (response != null) {
        return ApiException(readDetail(response), response.statusCode);
      }

      // Two fault types have a meaning worth naming on screen. Everything
      // else - connection, send, receive and transform timeouts, a body that
      // failed to decode, a cancelled or unknown transport fault - is
      // "the backend did not answer", which is what the queue retries.
      if (error.type == DioExceptionType.cancel) {
        return const ApiException('The request was cancelled.');
      }

      if (error.type == DioExceptionType.badCertificate) {
        return const ApiException(
            'The server certificate could not be trusted.');
      }
    }

    return ApiException(
        'Cannot reach the backend server. Make sure it is running on $kApiBaseUrl.');
  }

  /// The backend answers with `{id, full_name, email, role, dashboard}`;
  /// `AppUser.fromJson` expects `{id, name, email, role}`.
  static AppUser userFromApi(Map<String, dynamic> json) => AppUser.fromJson({
        ...json,
        'name': json['full_name'] ?? json['name'] ?? '',
        'status': 'Active',
      });

  // ---------------------------------------------------------------- session

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // -------------------------------------------------------------------- auth

  static Future<AppUser> _post(String path, {Map<String, dynamic>? body}) async {
    try {
      final response = await client.post(path, data: body);

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      final data = _asMap(response.data);
      final user = userFromApi(Map<String, dynamic>.from(data['user'] as Map));
      final token = data['token'] as String?;

      if (token != null) await saveToken(token);

      return user;
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  static Future<AppUser> register({
    required String fullName,
    required String email,
    required String password,
  }) =>
      _post('/api/auth/register', body: {
        'full_name': fullName,
        'email': email,
        'password': password,
      });

  static Future<AppUser> login({
    required String email,
    required String password,
  }) =>
      _post('/api/auth/login', body: {'email': email, 'password': password});

  /// Revalidates the stored bearer token. Returns `null` when the session
  /// is no longer valid.
  static Future<AppUser?> me() async {
    final token = await readToken();
    if (token == null) return null;

    try {
      final response = await client.get('/api/auth/profile');

      if (response.statusCode != 200) {
        await clearToken();
        return null;
      }

      return userFromApi(
          Map<String, dynamic>.from(_asMap(response.data)['user'] as Map));
    } catch (_) {
      // Backend unreachable - keep the local session instead of logging out.
      return null;
    }
  }

  static Future<void> logout() async {
    final token = await readToken();
    await clearToken();
    if (token == null) return;

    try {
      await client.post('/api/auth/logout');
    } catch (_) {
      // Local session is already cleared, nothing else to do.
    }
  }

  // --------------------------------------------------------------- profile
  //
  // Activity 3, Part D, rows 2 and 3 of the contract worksheet.

  /// `GET /api/auth/profile` - the requesting user's record, including the
  /// `contact` field the worksheet's request data names.
  static Future<Map<String, dynamic>> fetchProfile() async {
    try {
      final response = await client.get('/api/auth/profile');

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      return Map<String, dynamic>.from(_asMap(response.data)['user'] as Map);
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  /// `PUT /api/auth/profile` - saves the profile form.
  ///
  /// Only the keys present in [fields] are sent, so the server updates just
  /// what the user edited (and a partial update cannot blank the rest).
  static Future<Map<String, dynamic>> updateProfile(
      Map<String, String> fields) async {
    try {
      final response =
          await client.put('/api/auth/profile', data: Map.of(fields));

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      return Map<String, dynamic>.from(_asMap(response.data)['user'] as Map);
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  // ------------------------------------------------------------- data calls

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('Unexpected response from the server.');
  }

  static Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await client.get(path, queryParameters: query);

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      final data = _asMap(response.data);
      final items = data['data'];
      if (items is! List) return [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  /// Fermentation classifications already saved in PostgreSQL.
  static Future<List<Map<String, dynamic>>> fetchHistory() =>
      _getList('/api/history');

  /// Batch records stored in PostgreSQL (`GET /api/batches`).
  ///
  /// Activity 3, Part D names `farmer_id` and a date range as this endpoint's
  /// query parameters; all three are optional and the server decides whether
  /// the caller's role is allowed to ask for them.
  static Future<List<Map<String, dynamic>>> fetchBatches({
    int? farmerId,
    String? startDate,
    String? endDate,
  }) {
    final query = <String, dynamic>{};

    if (farmerId != null) query['farmer_id'] = farmerId;
    if (startDate != null && startDate.isNotEmpty) {
      query['start_date'] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) query['end_date'] = endDate;

    return _getList('/api/batches', query: query.isEmpty ? null : query);
  }

  /// One batch with its classification records (`GET /api/batches/{id}`).
  static Future<Map<String, dynamic>> fetchBatchDetail(int id) async {
    try {
      final response = await client.get('/api/batches/$id');

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      return Map<String, dynamic>.from(_asMap(response.data)['batch'] as Map);
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  /// Dashboard aggregation (`GET /api/trends`): stage counts, average
  /// confidence, and the daily series the backend computed.
  static Future<Map<String, dynamic>> fetchTrends() async {
    try {
      final response = await client.get('/api/trends');

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      return _asMap(response.data);
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  /// Removes a batch (`DELETE /api/batches/{id}`). Farmers may only delete
  /// their own; staff and admins may delete any.
  static Future<void> deleteBatch(int id) async {
    try {
      final response = await client.delete('/api/batches/$id');

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  /// Registered accounts (`GET /api/admin/users`, admins only).
  static Future<List<Map<String, dynamic>>> fetchUsers() =>
      _getList('/api/admin/users');

  /// The five documented actors (`GET /api/roles`).
  ///
  /// Part A lists them as `users`, `roles`, ... tables; the admin console
  /// builds its role picker from these rows rather than a hard-coded copy.
  static Future<List<Map<String, dynamic>>> fetchRoles() =>
      _getList('/api/roles');

  /// Assigns one of the five documented roles
  /// (`PATCH /api/admin/users/{id}`, admins only).
  ///
  /// [role] may be either the label (`'Extension Worker'`) or the backend
  /// slug (`'extension_worker'`); the server normalises both.
  static Future<Map<String, dynamic>> updateUserRole(
      int userId, String role) async {
    try {
      final response =
          await client.patch('/api/admin/users/$userId', data: {'role': role});

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      return _asMap(response.data);
    } on Object catch (error) {
      throw toApiException(error);
    }
  }

  // ----------------------------------------------------------- classification

  /// Sends a cut-test photo to `POST /api/classify` (Activity 2, Part D).
  ///
  /// The backend authenticates the session, stores the photo, forwards it to
  /// the CNN inference service, writes the quality note and recommendation,
  /// saves the record, and answers with
  /// `{id, predicted_class, confidence, quality_notes, recommendation,
  /// image_url}`.
  ///
  /// [onSendProgress] drives the upload progress indicator Activity 3, Part C
  /// asks the Upload screen for.
  static Future<Map<String, dynamic>> classify({
    required Uint8List bytes,
    required String fileName,
    required String batchName,
    String notes = '',
    void Function(int sent, int total)? onSendProgress,
  }) async {
    if (await readToken() == null) {
      throw const ApiException(
          'Please sign in again before submitting a photo.', 401);
    }

    final subtype = fileName.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';

    try {
      final response = await client.post(
        '/api/classify',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: fileName,
            contentType: MediaType('image', subtype),
          ),
          'batch_name': batchName,
          'notes': notes,
        }),
        // A photo upload plus a round-trip through the CNN service is far
        // slower than a plain JSON call, which is why this one is exempt from
        // the 20 s default.
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
        onSendProgress: onSendProgress,
      );

      if ((response.statusCode ?? 0) >= 400) {
        throw ApiException(readDetail(response), response.statusCode);
      }

      final data = response.data;
      if (data is! Map) {
        throw const ApiException('Unexpected response from the server.');
      }

      return Map<String, dynamic>.from(data);
    } on Object catch (error) {
      throw toApiException(error);
    }
  }
}
