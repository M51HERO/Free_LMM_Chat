import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/core/errors.dart';
import 'package:free_llm_chat/data/llm_provider.dart';
import 'package:free_llm_chat/data/manifest_cost.dart';
import 'package:free_llm_chat/data/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'mnfst_secret_key';

/// A mock HTTP client that answers with [body] (as the raw response text).
http.Client _reply(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
  void Function(http.Request request)? onRequest,
}) {
  return MockClient.streaming((request, bodyStream) async {
    onRequest?.call(request as http.Request);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status, headers: headers);
  });
}

OpenAiCompatibleProvider _provider(
  http.Client client, {
  String baseUrl = 'http://localhost:2099/v1',
  void Function(Map<String, String>)? onHeaders,
  void Function(TokenUsage)? onUsage,
}) =>
    OpenAiCompatibleProvider(
      baseUrl: baseUrl,
      apiKey: _key,
      onHeaders: onHeaders,
      onUsage: onUsage,
      clientFactory: () => client,
    );

final _hi = [ChatMessage.create('user', 'hi')];

Future<ApiException> _failure(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  group('errorCodeOf', () {
    test('reads int and numeric-string codes', () {
      expect(errorCodeOf({'code': 429}), 429);
      expect(errorCodeOf({'code': '429'}), 429);
      expect(errorCodeOf({'code': ' 503 '}), 503);
    });

    test('maps rate-limit wording to 429', () {
      expect(errorCodeOf({'code': 'rate_limit_exceeded', 'message': 'Rate limit reached'}), 429);
      expect(errorCodeOf({'message': 'Daily quota exhausted'}), 429);
      expect(errorCodeOf('Too many requests'), 429);
    });

    test('falls back to 500', () {
      expect(errorCodeOf({'message': 'boom'}), 500);
      expect(errorCodeOf(null), 500);
    });
  });

  group('OpenAiCompatibleProvider', () {
    const sse = 'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n'
        'data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2}}\n\n'
        'data: [DONE]\n\n';

    test('streams the tokens, reports headers and usage, sends the key and the request shape',
        () async {
      http.Request? seen;
      Map<String, String>? headers;
      TokenUsage? usage;
      final p = _provider(
        _reply(
          sse,
          headers: {'x-manifest-model': 'gpt-5-mini', 'x-manifest-provider': 'openai'},
          onRequest: (r) => seen = r,
        ),
        onHeaders: (h) => headers = h,
        onUsage: (u) => usage = u,
      );

      final tokens = await p.streamChat(messages: _hi, model: 'auto').toList();

      expect(tokens.join(), 'Hello');
      expect(headers!['x-manifest-model'], 'gpt-5-mini');
      expect(headers!['x-manifest-provider'], 'openai');
      expect(usage!.promptTokens, 10);
      expect(usage!.completionTokens, 2);
      expect(seen!.url.toString(), 'http://localhost:2099/v1/chat/completions');
      expect(seen!.method, 'POST');
      expect(seen!.headers['Authorization'], 'Bearer $_key');
      final sent = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(sent['model'], 'auto');
      expect(sent['stream'], true);
      expect((sent['stream_options'] as Map)['include_usage'], true);
      expect((sent['messages'] as List).single, {'role': 'user', 'content': 'hi'});
    });

    test('the base URL works without /v1 too', () async {
      http.Request? seen;
      final p = _provider(
        _reply(sse, onRequest: (r) => seen = r),
        baseUrl: 'https://app.manifest.build',
      );
      await p.streamChat(messages: _hi, model: 'openai/gpt-4o').toList();
      expect(seen!.url.toString(), 'https://app.manifest.build/v1/chat/completions');
      expect((jsonDecode(seen!.body) as Map)['model'], 'openai/gpt-4o');
    });

    test('headers are not reported for an error response', () async {
      var called = false;
      final p = _provider(
        _reply('{"error":{"message":"nope"}}', status: 401, onRequest: (_) {}),
        onHeaders: (_) => called = true,
      );
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.invalidKey);
      expect(called, isFalse);
    });

    test('fallback exhausted: header on an error status', () async {
      final p = _provider(_reply(
        '{"error":{"message":"rate limited upstream"}}',
        status: 429,
        headers: {'x-manifest-fallback-exhausted': 'true'},
      ));
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.fallbackExhausted);
      expect(e.detail, 'rate limited upstream');
    });

    test('fallback exhausted: body code without the header', () async {
      final p = _provider(_reply(
        '{"error":{"message":"every model failed","code":"fallback_exhausted"}}',
        status: 503,
      ));
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.fallbackExhausted);
    });

    test('429 and 402 map to friendly kinds', () async {
      final rate = _provider(_reply('{"error":{"message":"slow down"}}', status: 429));
      expect((await _failure(rate.streamChat(messages: _hi, model: 'auto').toList())).kind,
          ErrorKind.rateLimit);
      final pay = _provider(_reply('{"error":{"message":"billing"}}', status: 402));
      expect((await _failure(pay.streamChat(messages: _hi, model: 'auto').toList())).kind,
          ErrorKind.paymentRequired);
    });

    test('the key never appears in an error message', () async {
      final p = _provider(_reply('{"error":{"message":"bad key $_key"}}', status: 400));
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.detail, isNotNull);
      expect(e.detail, isNot(contains(_key)));
      expect(e.detail, contains('***'));
    });

    test('an error object inside the stream fails the request', () async {
      final p = _provider(_reply('data: {"error":{"message":"boom","code":503}}\n\n'));
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.server);
    });

    test('a non-streamed JSON completion is shown as one chunk', () async {
      Map<String, String>? headers;
      TokenUsage? usage;
      final p = _provider(
        _reply(
          '{"choices":[{"message":{"content":"Whole answer"}}],'
          '"usage":{"prompt_tokens":3,"completion_tokens":4}}',
          headers: {'x-manifest-model': 'm'},
        ),
        onHeaders: (h) => headers = h,
        onUsage: (u) => usage = u,
      );
      final tokens = await p.streamChat(messages: _hi, model: 'auto').toList();
      expect(tokens.join(), 'Whole answer');
      expect(headers!['x-manifest-model'], 'm');
      expect(usage!.completionTokens, 4);
    });

    test('a Manifest message arrives as ordinary text (the controller turns it into an error)',
        () async {
      const text = '[🦚 Manifest M200] You hit your cost limit';
      final p = _provider(_reply(
        'data: {"choices":[{"delta":{"content":"$text"}}]}\n\ndata: [DONE]\n\n',
        headers: {'x-manifest-model': 'manifest', 'x-manifest-provider': 'manifest'},
      ));
      final tokens = await p.streamChat(messages: _hi, model: 'auto').toList();
      expect(parseManifestNotice(tokens.join())!.code, 'M200');
    });

    test('connection refused means Manifest is not running', () async {
      final p = _provider(MockClient((request) async =>
          throw SocketException('Connection refused', osError: OSError('Connection refused', 111))));
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.connectionRefused);
    });

    test('other socket errors are plain network errors', () async {
      final p = _provider(MockClient((request) async => throw SocketException('Network is down')));
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.network);
    });

    test('an unusable base URL is a configuration error, nothing is sent', () async {
      var sent = false;
      final p = _provider(_reply(sse, onRequest: (_) => sent = true),
          baseUrl: 'http://example.com'); // plain http to a public host
      final e = await _failure(p.streamChat(messages: _hi, model: 'auto').toList());
      expect(e.kind, ErrorKind.notConfigured);
      expect(sent, isFalse);
    });
  });
}
