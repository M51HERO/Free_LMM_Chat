import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/core/errors.dart';
import 'package:free_llm_chat/data/manifest_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'mnfst_secret_key';

const _models = '{"object":"list","data":['
    '{"id":"auto","object":"model","created":0,"owned_by":"manifest"},'
    '{"id":"openai/gpt-5.4-mini","owned_by":"openai","cost":{"input":0.75,"output":4.5}},'
    '{"id":"openrouter/example-free-model","owned_by":"openrouter","cost":{"input":0,"output":0}},'
    '{"id":"mystery/model","owned_by":"mystery"}'
    ']}';

ManifestClient _client(Future<http.Response> Function(http.Request request) handler) =>
    ManifestClient(clientFactory: () => MockClient(handler));

Future<ApiException> _failure(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  test('GET /v1/models?cost=true with the key, and counts free / paid / unknown', () async {
    http.Request? seen;
    final c = await _client((r) async {
      seen = r;
      return http.Response(_models, 200);
    }).fetchModels(baseUrl: 'http://localhost:2099', key: _key);

    expect(seen!.method, 'GET');
    expect(seen!.url.toString(), 'http://localhost:2099/v1/models?cost=true');
    expect(seen!.headers['Authorization'], 'Bearer $_key');
    expect(c.concrete.length, 3);
    expect(c.freeCount, 1);
    expect(c.paidCount, 1);
    expect(c.unknownCount, 1);
    expect(c.models.first.id, 'auto');
  });

  test('a base URL already ending in /v1 gives the same request', () async {
    http.Request? seen;
    await _client((r) async {
      seen = r;
      return http.Response(_models, 200);
    }).fetchModels(baseUrl: 'https://app.manifest.build/v1/', key: _key);
    expect(seen!.url.toString(), 'https://app.manifest.build/v1/models?cost=true');
  });

  test('401 is a bad key', () async {
    final e = await _failure(_client((r) async => http.Response(
            '{"error":{"message":"[🦚 Manifest M005] I don\'t recognize this key.",'
            '"type":"auth_error","code":"manifest_auth"}}',
            401))
        .fetchModels(baseUrl: 'http://localhost:2099', key: _key));
    expect(e.kind, ErrorKind.invalidKey);
  });

  test('connection refused means Manifest is not running', () async {
    final e = await _failure(_client((r) async =>
            throw SocketException('Connection refused', osError: OSError('Connection refused', 111)))
        .fetchModels(baseUrl: 'http://localhost:2099', key: _key));
    expect(e.kind, ErrorKind.connectionRefused);
  });

  test('a response that is not a model list is an error, not an empty list', () async {
    final notJson = await _failure(_client((r) async => http.Response('<html>hi</html>', 200))
        .fetchModels(baseUrl: 'http://localhost:2099', key: _key));
    expect(notJson.kind, ErrorKind.unknown);
    final noData = await _failure(_client((r) async => http.Response('{"hello":1}', 200))
        .fetchModels(baseUrl: 'http://localhost:2099', key: _key));
    expect(noData.kind, ErrorKind.unknown);
  });

  test('an unusable base URL is a configuration error and nothing is requested', () async {
    var requested = false;
    final e = await _failure(_client((r) async {
      requested = true;
      return http.Response(_models, 200);
    }).fetchModels(baseUrl: 'http://example.com', key: _key));
    expect(e.kind, ErrorKind.notConfigured);
    expect(requested, isFalse);
  });

  test('the key is never echoed in an error message', () async {
    final e = await _failure(_client((r) async =>
            http.Response('{"error":{"message":"unknown key $_key"}}', 400))
        .fetchModels(baseUrl: 'http://localhost:2099', key: _key));
    expect(e.detail, isNot(contains(_key)));
  });
}
