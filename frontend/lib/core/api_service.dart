import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Base URL of the CacaoGrade AI FastAPI backend.
///
/// - Windows / macOS / Linux / iOS simulator -> http://127.0.0.1:8000
/// - Android emulator                         -> http://10.0.2.2:8000
/// - Real phone                               -> http://<your-PC-LAN-IP>:8000
///
/// Override it without editing this file by passing a `--dart-define`, which is
/// how the HTTPS setup (Activity 2, Part A) switches schemes:
///
/// ```bash
/// flutter run -d chrome --dart-define=CACAO_API=https://127.0.0.1:8000
/// ```
///
/// The HTTPS setup uses the self-signed certificate from `backend/make_cert.py`,
/// so the browser will warn you once on localhost. Accept it for localhost, and
/// use a real certificate for anything public.
const String kApiBaseUrl = String.fromEnvironment(
  'CACAO_API',
  defaultValue: 'http://127.0.0.1:8000',
);

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Thin HTTP client for `/api/auth/*` plus the small read-only data endpoints.
///
/// The signed-in account itself lives in [authProvider] (`core/state.dart`);
/// this class only owns the bearer token.
class CacaoApi {
  /// Swap this out in tests (see `test/auth_flow_test.dart`).
  static http.Client client = http.Client();

  static const String _tokenKey = 'cacao_auth_token';

  // ---------------------------------------------------------------- helpers

  static String _readDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final detail = body is Map ? body['detail'] : null;

      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
      }
      return 'Server returned an error (${response.statusCode}).';
    } catch (_) {
      return 'Server returned an error (${response.statusCode}).';
    }
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

  // -------------------------------------------------------------------- api

  static Future<AppUser> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await client
          .post(
            Uri.parse('$kApiBaseUrl$path'),
            headers: const {'Content-Type': 'application/json'},
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw ApiException(_readDetail(response), response.statusCode);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final user = userFromApi(Map<String, dynamic>.from(data['user'] as Map));
      final token = data['token'] as String?;

      if (token != null) await saveToken(token);

      return user;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Cannot reach the backend server. Make sure it is running on port $kApiBaseUrl.');
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
      final response = await client
          .get(
            Uri.parse('$kApiBaseUrl/api/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        await clearToken();
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return userFromApi(Map<String, dynamic>.from(data['user'] as Map));
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
      await client
          .post(
            Uri.parse('$kApiBaseUrl/api/auth/logout'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Local session is already cleared, nothing else to do.
    }
  }

  // ------------------------------------------------------------- data calls

  static Future<List<Map<String, dynamic>>> _getList(String path) async {
    final token = await readToken();

    try {
      final response = await client
          .get(
            Uri.parse('$kApiBaseUrl$path'),
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw ApiException(_readDetail(response), response.statusCode);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['data'];
      if (items is! List) return [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Cannot reach the backend server. Make sure it is running on port $kApiBaseUrl.');
    }
  }

  /// Fermentation classifications already saved in PostgreSQL.
  static Future<List<Map<String, dynamic>>> fetchHistory() =>
      _getList('/api/history');

  /// Batch records stored in PostgreSQL (`GET /api/batches`).
  static Future<List<Map<String, dynamic>>> fetchBatches() =>
      _getList('/api/batches');

  /// Dashboard aggregation (`GET /api/trends`): stage counts, average
  /// confidence, and the daily series the backend computed.
  static Future<Map<String, dynamic>> fetchTrends() async {
    final token = await readToken();

    try {
      final response = await client
          .get(
            Uri.parse('$kApiBaseUrl/api/trends'),
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw ApiException(_readDetail(response), response.statusCode);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Cannot reach the backend server. Make sure it is running on $kApiBaseUrl.');
    }
  }

  /// Removes a batch (`DELETE /api/batches/{id}`). Farmers may only delete
  /// their own; staff and admins may delete any.
  static Future<void> deleteBatch(int id) async {
    final token = await readToken();

    try {
      final response = await client
          .delete(
            Uri.parse('$kApiBaseUrl/api/batches/$id'),
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw ApiException(_readDetail(response), response.statusCode);
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Cannot reach the backend server. Make sure it is running on $kApiBaseUrl.');
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
    final token = await readToken();

    try {
      final response = await client
          .patch(
            Uri.parse('$kApiBaseUrl/api/admin/users/$userId'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'role': role}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw ApiException(_readDetail(response), response.statusCode);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Cannot reach the backend server. Make sure it is running on $kApiBaseUrl.');
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
  static Future<Map<String, dynamic>> classify({
    required Uint8List bytes,
    required String fileName,
    required String batchName,
    String notes = '',
  }) async {
    final token = await readToken();
    if (token == null) {
      throw ApiException('Please sign in again before submitting a photo.', 401);
    }

    final subtype = fileName.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$kApiBaseUrl/api/classify'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType('image', subtype),
        ))
        ..fields['batch_name'] = batchName
        ..fields['notes'] = notes;

      final streamed =
          await client.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 400) {
        throw ApiException(_readDetail(response), response.statusCode);
      }

      final data = jsonDecode(response.body);
      if (data is! Map) {
        throw ApiException('Unexpected response from the server.');
      }

      return Map<String, dynamic>.from(data);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Cannot reach the backend server. Make sure it is running on $kApiBaseUrl.');
    }
  }
}
