import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/core/errors.dart';

void main() {
  group('ApiException.fromStatus', () {
    test('maps HTTP statuses', () {
      expect(ApiException.fromStatus(401, '').kind, ErrorKind.invalidKey);
      expect(ApiException.fromStatus(403, '').kind, ErrorKind.invalidKey);
      expect(ApiException.fromStatus(402, '').kind, ErrorKind.paymentRequired);
      expect(ApiException.fromStatus(429, '').kind, ErrorKind.rateLimit);
      expect(ApiException.fromStatus(400, '').kind, ErrorKind.badRequest);
      expect(ApiException.fromStatus(404, '').kind, ErrorKind.badRequest);
      expect(ApiException.fromStatus(500, '').kind, ErrorKind.server);
      expect(ApiException.fromStatus(529, '').kind, ErrorKind.server);
      expect(ApiException.fromStatus(418, '').kind, ErrorKind.unknown);
    });

    test('fallback exhausted by header, whatever the status', () {
      final e = ApiException.fromStatus(429, '{"error":{"message":"rate limited"}}',
          fallbackExhausted: true);
      expect(e.kind, ErrorKind.fallbackExhausted);
      expect(e.detail, 'rate limited');
      expect(ApiException.fromStatus(503, '', fallbackExhausted: true).kind,
          ErrorKind.fallbackExhausted);
    });

    test('fallback exhausted by body code', () {
      final e = ApiException.fromStatus(
          503, '{"error":{"message":"all models failed","code":"fallback_exhausted"}}');
      expect(e.kind, ErrorKind.fallbackExhausted);
      expect(e.detail, 'all models failed');
    });

    test('a provider error code in the body is not a fallback-exhausted error', () {
      final e = ApiException.fromStatus(429, '{"error":{"message":"slow down","code":"rate_limit"}}');
      expect(e.kind, ErrorKind.rateLimit);
    });

    test('the Manifest code in the message wins over the status', () {
      const body =
          '{"error":{"message":"[🦚 Manifest M005] I don\'t recognize this key.","type":"auth_error","code":"manifest_auth"}}';
      expect(ApiException.fromStatus(400, body).kind, ErrorKind.invalidKey);
      expect(ApiException.fromStatus(401, body).detail, contains('M005'));
    });

    test('plain-text bodies become the detail, cut to 200 characters', () {
      final e = ApiException.fromStatus(500, 'x' * 500);
      expect(e.kind, ErrorKind.server);
      expect(e.detail!.length, lessThanOrEqualTo(201));
    });
  });

  group('parseManifestNotice (errors Manifest returns as a 200 reply)', () {
    test('recognizes a Manifest message and its code', () {
      final n = parseManifestNotice(
          '[🦚 Manifest M200] You hit your cost limit: \$12.50 used, \$10.00/day allowed.');
      expect(n, isNotNull);
      expect(n!.code, 'M200');
      expect(n.text, contains('cost limit'));
    });

    test('tolerates leading whitespace and a missing emoji', () {
      expect(parseManifestNotice('  \n[Manifest M005] bad key')!.code, 'M005');
    });

    test('ignores normal answers', () {
      expect(parseManifestNotice('Hello! How can I help?'), isNull);
      expect(parseManifestNotice('[a link](https://example.com) is here'), isNull);
      expect(parseManifestNotice('[Manifest M5] too short'), isNull);
      expect(parseManifestNotice('The text [🦚 Manifest M200] is quoted later'), isNull);
      expect(parseManifestNotice(''), isNull);
    });

    test('fromNotice maps the documented codes', () {
      ErrorKind kind(String code) =>
          ApiException.fromNotice(ManifestNotice(code, '[Manifest $code] text')).kind;
      expect(kind('M005'), ErrorKind.invalidKey);
      expect(kind('M200'), ErrorKind.spendLimit);
      expect(kind('M201'), ErrorKind.rateLimit);
      expect(kind('M202'), ErrorKind.rateLimit);
      expect(kind('M203'), ErrorKind.rateLimit);
      expect(kind('M204'), ErrorKind.paymentRequired);
      expect(kind('M302'), ErrorKind.modelNotAvailable);
      expect(kind('M101'), ErrorKind.modelNotAvailable);
      expect(kind('M999'), ErrorKind.unknown);
    });
  });

  group('isConnectionRefused', () {
    test('Linux/Android, macOS and Windows error numbers', () {
      expect(isConnectionRefused(SocketException('x', osError: OSError('Connection refused', 111))),
          isTrue);
      expect(isConnectionRefused(SocketException('x', osError: OSError('refused', 61))), isTrue);
      expect(isConnectionRefused(SocketException('x', osError: OSError('refused', 10061))),
          isTrue);
    });

    test('by message', () {
      expect(isConnectionRefused(SocketException('Connection refused')), isTrue);
    });

    test('other network failures are not "refused"', () {
      expect(
          isConnectionRefused(
              SocketException('Failed host lookup', osError: OSError('Name or service not known', -2))),
          isFalse);
      expect(isConnectionRefused(const FormatException('bad')), isFalse);
    });
  });
}
