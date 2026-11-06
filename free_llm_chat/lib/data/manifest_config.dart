import 'dart:io' show InternetAddress, InternetAddressType;

/// Self-hosted Manifest (Docker) default address.
const String kManifestSelfHostedUrl = 'http://localhost:2099';

/// Manifest Cloud. The "Set up agent" dialog may show a different base URL:
/// the Settings field stays editable.
const String kManifestCloudUrl = 'https://app.manifest.build';

/// The synthetic model: Manifest picks the real model (routing + fallbacks).
const String kAutoModel = 'auto';

/// Every Manifest key starts with this prefix.
const String kKeyPrefix = 'mnfst_';

enum BaseUrlProblem { empty, invalid, cleartextNotLocal }

/// Result of [checkBaseUrl]: either a normalized URL or the problem found.
class BaseUrlResult {
  const BaseUrlResult.ok(this.url) : problem = null;
  const BaseUrlResult.bad(this.problem) : url = null;

  /// Normalized base URL without a trailing slash and without `/v1`.
  final String? url;
  final BaseUrlProblem? problem;

  bool get ok => url != null;
}

/// True for loopback names/addresses (`localhost`, `127.x.x.x`, `::1`).
bool isLoopbackHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  final ip = InternetAddress.tryParse(h);
  return ip != null && ip.isLoopback;
}

/// True for hosts where plain `http://` is acceptable: loopback, private LAN
/// ranges, link-local, CGNAT/Tailscale (100.64.0.0/10), IPv6 unique-local,
/// single-label names (`my-nas`) and common LAN suffixes.
bool isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h.isEmpty) return false;
  if (isLoopbackHost(h)) return true;
  final ip = InternetAddress.tryParse(h);
  if (ip != null) {
    if (ip.isLinkLocal) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      if (b[0] == 10) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
      return false;
    }
    return (b[0] & 0xFE) == 0xFC; // fc00::/7
  }
  if (!h.contains('.')) return true;
  return h.endsWith('.local') ||
      h.endsWith('.lan') ||
      h.endsWith('.home.arpa') ||
      h.endsWith('.internal');
}

String _hostOfSchemeless(String s) {
  var h = s.split(RegExp(r'[/?#]')).first;
  final at = h.lastIndexOf('@');
  if (at >= 0) h = h.substring(at + 1);
  if (h.startsWith('[')) {
    final end = h.indexOf(']');
    return end > 0 ? h.substring(1, end) : h;
  }
  final colon = h.lastIndexOf(':');
  if (colon > 0 && int.tryParse(h.substring(colon + 1)) != null) {
    h = h.substring(0, colon);
  }
  return h;
}

String _trimSlashes(String s) => s.replaceAll(RegExp(r'/+$'), '');

/// Normalizes what the user typed into a base URL **without** `/v1`.
///
/// - accepts it with or without a trailing `/v1` (and a pasted
///   `/v1/chat/completions` or `/v1/models`), with or without trailing slashes;
/// - a missing scheme becomes `http://` for local/LAN hosts, `https://` otherwise;
/// - drops user-info, query and fragment (credentials never stay in the URL);
/// - refuses plain `http://` for hosts that are not local/LAN, because the
///   agent key would travel unencrypted (Android allows cleartext globally, so
///   this is enforced here).
BaseUrlResult checkBaseUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return const BaseUrlResult.bad(BaseUrlProblem.empty);
  if (!s.contains('://')) {
    final host = _hostOfSchemeless(s);
    s = '${isLocalHost(host) ? 'http' : 'https'}://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return const BaseUrlResult.bad(BaseUrlProblem.invalid);
  }
  if (uri.scheme == 'http' && !isLocalHost(uri.host)) {
    return const BaseUrlResult.bad(BaseUrlProblem.cleartextNotLocal);
  }
  var path = _trimSlashes(uri.path);
  path = _trimSlashes(
      path.replaceFirst(RegExp(r'/(chat/completions|models)$', caseSensitive: false), ''));
  path = _trimSlashes(path.replaceFirst(RegExp(r'/v1$', caseSensitive: false), ''));
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return BaseUrlResult.ok('${uri.scheme}://$host$port$path');
}

/// `{base}/v1/{path}` for a base typed with or without `/v1`.
/// Throws [FormatException] when the base URL is not acceptable.
Uri manifestEndpoint(String baseUrl, String path, {Map<String, String>? query}) {
  final r = checkBaseUrl(baseUrl);
  if (!r.ok) throw const FormatException('Invalid base URL');
  final uri = Uri.parse('${r.url}/v1/$path');
  return query == null ? uri : uri.replace(queryParameters: query);
}
