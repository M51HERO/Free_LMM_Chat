import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../data/manifest_client.dart';
import '../data/manifest_cost.dart';
import 'settings_controller.dart';

/// Holds the model list with prices (memory only, never written to disk).
///
/// Refreshed on app start, after the connection settings change, from the refresh
/// button, and every [interval] (10 minutes). When a fetch fails the catalog becomes
/// [ModelCatalog.unavailable]: every model is then "price unknown".
class ModelCatalogController extends ChangeNotifier {
  ModelCatalogController(
    this._settings, {
    ManifestClient? client,
    this.interval = const Duration(minutes: 10),
  }) : _client = client ?? ManifestClient();

  final SettingsController _settings;
  final ManifestClient _client;
  final Duration interval;

  ModelCatalog _catalog = ModelCatalog.unavailable();
  ApiException? lastError;
  bool loading = false;

  /// True once the first fetch (or the "not configured" check) has finished.
  bool hasAttempted = false;

  Timer? _timer;
  Future<void>? _last;
  int _gen = 0;

  ModelCatalog get catalog => _catalog;

  /// Fetches now and then every [interval].
  void start() {
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  /// Newest request wins: an older response that arrives late is dropped.
  Future<void> refresh() {
    final f = _doRefresh(++_gen);
    _last = f;
    return f;
  }

  /// Lets a fetch that is already running finish (up to 8 s), so a message sent right
  /// after start-up is judged on real prices instead of "unknown".
  Future<void> whenIdle() async {
    final f = _last;
    if (f != null && loading) {
      await f.timeout(const Duration(seconds: 8), onTimeout: () {});
    }
  }

  Future<void> _doRefresh(int gen) async {
    if (!_settings.isConfigured) {
      _catalog = ModelCatalog.unavailable();
      lastError = null;
      loading = false;
      hasAttempted = true;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    ModelCatalog result;
    ApiException? err;
    try {
      result = await _client.fetchModels(baseUrl: _settings.baseUrl, key: _settings.agentKey);
    } on ApiException catch (e) {
      result = ModelCatalog.unavailable();
      err = e;
    } catch (e) {
      result = ModelCatalog.unavailable();
      err = ApiException(ErrorKind.unknown, '$e');
    }
    if (gen != _gen) return; // A newer refresh is running and will publish its own result.
    _catalog = result;
    lastError = err;
    loading = false;
    hasAttempted = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
