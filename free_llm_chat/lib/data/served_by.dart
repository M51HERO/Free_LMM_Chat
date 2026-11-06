import 'manifest_cost.dart';
import 'manifest_headers.dart';

/// Who served one assistant reply and how it is billed. Stored with the chat
/// history so the badge survives restarts.
///
/// The billing class is a snapshot taken when the reply started: later price
/// changes in Manifest do not rewrite old replies.
class ServedBy {
  const ServedBy({
    required this.costClass,
    this.model,
    this.provider,
    this.fallbackFrom,
    this.inputPrice,
    this.outputPrice,
    this.answeredByManifest = false,
    this.headersMissing = false,
    this.ambiguous = false,
    this.listUnavailable = false,
    this.promptTokens,
    this.completionTokens,
    this.estimatedCostUsd,
  });

  factory ServedBy.fromJson(Map<String, dynamic> j) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    int? i(Object? v) => v is num ? v.toInt() : null;
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    final name = j['costClass'];
    return ServedBy(
      costClass: CostClass.values.firstWhere(
        (c) => c.name == name,
        orElse: () => CostClass.unknown,
      ),
      model: s(j['model']),
      provider: s(j['provider']),
      fallbackFrom: s(j['fallbackFrom']),
      inputPrice: d(j['inputPrice']),
      outputPrice: d(j['outputPrice']),
      answeredByManifest: j['answeredByManifest'] == true,
      headersMissing: j['headersMissing'] == true,
      ambiguous: j['ambiguous'] == true,
      listUnavailable: j['listUnavailable'] == true,
      promptTokens: i(j['promptTokens']),
      completionTokens: i(j['completionTokens']),
      estimatedCostUsd: d(j['estimatedCostUsd']),
    );
  }

  final CostClass costClass;
  final String? model;
  final String? provider;

  /// Set when Manifest's fallback chain moved to another model.
  final String? fallbackFrom;

  /// USD per 1M tokens at the time of the reply (null = not reported).
  final double? inputPrice;
  final double? outputPrice;

  /// Manifest answered by itself: no model was called.
  final bool answeredByManifest;

  /// The response had no `X-Manifest-Model` header: the served model is unknown.
  final bool headersMissing;

  /// Several list entries matched with different billing.
  final bool ambiguous;

  /// The price list could not be loaded, so the class is "unknown" by default.
  final bool listUnavailable;

  final int? promptTokens;
  final int? completionTokens;

  /// Estimate only, and only for paid models with usage data in the response.
  final double? estimatedCostUsd;

  bool get isPaid => costClass == CostClass.paid;

  ServedBy withUsage(TokenUsage u) {
    final est = isPaid
        ? estimateCostUsd(u, ModelCost(input: inputPrice, output: outputPrice))
        : null;
    return ServedBy(
      costClass: costClass,
      model: model,
      provider: provider,
      fallbackFrom: fallbackFrom,
      inputPrice: inputPrice,
      outputPrice: outputPrice,
      answeredByManifest: answeredByManifest,
      headersMissing: headersMissing,
      ambiguous: ambiguous,
      listUnavailable: listUnavailable,
      promptTokens: u.promptTokens,
      completionTokens: u.completionTokens,
      estimatedCostUsd: est,
    );
  }

  Map<String, dynamic> toJson() => {
        'costClass': costClass.name,
        if (model != null) 'model': model,
        if (provider != null) 'provider': provider,
        if (fallbackFrom != null) 'fallbackFrom': fallbackFrom,
        if (inputPrice != null) 'inputPrice': inputPrice,
        if (outputPrice != null) 'outputPrice': outputPrice,
        if (answeredByManifest) 'answeredByManifest': true,
        if (headersMissing) 'headersMissing': true,
        if (ambiguous) 'ambiguous': true,
        if (listUnavailable) 'listUnavailable': true,
        if (promptTokens != null) 'promptTokens': promptTokens,
        if (completionTokens != null) 'completionTokens': completionTokens,
        if (estimatedCostUsd != null) 'estimatedCostUsd': estimatedCostUsd,
      };
}

/// Combines the response headers with the cached price list.
///
/// - no `X-Manifest-Model` header -> "served model unknown" (amber);
/// - `manifest` as model -> Manifest answered by itself, nothing was billed;
/// - otherwise the served model is looked up in [catalog] (unknown if absent
///   or if the list could not be loaded).
ServedBy buildServed(ServedInfo info, ModelCatalog catalog) {
  if (!info.hasServedModel) {
    return ServedBy(
      costClass: CostClass.unknown,
      headersMissing: true,
      listUnavailable: !catalog.available,
    );
  }
  if (info.answeredByManifest) {
    return ServedBy(
      costClass: CostClass.free,
      model: info.model,
      provider: info.provider,
      answeredByManifest: true,
    );
  }
  final r = catalog.lookup(info.model, provider: info.provider);
  return ServedBy(
    costClass: r.costClass,
    model: info.model,
    provider: info.provider,
    fallbackFrom: info.fallbackFrom,
    inputPrice: r.cost?.input,
    outputPrice: r.cost?.output,
    ambiguous: r.ambiguous,
    listUnavailable: !catalog.available,
  );
}
