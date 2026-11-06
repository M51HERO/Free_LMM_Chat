/// What the `X-Manifest-*` response headers say about one reply.
///
/// Documented headers (https://manifest.build docs, "Headers"):
/// `X-Manifest-Model` (model that actually served the reply), `X-Manifest-Provider`,
/// `X-Manifest-Tier`, `X-Manifest-Reason`; on fallback `X-Manifest-Fallback-From` and
/// `X-Manifest-Fallback-Index`; when every model failed `X-Manifest-Fallback-Exhausted`.
/// A request rejected before routing (bad key, quota, rate limit) carries none of them.
class ServedInfo {
  const ServedInfo({
    this.model,
    this.provider,
    this.tier,
    this.reason,
    this.fallbackFrom,
    this.fallbackIndex,
    this.fallbackExhausted = false,
  });

  final String? model;
  final String? provider;
  final String? tier;
  final String? reason;
  final String? fallbackFrom;
  final int? fallbackIndex;
  final bool fallbackExhausted;

  bool get hasServedModel => model != null;

  /// Manifest answered by itself (spend block, no provider connected, model it cannot
  /// serve): both model and provider headers report `manifest` and no model was called.
  bool get answeredByManifest => (model ?? '').toLowerCase() == 'manifest';

  bool get fellBack => fallbackFrom != null;
}

/// Header names are matched case-insensitively (Dart's `http` lowercases them,
/// but the proxy emits `X-Manifest-*`). Empty values count as missing.
ServedInfo parseManifestHeaders(Map<String, String> headers) {
  final lower = <String, String>{
    for (final e in headers.entries) e.key.toLowerCase(): e.value,
  };
  String? read(String name) {
    final v = lower[name]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  return ServedInfo(
    model: read('x-manifest-model'),
    provider: read('x-manifest-provider'),
    tier: read('x-manifest-tier'),
    reason: read('x-manifest-reason'),
    fallbackFrom: read('x-manifest-fallback-from'),
    fallbackIndex: int.tryParse(read('x-manifest-fallback-index') ?? ''),
    fallbackExhausted: (read('x-manifest-fallback-exhausted') ?? '').toLowerCase() == 'true',
  );
}
