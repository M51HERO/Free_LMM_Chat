import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/core/errors.dart';
import 'package:free_llm_chat/core/strings.dart';

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  final en = stringTable('en');
  final ar = stringTable('ar');

  test('English and Arabic have exactly the same keys', () {
    expect(ar.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'only in Arabic');
    expect(en.keys.toSet().difference(ar.keys.toSet()), isEmpty, reason: 'only in English');
  });

  test('no empty strings, and the same {placeholders} in both languages', () {
    for (final k in en.keys) {
      expect(en[k]!.trim(), isNotEmpty, reason: 'en $k');
      expect(ar[k]!.trim(), isNotEmpty, reason: 'ar $k');
      expect(_placeholders(ar[k]!), _placeholders(en[k]!), reason: 'placeholders of $k');
    }
  });

  test('every error kind has a message in both languages', () {
    for (final kind in ErrorKind.values) {
      expect(en.containsKey('err_${kind.name}'), isTrue, reason: 'en err_${kind.name}');
      expect(ar.containsKey('err_${kind.name}'), isTrue, reason: 'ar err_${kind.name}');
    }
  });

  test('keys used with tr()/trf()/trNow() in the UI exist', () {
    final used = <String>{};
    final call = RegExp(r"\b(?:tr|trNow|trf|trLang|trLangF)\(\s*(?:lang,\s*)?'([A-Za-z0-9_]+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('strings.dart')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    expect(used, isNotEmpty);
    expect(used.where((k) => !en.containsKey(k)), isEmpty);
  });

  test('placeholders are filled', () {
    expect(trLangF('en', 'testOk', {'total': '3', 'free': '1', 'paid': '1', 'unknown': '1'}),
        isNot(contains('{')));
    expect(trLangF('en', 'priceFmt', {'in': '0.75', 'out': '4.5'}), r'$0.75 in / $4.5 out per 1M tokens');
    expect(trLangF('ar', 'autoNoticeCounts', {'paid': '2', 'unknown': '1', 'total': '9'}),
        isNot(contains('{')));
  });

  test('the error text adds the server detail for the kinds where it helps', () {
    final withDetail = errorTextFor('en', ApiException(ErrorKind.fallbackExhausted, 'upstream said no'));
    expect(withDetail, contains('upstream said no'));
    final without = errorTextFor('en', ApiException(ErrorKind.invalidKey, 'secret detail'));
    expect(without, isNot(contains('secret detail')));
  });
}
