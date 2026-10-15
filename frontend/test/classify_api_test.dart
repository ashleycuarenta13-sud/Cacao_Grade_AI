import 'dart:convert';
import 'dart:typed_data';

import 'package:cacao/core/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';

/// Covers the Flutter side of Activity 2, Part D: the client sends the photo
/// with the session token and renders whatever business logic the backend
/// answered with.
void main() {
  const payload = {
    'status': 'success',
    'id': 42,
    'predicted_class': 'well_fermented',
    'confidence': 0.87,
    'quality_notes': 'Cut surface is an even rich brown.',
    'recommendation': 'Well-fermented cacao bean.',
    'image_url': '/uploads/abc123.jpg',
    'engine': 'heuristic',
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({'cacao_auth_token': 'test-token'});
  });

  test('classify posts the photo as multipart with the bearer token', () async {
    http.Request? seen;

    CacaoApi.client = fakeBackend((request) async {
      seen = request;
      return http.Response(jsonEncode(payload), 200,
          headers: {'content-type': 'application/json'});
    });

    final result = await CacaoApi.classify(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      fileName: 'cut-test.png',
      batchName: 'North Plot 001',
      notes: 'Harvested after six days.',
    );

    // The payload the result screen renders.
    expect(result['predicted_class'], 'well_fermented');
    expect(result['confidence'], 0.87);
    expect(result['quality_notes'], isNotEmpty);
    expect(result['recommendation'], isNotEmpty);
    expect(result['image_url'], '/uploads/abc123.jpg');

    expect(seen, isNotNull);
    expect(seen!.method, 'POST');
    expect(seen!.url.path, '/api/classify');
    expect(seen!.headers['authorization'], 'Bearer test-token');
    expect(seen!.headers['content-type'], contains('multipart/form-data'));

    final body = utf8.decode(seen!.bodyBytes);
    // dio and package:http differ only in how they capitalise a part header,
    // so the check is on the value rather than on the spelling.
    final wire = body.toLowerCase();
    expect(wire, contains('content-type: image/png'));
    expect(body, contains('filename="cut-test.png"'));
    expect(body, contains('North Plot 001'));
    expect(body, contains('Harvested after six days.'));
    expect(body, contains('cut-test.png'));
  });

  test('classify surfaces the backend error and its status code', () async {
    CacaoApi.client = fakeBackend((request) async => http.Response(
        jsonEncode({'detail': 'Session expired or not logged in.'}), 401,
        headers: {'content-type': 'application/json'}));

    await expectLater(
      CacaoApi.classify(
        bytes: Uint8List.fromList([9]),
        fileName: 'a.jpg',
        batchName: 'x',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Session expired or not logged in.')
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('classify reports an unreachable backend instead of failing silently',
      () async {
    CacaoApi.client =
        fakeBackend((request) async => throw http.ClientException('down'));

    await expectLater(
      CacaoApi.classify(
        bytes: Uint8List.fromList([9]),
        fileName: 'a.jpg',
        batchName: 'x',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('the part content type follows the file extension', () async {
    Future<String> send(String fileName) async {
      Uint8List? bodyBytes;

      CacaoApi.client = fakeBackend((request) async {
        bodyBytes = request.bodyBytes;
        return http.Response(jsonEncode(payload), 200,
            headers: {'content-type': 'application/json'});
      });

      await CacaoApi.classify(
        bytes: Uint8List.fromList([0]),
        fileName: fileName,
        batchName: 'x',
      );

      return utf8.decode(bodyBytes!);
    }

    expect(await send('beans.PNG').then((b) => b.toLowerCase()),
        contains('content-type: image/png'));
    expect(await send('beans.jpg').then((b) => b.toLowerCase()),
        contains('content-type: image/jpeg'));
  });
}
