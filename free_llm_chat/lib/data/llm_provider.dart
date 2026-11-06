import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/errors.dart';
import 'manifest_config.dart';
import 'manifest_cost.dart';
import 'manifest_headers.dart';
import 'models.dart';

/// HTTP-like status for an error object sent inside the SSE stream.
/// Providers send the code as an int, as a numeric string, or not at all
/// (then rate-limit wording in the message is used, else 500).
int errorCodeOf(Object? err) {
  if (err is Map) {
    final c = err['code'];
    if (c is int) return c;
    if (c is String) {
      final n = int.tryParse(c.trim());
      if (n != null) return n;
    }
  }
  final text = (err is Map ? '${err['message'] ?? ''}' : '$err').toLowerCase();
  if (text.contains('rate limit') ||
      text.contains('rate_limit') ||
      text.contains('quota') ||
      text.contains('too many requests')) {
    return 429;
  }
  return 500;
}

/// Cancelling the subscription of the returned stream aborts the underlying HTTP request.
abstract class LlmProvider {
  Stream<String> streamChat({required List<ChatMessage> messages, required String model});
}

typedef ClientFactory = http.Client Function();

/// Talks to Manifest: `POST {base}/v1/chat/completions`, OpenAI format, streaming.
class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    this.onHeaders,
    this.onUsage,
    this.firstByteTimeout = const Duration(seconds: 90),
    this.clientFactory,
  });

  /// Base URL typed by the user, with or without `/v1`.
  final String baseUrl;

  /// The `mnfst_...` agent key. Only ever sent in the Authorization header, never logged.
  final String apiKey;

  /// Called once with the response headers of a successful (HTTP 200) response, before
  /// the first token is read. Dart's `http` lowercases header names.
  final void Function(Map<String, String> headers)? onHeaders;

  /// Called with the `usage` object when the stream carries one (latest value wins).
  final void Function(TokenUsage usage)? onUsage;

  /// How long to wait for the response headers. Routing with fallbacks adds latency,
  /// so this is generous (Manifest's own per-attempt timeout defaults to 180 s).
  final Duration firstByteTimeout;

  /// Test hook.
  final ClientFactory? clientFactory;

  Uri get _uri => manifestEndpoint(baseUrl, 'chat/completions');

  ApiException _redact(ApiException e) {
    final d = e.detail;
    if (apiKey.isEmpty || d == null || !d.contains(apiKey)) return e;
    return ApiException(e.kind, d.replaceAll(apiKey, '***'));
  }

  @override
  Stream<String> streamChat({required List<ChatMessage> messages, required String model}) {
    final client = clientFactory?.call() ?? http.Client();
    StreamSubscription<String>? sub;
    late final StreamController<String> ctrl;
    final rawBuf = StringBuffer();
    var emitted = false;

    void shutdown() {
      sub?.cancel();
      client.close();
      if (!ctrl.isClosed) ctrl.close();
    }

    void fail(ApiException e) {
      if (!ctrl.isClosed) ctrl.addError(_redact(e));
      shutdown();
    }

    void emit(String text) {
      if (text.isEmpty || ctrl.isClosed) return;
      emitted = true;
      ctrl.add(text);
    }

    void handleLine(String line) {
      if (!line.startsWith('data:')) {
        // Not SSE: keep it, a non-streamed JSON body is handled when the stream ends.
        final t = line.trim();
        if (t.isNotEmpty &&
            !t.startsWith(':') &&
            !t.startsWith('event:') &&
            !t.startsWith('id:') &&
            !t.startsWith('retry:') &&
            rawBuf.length < 65536) {
          rawBuf.writeln(t);
        }
        return;
      }
      final data = line.substring(5).trim();
      if (data.isEmpty) return;
      if (data == '[DONE]') {
        shutdown();
        return;
      }
      try {
        final j = jsonDecode(data);
        if (j is! Map) return;
        if (j['error'] != null) {
          fail(ApiException.fromStatus(errorCodeOf(j['error']), data));
          return;
        }
        final usage = TokenUsage.fromJson(j['usage']);
        if (usage != null) onUsage?.call(usage);
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final delta = (choices.first as Map)['delta'];
          final c = delta is Map ? delta['content'] : null;
          if (c is String) emit(c);
        }
      } catch (_) {
        // Ignore keep-alive, partial or unexpected lines.
      }
    }

    /// Some answers (Manifest "buffered" responses, errors) arrive as one JSON
    /// completion instead of SSE chunks.
    void flushRaw() {
      if (emitted || rawBuf.isEmpty) return;
      final text = rawBuf.toString();
      try {
        final j = jsonDecode(text);
        if (j is! Map) return;
        if (j['error'] != null) {
          fail(ApiException.fromStatus(errorCodeOf(j['error']), text));
          return;
        }
        final usage = TokenUsage.fromJson(j['usage']);
        if (usage != null) onUsage?.call(usage);
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final msg = (choices.first as Map)['message'];
          final c = msg is Map ? msg['content'] : null;
          if (c is String) emit(c);
        }
      } catch (_) {
        // Not JSON: nothing to show.
      }
    }

    ctrl = StreamController<String>(
      onListen: () async {
        try {
          final req = http.Request('POST', _uri)
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            })
            ..body = jsonEncode({
              'model': model,
              'stream': true,
              // Manifest forwards this only to providers that support it (OpenAI, OpenRouter);
              // the others silently ignore it, so usage may be missing.
              'stream_options': {'include_usage': true},
              'messages': [
                for (final m in messages) {'role': m.role, 'content': m.content},
              ],
            });
          final res = await client.send(req).timeout(firstByteTimeout);
          if (res.statusCode != 200) {
            final body = await res.stream.bytesToString();
            final info = parseManifestHeaders(res.headers);
            fail(ApiException.fromStatus(res.statusCode, body,
                fallbackExhausted: info.fallbackExhausted));
            return;
          }
          onHeaders?.call(res.headers);
          sub = res.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                handleLine,
                onError: (Object e) => fail(ApiException(ErrorKind.network, '$e')),
                onDone: () {
                  flushRaw();
                  shutdown();
                },
                cancelOnError: true,
              );
        } on TimeoutException {
          fail(ApiException(ErrorKind.timeout));
        } on SocketException catch (e) {
          fail(ApiException(isConnectionRefused(e) ? ErrorKind.connectionRefused : ErrorKind.network));
        } on HandshakeException {
          fail(ApiException(ErrorKind.network));
        } on http.ClientException catch (e) {
          fail(ApiException(isConnectionRefused(e) ? ErrorKind.connectionRefused : ErrorKind.network));
        } on FormatException {
          fail(ApiException(ErrorKind.notConfigured));
        } catch (e) {
          fail(ApiException(ErrorKind.unknown, '$e'));
        }
      },
      onCancel: () {
        sub?.cancel();
        client.close();
      },
    );
    return ctrl.stream;
  }
}
