import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../core/errors.dart';
import 'manifest_config.dart';
import 'manifest_cost.dart';

/// Calls `GET {base}/v1/models?cost=true` and turns failures into [ApiException]s.
class ManifestClient {
  ManifestClient({http.Client Function()? clientFactory, this.timeout = const Duration(seconds: 15)})
      : _factory = clientFactory ?? (() => http.Client());

  final http.Client Function() _factory;
  final Duration timeout;

  Future<ModelCatalog> fetchModels({required String baseUrl, required String key}) async {
    final Uri uri;
    try {
      uri = manifestEndpoint(baseUrl, 'models', query: const {'cost': 'true'});
    } on FormatException {
      throw ApiException(ErrorKind.notConfigured);
    }
    final client = _factory();
    try {
      final res = await client.get(uri, headers: {
        'Authorization': 'Bearer $key',
        'Accept': 'application/json',
      }).timeout(timeout);
      if (res.statusCode != 200) {
        throw _redact(ApiException.fromStatus(res.statusCode, res.body), key);
      }
      try {
        return ModelCatalog.fromJson(jsonDecode(res.body));
      } on FormatException {
        throw ApiException(ErrorKind.unknown, 'Unexpected response from /v1/models');
      }
    } on TimeoutException {
      throw ApiException(ErrorKind.timeout);
    } on SocketException catch (e) {
      throw ApiException(isConnectionRefused(e) ? ErrorKind.connectionRefused : ErrorKind.network);
    } on http.ClientException catch (e) {
      throw ApiException(isConnectionRefused(e) ? ErrorKind.connectionRefused : ErrorKind.network);
    } finally {
      client.close();
    }
  }
}

/// Never let the key leak into an error message.
ApiException _redact(ApiException e, String key) {
  final d = e.detail;
  if (key.isEmpty || d == null || !d.contains(key)) return e;
  return ApiException(e.kind, d.replaceAll(key, '***'));
}
