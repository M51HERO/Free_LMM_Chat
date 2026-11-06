import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/manifest_config.dart';
import '../data/secret_store.dart';

/// App settings. Everything except the agent key lives in the Hive `settings` box;
/// the key lives in the OS secure store and is never logged.
class SettingsController extends ChangeNotifier {
  SettingsController(this._box, this._secrets);

  final Box _box;
  final SecretStore _secrets;

  static const String _secretName = 'manifest_agent_key';

  /// Secure-storage names used by the old multi-provider versions (`key_<providerId>`).
  static const String _legacyPrefix = 'key_';

  /// The old "Manifest (router)" provider entry: its key and URL are still valid, so
  /// they are carried over instead of being deleted.
  static const String _legacyManifestKey = 'key_manifest';

  String _agentKey = '';
  List<String> _legacyKeyNames = [];
  bool _legacyNoticePending = false;

  Future<void> load() async {
    try {
      _agentKey = (await _secrets.read(_secretName)) ?? '';
    } catch (_) {
      _agentKey = ''; // Secure storage unavailable: treat as no key.
    }
    await _detectLegacy();
  }

  // ---- Old multi-provider data -------------------------------------------------

  /// True once, on the first launch after the update, when keys of the removed
  /// providers are still in secure storage.
  bool get legacyNoticePending => _legacyNoticePending;

  /// Number of keys of removed providers (the carried-over Manifest key is not counted).
  int get legacyKeyCount => _legacyKeyNames.where((k) => k != _legacyManifestKey).length;

  Future<void> _detectLegacy() async {
    if (_box.get('legacy_notice_done', defaultValue: false) == true) return;
    final Map<String, String> all;
    try {
      all = await _secrets.readAll();
    } catch (_) {
      return; // Try again on the next launch.
    }
    _legacyKeyNames = [for (final k in all.keys) if (k.startsWith(_legacyPrefix)) k];

    // Carry over what the old Manifest provider entry already had.
    final oldKey = all[_legacyManifestKey];
    if (_agentKey.isEmpty && oldKey != null && oldKey.startsWith(kKeyPrefix)) {
      try {
        await _secrets.write(_secretName, oldKey);
        _agentKey = oldKey;
      } catch (_) {}
    }
    final oldBase = _box.get('base_manifest');
    if (oldBase is String && !_box.containsKey('manifest_base')) {
      final r = checkBaseUrl(oldBase);
      if (r.ok) await _box.put('manifest_base', r.url);
    }

    await _purgeLegacyPrefs();

    if (legacyKeyCount == 0) {
      // Nothing from other providers to tell the user about.
      await _deleteLegacyKeys();
    } else {
      _legacyNoticePending = true;
    }
  }

  Future<void> _purgeLegacyPrefs() async {
    const exact = {
      'provider',
      'custom_base',
      'auto_switch',
      'keyless_fallback',
      'list_cache',
      'list_updated',
    };
    final old = _box.keys.where((k) {
      final s = '$k';
      return exact.contains(s) ||
          s.startsWith('model_') ||
          s.startsWith('base_') ||
          s.startsWith('usage_');
    }).toList();
    for (final k in old) {
      await _box.delete(k);
    }
  }

  /// Deletes every old key from secure storage. Marks the migration done only if
  /// all deletions worked, so a failure is retried on the next launch.
  Future<void> _deleteLegacyKeys() async {
    var ok = true;
    for (final k in _legacyKeyNames) {
      try {
        await _secrets.delete(k);
      } catch (_) {
        ok = false;
      }
    }
    if (ok) {
      _legacyKeyNames = [];
      await _box.put('legacy_notice_done', true);
    }
  }

  /// Call after the user has seen the one-time notice: deletes the old keys.
  Future<void> acknowledgeLegacyNotice() async {
    await _deleteLegacyKeys();
    _legacyNoticePending = false;
    notifyListeners();
  }

  // ---- Language / theme --------------------------------------------------------

  String get lang => _box.get('lang',
      defaultValue: PlatformDispatcher.instance.locale.languageCode == 'ar' ? 'ar' : 'en') as String;

  ThemeMode get themeMode => switch (_box.get('theme', defaultValue: 'system')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setLang(String v) async {
    await _box.put('lang', v);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    await _box.put('theme', m.name);
    notifyListeners();
  }

  // ---- Manifest connection -----------------------------------------------------

  /// Base URL without `/v1` (see [checkBaseUrl]).
  String get baseUrl => (_box.get('manifest_base', defaultValue: kManifestSelfHostedUrl) as String);

  /// The `mnfst_...` agent key ('' if none). Never log it.
  String get agentKey => _agentKey;

  bool get isConfigured => _agentKey.isNotEmpty && checkBaseUrl(baseUrl).ok;

  /// Selected model: `auto` (Manifest routes) or a concrete model ID from the list.
  String get model {
    final m = (_box.get('manifest_model', defaultValue: kAutoModel) as String).trim();
    return m.isEmpty ? kAutoModel : m;
  }

  /// Warn before a paid (or price-unknown) model is used. On by default.
  bool get warnPaid => _box.get('warn_paid', defaultValue: true) as bool;

  /// Validates and stores the connection. Throws [FormatException] (message = the
  /// [BaseUrlProblem] name) when the URL is not acceptable; an empty [key] clears the key.
  Future<void> saveConnection({required String baseUrl, required String key}) async {
    final r = checkBaseUrl(baseUrl);
    if (!r.ok) throw FormatException(r.problem!.name);
    await _box.put('manifest_base', r.url);
    if (key.isEmpty) {
      await _secrets.delete(_secretName);
      _agentKey = '';
    } else {
      await _secrets.write(_secretName, key);
      _agentKey = key;
    }
    notifyListeners();
  }

  Future<void> setModel(String id) async {
    await _box.put('manifest_model', id.trim().isEmpty ? kAutoModel : id.trim());
    notifyListeners();
  }

  Future<void> setWarnPaid(bool v) async {
    await _box.put('warn_paid', v);
    notifyListeners();
  }
}
