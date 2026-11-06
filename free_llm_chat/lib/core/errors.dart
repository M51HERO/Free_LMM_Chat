import 'dart:convert';
import 'dart:io' show SocketException;

enum ErrorKind {
  missingKey,
  notConfigured,
  invalidKey,
  rateLimit,
  paymentRequired,
  spendLimit,
  modelNotAvailable,
  fallbackExhausted,
  connectionRefused,
  network,
  timeout,
  server,
  badRequest,
  unknown,
}

/// A message Manifest itself wrote as the assistant text, for example
/// `[🦚 Manifest M200] You hit your cost limit ...`.
///
/// Manifest's docs say a chat/streaming client can get such errors as an HTTP 200
/// completion (a spend-limit block is always one), so they must not be shown
/// as a normal answer.
class ManifestNotice {
  const ManifestNotice(this.code, this.text);

  /// For example `M200`.
  final String code;

  /// The full message text.
  final String text;
}

final RegExp _noticeRe = RegExp(r'^\s*\[[^\]\n]{0,24}?Manifest\s+(M\d{3})\]');

ManifestNotice? parseManifestNotice(String content) {
  final m = _noticeRe.firstMatch(content);
  if (m == null) return null;
  return ManifestNotice(m.group(1)!, content.trim());
}

ErrorKind? _kindOfCode(String code) => switch (code) {
      'M005' => ErrorKind.invalidKey,
      'M101' || 'M302' => ErrorKind.modelNotAvailable,
      'M200' => ErrorKind.spendLimit,
      'M201' || 'M202' || 'M203' => ErrorKind.rateLimit,
      'M204' => ErrorKind.paymentRequired,
      _ => null,
    };

/// True when the server refused the connection (Manifest is not running or the
/// port is wrong): errno 111 (Linux/Android), 61 (macOS), 10061/1225 (Windows).
bool isConnectionRefused(Object e) {
  if (e is SocketException) {
    final code = e.osError?.errorCode;
    if (code == 111 || code == 61 || code == 10061 || code == 1225) return true;
  }
  final t = '$e'.toLowerCase();
  return t.contains('connection refused') ||
      t.contains('refused the network connection') ||
      t.contains('errno = 111') ||
      t.contains('errno = 10061');
}

class ApiException implements Exception {
  ApiException(this.kind, [this.detail]);

  final ErrorKind kind;
  final String? detail;

  /// [fallbackExhausted] is true when the response carried
  /// `X-Manifest-Fallback-Exhausted: true`; a body code `fallback_exhausted` counts too.
  /// In both cases the HTTP status is the primary model's real error status.
  factory ApiException.fromStatus(int code, String body, {bool fallbackExhausted = false}) {
    final detail = _extract(body);
    if (fallbackExhausted || _bodyCode(body) == 'fallback_exhausted') {
      return ApiException(ErrorKind.fallbackExhausted, detail);
    }
    var kind = switch (code) {
      401 || 403 => ErrorKind.invalidKey,
      402 => ErrorKind.paymentRequired,
      429 => ErrorKind.rateLimit,
      400 || 404 || 422 => ErrorKind.badRequest,
      >= 500 => ErrorKind.server,
      _ => ErrorKind.unknown,
    };
    final notice = detail == null ? null : parseManifestNotice(detail);
    final byCode = notice == null ? null : _kindOfCode(notice.code);
    if (byCode != null) kind = byCode;
    return ApiException(kind, detail);
  }

  /// From a Manifest message found in an HTTP 200 reply.
  factory ApiException.fromNotice(ManifestNotice n) =>
      ApiException(_kindOfCode(n.code) ?? ErrorKind.unknown, _cut(n.text));

  static String? _bodyCode(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map) {
        final e = d['error'];
        final c = e is Map ? e['code'] : d['code'];
        if (c is String) return c;
      }
    } catch (_) {}
    return null;
  }

  static String? _extract(String body) {
    try {
      var d = jsonDecode(body);
      if (d is List && d.isNotEmpty) d = d.first;
      if (d is Map) {
        final e = d['error'] ?? d['message'] ?? d['detail'];
        if (e is Map && e['message'] != null) return _cut('${e['message']}');
        if (e != null) return _cut('$e');
      }
    } catch (_) {}
    final t = body.trim();
    return t.isEmpty ? null : _cut(t);
  }

  static String _cut(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  @override
  String toString() => 'ApiException($kind, $detail)';
}
