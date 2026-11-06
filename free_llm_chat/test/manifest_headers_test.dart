import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/data/manifest_cost.dart';
import 'package:free_llm_chat/data/manifest_headers.dart';
import 'package:free_llm_chat/data/served_by.dart';

ModelCatalog catalog() => ModelCatalog.fromJson({
      'data': [
        {'id': 'auto'},
        {
          'id': 'anthropic/claude-sonnet-4-6',
          'cost': {'input': 3, 'output': 15},
        },
        {
          'id': 'openrouter/example-free-model',
          'cost': {'input': 0, 'output': 0},
        },
        {'id': 'mystery/model'},
        {
          'id': 'openai/gpt-5.4-mini',
          'cost': {'input': 0.75, 'output': 4.5},
        },
        {
          'id': 'openai/gpt-5.4-mini-subscription',
          'cost': {'input': 0, 'output': 0},
        },
      ],
    });

void main() {
  group('parseManifestHeaders', () {
    test('reads the routed-response headers (names are case-insensitive)', () {
      final i = parseManifestHeaders({
        'X-Manifest-Model': 'claude-sonnet-4-6',
        'x-manifest-provider': 'anthropic',
        'X-MANIFEST-TIER': 'direct',
        'X-Manifest-Reason': 'direct',
      });
      expect(i.model, 'claude-sonnet-4-6');
      expect(i.provider, 'anthropic');
      expect(i.tier, 'direct');
      expect(i.reason, 'direct');
      expect(i.hasServedModel, isTrue);
      expect(i.fellBack, isFalse);
      expect(i.fallbackExhausted, isFalse);
      expect(i.answeredByManifest, isFalse);
    });

    test('reads the fallback headers', () {
      final i = parseManifestHeaders({
        'x-manifest-model': 'gpt-5-mini',
        'x-manifest-provider': 'openai',
        'x-manifest-fallback-from': 'gpt-5',
        'x-manifest-fallback-index': '0',
      });
      expect(i.fellBack, isTrue);
      expect(i.fallbackFrom, 'gpt-5');
      expect(i.fallbackIndex, 0);
    });

    test('fallback exhausted flag', () {
      expect(parseManifestHeaders({'X-Manifest-Fallback-Exhausted': 'true'}).fallbackExhausted,
          isTrue);
      expect(parseManifestHeaders({'x-manifest-fallback-exhausted': 'TRUE'}).fallbackExhausted,
          isTrue);
      expect(parseManifestHeaders({'x-manifest-fallback-exhausted': 'false'}).fallbackExhausted,
          isFalse);
    });

    test('missing, empty or blank headers mean "no served model"', () {
      expect(parseManifestHeaders(const {}).hasServedModel, isFalse);
      expect(parseManifestHeaders({'x-manifest-model': '   '}).hasServedModel, isFalse);
      expect(parseManifestHeaders({'content-type': 'text/event-stream'}).model, isNull);
      expect(parseManifestHeaders({'x-manifest-fallback-index': 'abc'}).fallbackIndex, isNull);
    });

    test('Manifest answering by itself reports "manifest" as model and provider', () {
      final i = parseManifestHeaders({
        'x-manifest-model': 'manifest',
        'x-manifest-provider': 'manifest',
        'x-manifest-tier': 'simple',
      });
      expect(i.answeredByManifest, isTrue);
    });
  });

  group('buildServed', () {
    test('paid model: red, with prices', () {
      final s = buildServed(
        parseManifestHeaders({
          'x-manifest-model': 'claude-sonnet-4-6',
          'x-manifest-provider': 'anthropic',
        }),
        catalog(),
      );
      expect(s.costClass, CostClass.paid);
      expect(s.inputPrice, 3);
      expect(s.outputPrice, 15);
      expect(s.model, 'claude-sonnet-4-6');
      expect(s.provider, 'anthropic');
      expect(s.headersMissing, isFalse);
      expect(s.listUnavailable, isFalse);
    });

    test('model with zero prices: no per-token charge (green)', () {
      final s = buildServed(
        parseManifestHeaders({
          'x-manifest-model': 'openrouter/example-free-model',
          'x-manifest-provider': 'openrouter',
        }),
        catalog(),
      );
      expect(s.costClass, CostClass.free);
      expect(s.estimatedCostUsd, isNull);
    });

    test('model missing from the list, or listed without prices: unknown (amber)', () {
      final gone = buildServed(
        parseManifestHeaders({'x-manifest-model': 'brand-new-model', 'x-manifest-provider': 'x'}),
        catalog(),
      );
      expect(gone.costClass, CostClass.unknown);
      final noPrice = buildServed(
        parseManifestHeaders({'x-manifest-model': 'mystery/model'}),
        catalog(),
      );
      expect(noPrice.costClass, CostClass.unknown);
    });

    test('normal and subscription routes of the same model are ambiguous: unknown', () {
      final s = buildServed(
        parseManifestHeaders({'x-manifest-model': 'gpt-5.4-mini', 'x-manifest-provider': 'openai'}),
        catalog(),
      );
      expect(s.costClass, CostClass.unknown);
      expect(s.ambiguous, isTrue);
    });

    test('fallback: remembers the model it fell back from', () {
      final s = buildServed(
        parseManifestHeaders({
          'x-manifest-model': 'openrouter/example-free-model',
          'x-manifest-provider': 'openrouter',
          'x-manifest-fallback-from': 'gpt-5',
          'x-manifest-fallback-index': '0',
        }),
        catalog(),
      );
      expect(s.fallbackFrom, 'gpt-5');
      expect(s.costClass, CostClass.free);
    });

    test('missing headers: "served model unknown", amber', () {
      final s = buildServed(parseManifestHeaders(const {}), catalog());
      expect(s.headersMissing, isTrue);
      expect(s.costClass, CostClass.unknown);
      expect(s.model, isNull);
    });

    test('Manifest answered by itself: no model was called', () {
      final s = buildServed(
        parseManifestHeaders({'x-manifest-model': 'manifest', 'x-manifest-provider': 'manifest'}),
        catalog(),
      );
      expect(s.answeredByManifest, isTrue);
      expect(s.headersMissing, isFalse);
    });

    test('price list unavailable: everything is unknown and says so', () {
      final s = buildServed(
        parseManifestHeaders({
          'x-manifest-model': 'claude-sonnet-4-6',
          'x-manifest-provider': 'anthropic',
        }),
        ModelCatalog.unavailable(),
      );
      expect(s.costClass, CostClass.unknown);
      expect(s.listUnavailable, isTrue);

      final missing = buildServed(parseManifestHeaders(const {}), ModelCatalog.unavailable());
      expect(missing.headersMissing, isTrue);
      expect(missing.listUnavailable, isTrue);
    });
  });

  group('ServedBy', () {
    final paid = buildServed(
      parseManifestHeaders({
        'x-manifest-model': 'claude-sonnet-4-6',
        'x-manifest-provider': 'anthropic',
        'x-manifest-fallback-from': 'gpt-5',
      }),
      catalog(),
    );

    test('estimated cost only for paid models with usage', () {
      final withUsage = paid.withUsage(const TokenUsage(promptTokens: 1000, completionTokens: 500));
      expect(withUsage.estimatedCostUsd, closeTo(0.0105, 1e-12));
      expect(withUsage.promptTokens, 1000);
      expect(withUsage.fallbackFrom, 'gpt-5');

      final free = buildServed(
        parseManifestHeaders({
          'x-manifest-model': 'openrouter/example-free-model',
          'x-manifest-provider': 'openrouter',
        }),
        catalog(),
      ).withUsage(const TokenUsage(promptTokens: 1000, completionTokens: 500));
      expect(free.estimatedCostUsd, isNull);
      expect(free.completionTokens, 500);
    });

    test('survives a JSON round trip', () {
      final original = paid.withUsage(const TokenUsage(promptTokens: 10, completionTokens: 20));
      final back = ServedBy.fromJson(original.toJson());
      expect(back.costClass, CostClass.paid);
      expect(back.model, 'claude-sonnet-4-6');
      expect(back.provider, 'anthropic');
      expect(back.fallbackFrom, 'gpt-5');
      expect(back.inputPrice, 3);
      expect(back.outputPrice, 15);
      expect(back.estimatedCostUsd, original.estimatedCostUsd);
    });

    test('fromJson tolerates unknown or missing fields', () {
      final s = ServedBy.fromJson({'costClass': 'something-new'});
      expect(s.costClass, CostClass.unknown);
      expect(s.model, isNull);
      expect(ServedBy.fromJson({'costClass': 'free'}).costClass, CostClass.free);
    });
  });
}
