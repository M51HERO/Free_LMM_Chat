import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/errors.dart';
import '../core/strings.dart';
import '../data/manifest_client.dart';
import '../data/manifest_config.dart';
import '../state/model_catalog_controller.dart';
import '../state/settings_controller.dart';
import 'model_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _base = TextEditingController();
  final _key = TextEditingController();
  bool _showKey = false;
  String? _baseError;
  String? _keyError;
  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsController>();
    _base.text = s.baseUrl;
    _key.text = s.agentKey;
  }

  @override
  void dispose() {
    _base.dispose();
    _key.dispose();
    super.dispose();
  }

  bool get _android => !kIsWeb && Platform.isAndroid;

  /// Validates both fields and shows the problems under them.
  bool _validate() {
    final r = checkBaseUrl(_base.text);
    final key = _key.text.trim();
    String? baseError;
    String? keyError;
    if (!r.ok) {
      baseError = context.trNow(switch (r.problem!) {
        BaseUrlProblem.empty => 'urlEmpty',
        BaseUrlProblem.invalid => 'urlInvalid',
        BaseUrlProblem.cleartextNotLocal => 'urlCleartext',
      });
    }
    if (key.isNotEmpty && !key.startsWith(kKeyPrefix)) {
      keyError = context.trNow('keyBadPrefix');
    }
    setState(() {
      _baseError = baseError;
      _keyError = keyError;
    });
    return baseError == null && keyError == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final s = context.read<SettingsController>();
    final catalog = context.read<ModelCatalogController>();
    final messenger = ScaffoldMessenger.of(context);
    final savedText = context.trNow('saved');
    try {
      await s.saveConnection(baseUrl: _base.text, key: _key.text.trim());
      _base.text = s.baseUrl; // show the normalized URL
      catalog.refresh(); // settings changed: reload the price list
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(savedText), duration: const Duration(seconds: 1)));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Tests what is typed in the fields (not yet saved): `GET /v1/models?cost=true`.
  Future<void> _test() async {
    if (!_validate()) return;
    final lang = context.read<SettingsController>().lang;
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testOk = false;
        _testMsg = trLang(lang, 'err_missingKey');
      });
      return;
    }
    final base = checkBaseUrl(_base.text).url!;
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    String msg;
    bool ok;
    try {
      final c = await ManifestClient().fetchModels(baseUrl: base, key: key);
      ok = true;
      msg = trLangF(lang, 'testOk', {
        'total': '${c.concrete.length}',
        'free': '${c.freeCount}',
        'paid': '${c.paidCount}',
        'unknown': '${c.unknownCount}',
      });
      if (c.concrete.isEmpty) msg = '$msg\n${trLang(lang, 'testNoModels')}';
    } on ApiException catch (e) {
      ok = false;
      msg = errorTextFor(lang, e);
    } catch (e) {
      ok = false;
      msg = errorTextFor(lang, ApiException(ErrorKind.unknown, '$e'));
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testMsg = msg;
    });
  }

  Future<void> _toggleWarn(bool value) async {
    final s = context.read<SettingsController>();
    if (value) {
      await s.setWarnPaid(true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('warnOffTitle')),
        content: Text(ctx.tr('warnOffBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('keepOn'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('turnOff'))),
        ],
      ),
    );
    if (confirmed == true) await s.setWarnPaid(false);
  }

  void _preset(String url) {
    setState(() {
      _base.text = url;
      _baseError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;

    final typed = checkBaseUrl(_base.text).url;
    final localhostOnAndroid =
        _android && typed != null && isLoopbackHost(Uri.parse(typed).host);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.tr('manifestSection'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(context.tr('manifestIntro'), style: small?.copyWith(color: cs.outline)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _preset(kManifestSelfHostedUrl),
                    child: Text(context.tr('presetSelfHosted')),
                  ),
                  OutlinedButton(
                    onPressed: () => _preset(kManifestCloudUrl),
                    child: Text(context.tr('presetCloud')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _base,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _baseError = null),
                decoration: InputDecoration(
                  labelText: context.tr('baseUrl'),
                  helperText: context.tr('baseUrlHint'),
                  helperMaxLines: 4,
                  errorText: _baseError,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (localhostOnAndroid) ...[
                const SizedBox(height: 8),
                Text(context.tr('androidLocalhost'), style: small?.copyWith(color: cs.error)),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _key,
                obscureText: !_showKey,
                enableSuggestions: false,
                autocorrect: false,
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() => _keyError = null),
                decoration: InputDecoration(
                  labelText: context.tr('agentKey'),
                  hintText: context.tr('keyHint'),
                  errorText: _keyError,
                  errorMaxLines: 2,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(onPressed: _save, child: Text(context.tr('save'))),
                  OutlinedButton.icon(
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: Text(context.tr(_testing ? 'testing' : 'testConnection')),
                    onPressed: _testing ? null : _test,
                  ),
                ],
              ),
              if (_testMsg != null) ...[
                const SizedBox(height: 8),
                Text(_testMsg!, style: TextStyle(color: _testOk ? cs.primary : cs.error)),
              ],
              const Divider(height: 40),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('modelLabel')),
                subtitle: Text(s.model, textDirection: TextDirection.ltr),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModelPicker(context),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('warnPaid')),
                subtitle: Text(context.tr('warnPaidHint')),
                value: s.warnPaid,
                onChanged: _toggleWarn,
              ),
              const Divider(height: 40),
              Text(context.tr('language'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                ],
                selected: {s.lang},
                onSelectionChanged: (v) => s.setLang(v.first),
              ),
              const SizedBox(height: 24),
              Text(context.tr('theme'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(context.tr('system'))),
                  ButtonSegment(value: ThemeMode.light, label: Text(context.tr('light'))),
                  ButtonSegment(value: ThemeMode.dark, label: Text(context.tr('dark'))),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.setTheme(v.first),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
