import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cacao/core/api_service.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// Stands in for the FastAPI backend so the widget tests never touch a socket.
///
/// It speaks `package:http` on the handler side - the same `http.Request` the
/// suite was written against - while dio drives everything underneath. That
/// keeps the assertions (`request.url.path`, `request.headers['authorization']`,
/// the raw multipart body) reading exactly as they did, so a failure here still
/// means the *client* changed behaviour rather than the harness.
class FakeBackendAdapter implements HttpClientAdapter {
  FakeBackendAdapter(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bodyBytes =
        requestStream == null ? Uint8List(0) : await _drain(requestStream);

    final request = http.Request(options.method, options.uri);
    request.bodyBytes = bodyBytes;

    for (final entry in options.headers.entries) {
      request.headers[entry.key] = '${entry.value}';
    }

    // dio stamps `multipart/form-data; boundary=...` while finalising the
    // FormData, and not every adapter surfaces that in options.headers. Recover
    // it from the bytes so an assertion on the request header sees what the
    // server would actually receive.
    if (!request.headers.containsKey('content-type')) {
      final sniffed = _sniffContentType(bodyBytes);
      if (sniffed != null) request.headers['content-type'] = sniffed;
    }

    final response = await _handler(request);

    return _toResponseBody(response);
  }

  @override
  void close({bool force = false}) {}

  static Future<Uint8List> _drain(Stream<Uint8List> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Reads `multipart/form-data; boundary=...` out of a body that starts with
  /// the boundary line. Returns null for anything that is not multipart.
  static String? _sniffContentType(Uint8List body) {
    if (body.length < 4) return null;

    final head = String.fromCharCodes(body.sublist(0, min(body.length, 256)));
    if (!head.startsWith('--')) return null;

    final eol = head.indexOf('\r\n');
    final line = eol == -1 ? head : head.substring(0, eol);
    if (!line.startsWith('--')) return null;

    final boundary = line.substring(2).trim();
    if (boundary.isEmpty || boundary.startsWith('-')) return null;

    return 'multipart/form-data; boundary=$boundary';
  }

  static ResponseBody _toResponseBody(http.Response response) {
    var contentType = response.headers['content-type'];

    // Without a content type dio returns the body as a String, so infer one.
    // An empty body is far more likely to be "no content" than broken JSON.
    if (contentType == null || contentType.isEmpty) {
      contentType = _looksLikeJson(response.body) ? 'application/json' : 'text/plain';
    }

    return ResponseBody.fromBytes(
      response.bodyBytes,
      response.statusCode,
      headers: {Headers.contentTypeHeader: <String>[contentType]},
    );
  }

  static bool _looksLikeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    try {
      jsonDecode(trimmed);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Builds the client under test with the fake transport wired in.
Dio fakeBackend(
  Future<http.Response> Function(http.Request request) handler,
) =>
    CacaoApi.newClient(adapter: FakeBackendAdapter(handler));
