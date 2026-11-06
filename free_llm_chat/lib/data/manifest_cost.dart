import 'manifest_config.dart';

/// How a model is billed, as far as the app can tell.
///
/// Manifest has no "free/paid" flag: `GET /v1/models?cost=true` only returns
/// per-1M-token prices, so the app classifies by itself:
/// - [paid]: input > 0 or output > 0;
/// - [free]: both prices are 0 (no per-token charge: free OR covered by a
///   subscription);
/// - [unknown]: no price data, only one price and it is 0, or the model is not
///   in the list. Treated as possibly paid.
enum CostClass { free, paid, unknown }

/// Prices in USD per 1M tokens. A null field means Manifest did not report it.
class ModelCost {
  const ModelCost({this.input, this.output});

  final double? input;
  final double? output;
}

double? _validPrice(double? v) => (v == null || v.isNaN || v.isInfinite || v < 0) ? null : v;

CostClass classifyCost(ModelCost? cost) {
  if (cost == null) return CostClass.unknown;
  final i = _validPrice(cost.input);
  final o = _validPrice(cost.output);
  if ((i ?? 0.0) > 0.0 || (o ?? 0.0) > 0.0) return CostClass.paid;
  if (i == 0.0 && o == 0.0) return CostClass.free;
  return CostClass.unknown;
}

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _asInt(Object? v) => v is num ? v.toInt() : null;

class ManifestModel {
  const ManifestModel({required this.id, this.ownedBy, this.cost});

  final String id;
  final String? ownedBy;
  final ModelCost? cost;

  bool get isAuto => id == kAutoModel;
  CostClass get costClass => classifyCost(cost);

  /// Parses one entry of `data` in the `/v1/models` response (null if unusable).
  static ManifestModel? tryParse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final owner = j['owned_by'];
    ModelCost? cost;
    final c = j['cost'];
    if (c is Map) {
      final input = _asDouble(c['input']);
      final output = _asDouble(c['output']);
      if (input != null || output != null) cost = ModelCost(input: input, output: output);
    }
    return ManifestModel(id: id, ownedBy: owner is String ? owner : null, cost: cost);
  }
}

/// Result of looking a model up in the catalog.
class ModelLookup {
  const ModelLookup({required this.costClass, this.cost, this.matchedId, this.ambiguous = false});

  final CostClass costClass;
  final ModelCost? cost;

  /// The catalog ID that matched (null when nothing, or several different things, matched).
  final String? matchedId;

  /// Several catalog entries match with different billing (e.g. a normal route and a
  /// `-subscription` route of the same model): the app cannot tell which one served.
  final bool ambiguous;

  bool get found => matchedId != null;
}

/// The model list with prices (kept in memory only).
class ModelCatalog {
  ModelCatalog(List<ManifestModel> list, {this.fetchedAt, this.available = true})
      : models = List<ManifestModel>.unmodifiable(_withAutoFirst(list));

  /// Nothing known: not configured yet, or the last fetch failed.
  /// Every lookup returns [CostClass.unknown].
  ModelCatalog.unavailable()
      : models = const [ManifestModel(id: kAutoModel)],
        fetchedAt = null,
        available = false;

  /// Parses the `/v1/models?cost=true` body. Throws [FormatException] if it
  /// is not an OpenAI-style model list. Unusable entries are skipped.
  factory ModelCatalog.fromJson(Object? body, {DateTime? now}) {
    if (body is! Map || body['data'] is! List) {
      throw const FormatException('Unexpected /v1/models response');
    }
    final out = <ManifestModel>[];
    for (final e in body['data'] as List) {
      final m = ManifestModel.tryParse(e);
      if (m != null) out.add(m);
    }
    return ModelCatalog(out, fetchedAt: now ?? DateTime.now());
  }

  /// All models, `auto` always first.
  final List<ManifestModel> models;
  final DateTime? fetchedAt;
  final bool available;

  static List<ManifestModel> _withAutoFirst(List<ManifestModel> list) {
    ManifestModel? auto;
    final rest = <ManifestModel>[];
    for (final m in list) {
      if (m.isAuto) {
        auto ??= m;
      } else {
        rest.add(m);
      }
    }
    return [auto ?? const ManifestModel(id: kAutoModel), ...rest];
  }

  /// Real models (everything except the synthetic `auto`).
  List<ManifestModel> get concrete => [for (final m in models) if (!m.isAuto) m];

  int _count(CostClass c) => concrete.where((m) => m.costClass == c).length;

  int get freeCount => _count(CostClass.free);
  int get paidCount => _count(CostClass.paid);
  int get unknownCount => _count(CostClass.unknown);

  /// True when `auto` could end up on a paid or price-unknown model. When the list
  /// is unavailable nothing is known, so it counts as true.
  bool get hasPaidOrUnknown => !available || paidCount + unknownCount > 0;

  /// Finds a model by the ID the user picked, or by the `X-Manifest-Model` /
  /// `X-Manifest-Provider` response headers.
  ///
  /// The docs show the served model without its provider prefix (`gpt-5-mini` +
  /// `openai`) while the list uses `openai/gpt-5.4-mini`, so matching is tolerant:
  /// exact ID, then `provider/model`, then a `/model` suffix, each also with a
  /// `-subscription` variant. If several candidates disagree on billing the
  /// answer is [CostClass.unknown] with `ambiguous: true`.
  ModelLookup lookup(String? model, {String? provider}) {
    final m = (model ?? '').trim().toLowerCase();
    if (!available || m.isEmpty) return const ModelLookup(costClass: CostClass.unknown);

    for (final x in concrete) {
      if (x.id.toLowerCase() == m) return _single(x);
    }

    List<ManifestModel> pick(bool Function(String id) test) =>
        [for (final x in concrete) if (test(x.id.toLowerCase())) x];

    final p = (provider ?? '').trim().toLowerCase();
    var cands = p.isEmpty
        ? <ManifestModel>[]
        : pick((id) => id == '$p/$m' || id == '$p/$m-subscription');
    if (cands.isEmpty) {
      cands = pick((id) => id.endsWith('/$m') || id.endsWith('/$m-subscription'));
    }
    if (cands.isEmpty) return const ModelLookup(costClass: CostClass.unknown);
    if (cands.length == 1) return _single(cands.first);

    final classes = {for (final c in cands) c.costClass};
    if (classes.length == 1) return _single(cands.first);
    return const ModelLookup(costClass: CostClass.unknown, ambiguous: true);
  }

  static ModelLookup _single(ManifestModel x) =>
      ModelLookup(costClass: x.costClass, cost: x.cost, matchedId: x.id);
}

/// Token counts from the `usage` object of a response.
class TokenUsage {
  const TokenUsage({this.promptTokens, this.completionTokens});

  final int? promptTokens;
  final int? completionTokens;

  static TokenUsage? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = _asInt(j['prompt_tokens']);
    final c = _asInt(j['completion_tokens']);
    if (p == null && c == null) return null;
    return TokenUsage(promptTokens: p, completionTokens: c);
  }
}

/// USD estimate from token counts and the list prices; null if anything is missing.
/// It is only an estimate: caching, reasoning tokens or provider rounding can change the real bill.
double? estimateCostUsd(TokenUsage? usage, ModelCost? cost) {
  if (usage == null || cost == null) return null;
  final pt = usage.promptTokens;
  final ct = usage.completionTokens;
  final i = cost.input;
  final o = cost.output;
  if (pt == null || ct == null || i == null || o == null) return null;
  return pt * i / 1000000 + ct * o / 1000000;
}

String _trimZeros(String s) {
  if (!s.contains('.')) return s;
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// USD per 1M tokens, e.g. `0.75`, `4.5`, `15`.
String formatPrice(double v) {
  if (v <= 0) return '0';
  if (v >= 100) return v.toStringAsFixed(0);
  return _trimZeros(v.toStringAsFixed(v >= 1 ? 2 : 4));
}

/// USD amount of one reply (an estimate), e.g. `0.0012`.
String formatCost(double v) {
  if (v <= 0) return '0';
  if (v < 0.00001) return '<0.00001';
  return _trimZeros(v.toStringAsFixed(v < 0.01 ? 5 : 4));
}
