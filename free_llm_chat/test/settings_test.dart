import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/data/manifest_config.dart';
import 'package:free_llm_chat/data/secret_store.dart';
import 'package:free_llm_chat/state/settings_controller.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('free_llm_chat_settings_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<Box> openBox() => Hive.openBox('settings_${n++}');

  test('defaults: self-hosted URL, auto, paid warnings on, not configured without a key', () async {
    final s = SettingsController(await openBox(), MemorySecretStore());
    await s.load();
    expect(s.baseUrl, kManifestSelfHostedUrl);
    expect(s.model, kAutoModel);
    expect(s.warnPaid, isTrue);
    expect(s.agentKey, '');
    expect(s.isConfigured, isFalse);
    expect(s.legacyNoticePending, isFalse);
  });

  test('saveConnection normalizes the URL and stores the key in the secret store only', () async {
    final box = await openBox();
    final store = MemorySecretStore();
    final s = SettingsController(box, store);
    await s.load();
    await s.saveConnection(baseUrl: ' http://192.168.1.20:2099/v1/ ', key: 'mnfst_abc');
    expect(s.baseUrl, 'http://192.168.1.20:2099');
    expect(s.agentKey, 'mnfst_abc');
    expect(s.isConfigured, isTrue);
    expect(store.data['manifest_agent_key'], 'mnfst_abc');
    expect(box.values.map((v) => '$v').any((v) => v.contains('mnfst_abc')), isFalse);

    final again = SettingsController(box, store);
    await again.load();
    expect(again.agentKey, 'mnfst_abc');
    expect(again.baseUrl, 'http://192.168.1.20:2099');
  });

  test('saveConnection rejects a bad URL and an empty key clears the key', () async {
    final s = SettingsController(await openBox(), MemorySecretStore());
    await s.load();
    await expectLater(s.saveConnection(baseUrl: '', key: 'mnfst_x'), throwsFormatException);
    await expectLater(
        s.saveConnection(baseUrl: 'http://example.com', key: 'mnfst_x'), throwsFormatException);
    await s.saveConnection(baseUrl: kManifestCloudUrl, key: 'mnfst_x');
    expect(s.isConfigured, isTrue);
    await s.saveConnection(baseUrl: kManifestCloudUrl, key: '');
    expect(s.agentKey, '');
    expect(s.isConfigured, isFalse);
  });

  test('model and the paid-warning switch are stored', () async {
    final box = await openBox();
    final s = SettingsController(box, MemorySecretStore());
    await s.load();
    await s.setModel('openai/gpt-5.4-mini');
    await s.setWarnPaid(false);
    expect(s.model, 'openai/gpt-5.4-mini');
    expect(s.warnPaid, isFalse);
    await s.setModel('  ');
    expect(s.model, kAutoModel);
  });

  test('old provider keys: notice first, deleted only after it is acknowledged', () async {
    final box = await openBox();
    await box.put('provider', 'groq');
    await box.put('model_groq', 'llama');
    await box.put('auto_switch', true);
    await box.put('list_cache', '[]');
    await box.put('usage_day', '2026-01-01');
    await box.put('base_manifest', 'http://192.168.1.5:2099/v1');
    await box.put('lang', 'ar');
    final store = MemorySecretStore({
      'key_groq': 'gsk_a',
      'key_gemini': 'AIza_b',
      'key_manifest': 'mnfst_old',
    });

    final s = SettingsController(box, store);
    await s.load();

    expect(s.legacyNoticePending, isTrue);
    expect(s.legacyKeyCount, 2); // the Manifest key is carried over, not counted
    expect(store.data.containsKey('key_groq'), isTrue); // not deleted yet
    // The old Manifest provider entry carries over.
    expect(s.agentKey, 'mnfst_old');
    expect(s.baseUrl, 'http://192.168.1.5:2099');
    expect(store.data['manifest_agent_key'], 'mnfst_old');
    // Old preferences are gone, unrelated ones stay.
    expect(box.containsKey('provider'), isFalse);
    expect(box.containsKey('model_groq'), isFalse);
    expect(box.containsKey('auto_switch'), isFalse);
    expect(box.containsKey('list_cache'), isFalse);
    expect(box.containsKey('usage_day'), isFalse);
    expect(box.containsKey('base_manifest'), isFalse);
    expect(box.get('lang'), 'ar');

    await s.acknowledgeLegacyNotice();

    expect(s.legacyNoticePending, isFalse);
    expect(store.data.keys.where((k) => k.startsWith('key_')), isEmpty);
    expect(store.data['manifest_agent_key'], 'mnfst_old');

    final next = SettingsController(box, store);
    await next.load();
    expect(next.legacyNoticePending, isFalse);
    expect(next.agentKey, 'mnfst_old');
  });

  test('only the old Manifest entry: carried over silently, no notice', () async {
    final store = MemorySecretStore({'key_manifest': 'mnfst_old'});
    final s = SettingsController(await openBox(), store);
    await s.load();
    expect(s.legacyNoticePending, isFalse);
    expect(s.agentKey, 'mnfst_old');
    expect(store.data.containsKey('key_manifest'), isFalse);
  });

  test('a key saved in the new version wins over the old Manifest entry', () async {
    final store = MemorySecretStore({
      'manifest_agent_key': 'mnfst_new',
      'key_manifest': 'mnfst_old',
      'key_groq': 'gsk_a',
    });
    final s = SettingsController(await openBox(), store);
    await s.load();
    expect(s.agentKey, 'mnfst_new');
    expect(s.legacyNoticePending, isTrue);
    expect(s.legacyKeyCount, 1);
  });
}
