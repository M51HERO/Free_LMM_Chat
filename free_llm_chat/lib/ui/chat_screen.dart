import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/errors.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import 'history_drawer.dart';
import 'markdown_view.dart';
import 'model_picker.dart';
import 'paid_widgets.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  bool get _desktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  late final ChatController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = context.read<ChatController>();
    _ctl.paidConfirmer = _confirmPaid;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowLegacyNotice());
  }

  @override
  void dispose() {
    _ctl.paidConfirmer = null;
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Desktop: Enter sends, Shift+Enter inserts a new line.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_desktop &&
        e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        _text.value.composing.isCollapsed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _send() async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    final sent = await _ctl.send(t);
    if (!mounted) return;
    // Cancelled in the paid-model dialog, or not configured: give the text back.
    if (!sent && _text.text.isEmpty) _text.text = t;
    _focus.requestFocus();
  }

  /// Asked by the controller before a paid or price-unknown specific model is used.
  Future<PaidDecision> _confirmPaid(PaidWarning warning) async {
    if (!mounted) return PaidDecision.cancel;
    final r = await showDialog<PaidDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaidDialog(warning: warning),
    );
    return r ?? PaidDecision.cancel;
  }

  /// One-time notice after the update: keys of the removed providers are deleted.
  Future<void> _maybeShowLegacyNotice() async {
    if (!mounted) return;
    final s = context.read<SettingsController>();
    if (!s.legacyNoticePending) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('legacyTitle')),
        content: Text(ctx.trf('legacyBody', {'n': '${s.legacyKeyCount}'})),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('gotIt'))),
        ],
      ),
    );
    await s.acknowledgeLegacyNotice();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final msgs = chat.current?.messages ?? const <ChatMessage>[];
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(chat.current?.title ?? context.tr('appTitle'), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: context.tr('newChat'),
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: chat.newChat,
          ),
          IconButton(
            tooltip: context.tr('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      drawer: const HistoryDrawer(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                Expanded(
                  child: msgs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 36, color: cs.primary),
                              const SizedBox(height: 16),
                              Text(context.tr('emptyTitle'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(color: cs.onSurface)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final m = msgs[msgs.length - 1 - i];
                            final isLast = i == 0;
                            return m.role == 'user'
                                ? _UserMessage(key: ValueKey(m.id), message: m, canEdit: !chat.streaming)
                                : _AssistantMessage(
                                    message: m,
                                    loading: chat.streaming && isLast,
                                    canRegenerate: isLast && !chat.streaming,
                                  );
                          },
                        ),
                ),
                if (chat.error != null) _ErrorBanner(error: chat.error!),
                const PaidAutoNotice(),
                _composer(chat),
                const _ModelChip(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer(ChatController chat) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 6, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _text,
              builder: (context, v, _) => TextField(
                controller: _text,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                textDirection: directionOf(v.text),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: context.tr('hint'),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          chat.streaming
              ? IconButton.filled(
                  tooltip: context.tr('stop'),
                  icon: const Icon(Icons.stop_rounded),
                  onPressed: chat.stop,
                )
              : IconButton.filled(
                  tooltip: context.tr('send'),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: _send,
                ),
        ],
      ),
    );
  }
}

Future<void> _copy(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  final done = context.trNow('copied');
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 1)));
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: Theme.of(context).colorScheme.outline,
        icon: Icon(icon),
        onPressed: onPressed,
      );
}

/// User message: a soft rounded bubble, with copy + edit underneath.
class _UserMessage extends StatefulWidget {
  const _UserMessage({super.key, required this.message, required this.canEdit});

  final ChatMessage message;
  final bool canEdit;

  @override
  State<_UserMessage> createState() => _UserMessageState();
}

class _UserMessageState extends State<_UserMessage> {
  bool _editing = false;
  late final TextEditingController _ctl = TextEditingController(text: widget.message.content);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final t = _ctl.text;
    if (t.trim().isEmpty) return;
    setState(() => _editing = false);
    context.read<ChatController>().editAndResend(widget.message, t);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxW = (MediaQuery.sizeOf(context).width * 0.85).clamp(0.0, 680.0).toDouble();

    if (_editing) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctl,
              builder: (context, v, _) => TextField(
                controller: _ctl,
                autofocus: true,
                minLines: 1,
                maxLines: 10,
                textDirection: directionOf(v.text),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _ctl.text = widget.message.content;
                    setState(() => _editing = false);
                  },
                  child: Text(context.tr('cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: Text(context.tr('send'))),
              ],
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SelectableText(widget.message.content,
                    textDirection: directionOf(widget.message.content)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIcon(
                    icon: Icons.copy_rounded,
                    tooltip: context.tr('copy'),
                    onPressed: () => _copy(context, widget.message.content),
                  ),
                  if (widget.canEdit)
                    _ActionIcon(
                      icon: Icons.edit_outlined,
                      tooltip: context.tr('edit'),
                      onPressed: () => setState(() => _editing = true),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Assistant message: Markdown on the page (no bubble), with copy + regenerate.
class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    required this.message,
    required this.loading,
    required this.canRegenerate,
  });

  final ChatMessage message;
  final bool loading;
  final bool canRegenerate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.served != null) ServedBadge(served: message.served!),
          if (message.content.isEmpty && loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            MarkdownView(message.content),
          if (message.content.isNotEmpty && !loading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  icon: Icons.copy_rounded,
                  tooltip: context.tr('copy'),
                  onPressed: () => _copy(context, message.content),
                ),
                if (canRegenerate)
                  _ActionIcon(
                    icon: Icons.refresh_rounded,
                    tooltip: context.tr('regenerate'),
                    onPressed: context.read<ChatController>().regenerate,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Small "model" line under the composer; tap to open the model picker.
class _ModelChip extends StatelessWidget {
  const _ModelChip();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showModelPicker(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Manifest · ${s.model}',
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ),
            Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final ApiException error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final retryable = error.kind != ErrorKind.missingKey && error.kind != ErrorKind.notConfigured;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(context.errorText(error), style: TextStyle(color: cs.onErrorContainer))),
          if (retryable)
            TextButton(
              onPressed: context.read<ChatController>().regenerate,
              child: Text(context.tr('retry')),
            ),
          IconButton(
            tooltip: context.tr('dismiss'),
            icon: Icon(Icons.close, color: cs.onErrorContainer),
            onPressed: context.read<ChatController>().clearError,
          ),
        ],
      ),
    );
  }
}
