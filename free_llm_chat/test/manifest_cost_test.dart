import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/data/manifest_cost.dart';

Map<String, dynamic> sample() => {
      'object': 'list',
      'data': [
        {'id': 'auto', 'object': 'model', 'created': 0, 'owned_by': 'manifest'},
        {
          'id': 'openai/gpt-5.4-mini',
          'owned_by': 'openai',
          'cost': {'input': 0.75, 'output': 4.5},
        },
        {
          'id': 'openrouter/example-free-model',
          'owned_by': 'openrouter',
          'cost': {'input': 0, 'output': 0},
        },
        {
          'id': 'openai/gpt-5.4-mini-subscription',
          'owned_by': 'openai',
          'cost': {'input': 0, 'output': 0},
        },
        {'id': 'mystery/model', 'owned_by': 'mystery'},
        {
          'id': 'half/model',
          'cost': {'output': 0},
        },
        {
          'id': 'anthropic/claude-sonnet-4-6',
          'cost': {'input': 3, 'output': 15},
        },
      ],
    };

void main() {
  group('classifyCost', () {
    test('paid when input or output is above zero', () {
      expect(classifyCost(const ModelCost(input: 0.75, output: 4.5)), CostClass.paid);
      expect(classifyCost(const ModelCost(input: 0, output: 0.01)), CostClass.paid);
      expect(classifyCost(const ModelCost(input: 1)), CostClass.paid); // other price unknown
      expect(classifyCost(const ModelCost(output: 2)), CostClass.paid);
    });

    test('free (no per-token charge) only when both prices are zero', () {
      expect(classifyCost(const ModelCost(input: 0, output: 0)), CostClass.free);
    });

    test('unknown when there is no usable price data', () {
      expect(classifyCost(null), CostClass.unknown);
      expect(classifyCost(const ModelCost()), CostClass.unknown);
      expect(classifyCost(const ModelCost(output: 0)), CostClass.unknown);
      expect(classifyCost(const ModelCost(input: 0)), CostClass.unknown);
      expect(classifyCost(const ModelCost(input: -1, output: -1)), CostClass.unknown);
      expect(classifyCost(const ModelCost(input: double.nan, output: double.nan)),
          CostClass.unknown);
    });
  });

  group('ModelCatalog.fromJson', () {
    test('parses models, prices and puts auto first', () {
      final c = ModelCatalog.fromJson(sample());
      expect(c.available, isTrue);
      expect(c.models.first.id, 'auto');
      expect(c.models.first.cost, isNull);
      expect(c.concrete.length, 6);
      final gpt = c.concrete.firstWhere((m) => m.id == 'openai/gpt-5.4-mini');
      expect(gpt.cost!.input, 0.75);
      expect(gpt.cost!.output, 4.5);
      expect(gpt.costClass, CostClass.paid);
    });

    test('counts free, paid and unknown (auto is not counted)', () {
      final c = ModelCatalog.fromJson(sample());
      expect(c.freeCount, 2);
      expect(c.paidCount, 2);
      expect(c.unknownCount, 2);
      expect(c.hasPaidOrUnknown, isTrue);
    });

    test('a partial price (one field omitted) keeps the other one', () {
      final c = ModelCatalog.fromJson(sample());
      final half = c.concrete.firstWhere((m) => m.id == 'half/model');
      expect(half.cost!.input, isNull);
      expect(half.cost!.output, 0);
      expect(half.costClass, CostClass.unknown);
    });

    test('inserts a synthetic auto when the list has none, and moves it to the front', () {
      final noAuto = ModelCatalog.fromJson({
        'data': [
          {'id': 'a/b', 'cost': {'input': 0, 'output': 0}},
        ],
      });
      expect(noAuto.models.first.id, 'auto');
      expect(noAuto.models.length, 2);

      final autoLast = ModelCatalog.fromJson({
        'data': [
          {'id': 'a/b'},
          {'id': 'auto'},
        ],
      });
      expect(autoLast.models.map((m) => m.id), ['auto', 'a/b']);
    });

    test('free-only list has nothing to warn about', () {
      final c = ModelCatalog.fromJson({
        'data': [
          {'id': 'a/b', 'cost': {'input': 0, 'output': 0}},
        ],
      });
      expect(c.hasPaidOrUnknown, isFalse);
    });

    test('skips unusable entries and rejects other shapes', () {
      final c = ModelCatalog.fromJson({
        'data': [
          'nope',
          {'object': 'model'},
          {'id': ''},
          {'id': 'ok/model'},
        ],
      });
      expect(c.concrete.map((m) => m.id), ['ok/model']);
      expect(() => ModelCatalog.fromJson(<String, dynamic>{}), throwsFormatException);
      expect(() => ModelCatalog.fromJson([]), throwsFormatException);
      expect(() => ModelCatalog.fromJson({'data': 'x'}), throwsFormatException);
    });
  });

  group('unavailable catalog', () {
    test('everything is unknown and counts as possibly paid', () {
      final c = ModelCatalog.unavailable();
      expect(c.available, isFalse);
      expect(c.models.single.id, 'auto');
      expect(c.hasPaidOrUnknown, isTrue);
      expect(c.lookup('openai/gpt-5.4-mini').costClass, CostClass.unknown);
    });
  });

  group('lookup', () {
    final c = ModelCatalog.fromJson(sample());

    test('exact ID', () {
      final r = c.lookup('openai/gpt-5.4-mini');
      expect(r.costClass, CostClass.paid);
      expect(r.matchedId, 'openai/gpt-5.4-mini');
      expect(r.cost!.input, 0.75);
      expect(r.ambiguous, isFalse);
      expect(c.lookup('openrouter/example-free-model').costClass, CostClass.free);
    });

    test('header style: model without provider prefix plus provider', () {
      final r = c.lookup('claude-sonnet-4-6', provider: 'anthropic');
      expect(r.costClass, CostClass.paid);
      expect(r.matchedId, 'anthropic/claude-sonnet-4-6');
      expect(r.cost!.output, 15);
    });

    test('matching ignores case', () {
      expect(c.lookup('CLAUDE-SONNET-4-6', provider: 'Anthropic').costClass, CostClass.paid);
    });

    test('suffix match without a provider', () {
      expect(c.lookup('example-free-model').costClass, CostClass.free);
    });

    test('a normal route and a -subscription route of the same model are ambiguous', () {
      final r = c.lookup('gpt-5.4-mini', provider: 'openai');
      expect(r.costClass, CostClass.unknown);
      expect(r.ambiguous, isTrue);
      expect(r.found, isFalse);
    });

    test('a lone -subscription route matches its base name', () {
      final only = ModelCatalog.fromJson({
        'data': [
          {'id': 'openai/gpt-5-subscription', 'cost': {'input': 0, 'output': 0}},
        ],
      });
      expect(only.lookup('gpt-5', provider: 'openai').costClass, CostClass.free);
    });

    test('a model missing from the list is unknown', () {
      final r = c.lookup('does-not-exist', provider: 'openai');
      expect(r.costClass, CostClass.unknown);
      expect(r.found, isFalse);
      expect(c.lookup(null).costClass, CostClass.unknown);
      expect(c.lookup('  ').costClass, CostClass.unknown);
    });

    test('a listed model without price data is unknown but found', () {
      final r = c.lookup('mystery/model');
      expect(r.costClass, CostClass.unknown);
      expect(r.found, isTrue);
    });
  });

  group('TokenUsage and estimate', () {
    test('parses usage', () {
      final u = TokenUsage.fromJson({'prompt_tokens': 1000, 'completion_tokens': 500});
      expect(u!.promptTokens, 1000);
      expect(u.completionTokens, 500);
      expect(TokenUsage.fromJson('x'), isNull);
      expect(TokenUsage.fromJson(<String, dynamic>{}), isNull);
    });

    test('estimates USD from per-1M prices', () {
      const usage = TokenUsage(promptTokens: 1000, completionTokens: 500);
      final est = estimateCostUsd(usage, const ModelCost(input: 3, output: 15));
      expect(est, closeTo(0.0105, 1e-12));
    });

    test('no estimate when anything is missing', () {
      const usage = TokenUsage(promptTokens: 1000, completionTokens: 500);
      expect(estimateCostUsd(null, const ModelCost(input: 3, output: 15)), isNull);
      expect(estimateCostUsd(usage, null), isNull);
      expect(estimateCostUsd(usage, const ModelCost(input: 3)), isNull);
      expect(estimateCostUsd(const TokenUsage(promptTokens: 5), const ModelCost(input: 3, output: 15)),
          isNull);
    });
  });

  group('formatting', () {
    test('formatPrice', () {
      expect(formatPrice(0.75), '0.75');
      expect(formatPrice(4.5), '4.5');
      expect(formatPrice(3), '3');
      expect(formatPrice(15), '15');
      expect(formatPrice(0), '0');
      expect(formatPrice(120.4), '120');
    });

    test('formatCost', () {
      expect(formatCost(0.0105), '0.0105');
      expect(formatCost(0.0012), '0.0012');
      expect(formatCost(0), '0');
      expect(formatCost(0.000001), '<0.00001');
    });
  });
}
