import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../data/chat_repository.dart';
import '../data/history.dart';
import '../data/llm_provider.dart';
import '../data/manifest_config.dart';
import '../data/manifest_cost.dart';
import '../data/manifest_headers.dart';
import '../data/models.dart';
import '../data/served_by.dart';
import 'model_catalog_controller.dart';
import 'settings_controller.dart';

/// What the user decided in the "this model may cost money" dialog.
enum PaidDecision { sendOnce, cancel, switchToAuto }

/// Details for the pre-send confirmation of a specific model.
class PaidWarning {
  const PaidWarning({
    required this.model,
    required this.costClass,
    this.cost,
    this.listUnavailable = false,
  });

  final String model;

  /// [CostClass.paid] or [CostClass.unknown] (a free model never asks).
  final CostClass costClass;
  final ModelCost? cost;

  /// The price list could not be loaded, so every price is unknown.
  final bool listUnavailable;
}

typedef PaidConfirmer = Future<PaidDecision> Function(PaidWarning warning);

class ChatController extends ChangeNotifier {
  ChatController(this._repo, this._settings, this._catalog) {
    chats = _repo.all();
  }

  final ChatRepository _repo;
  final SettingsController _settings;
  final ModelCatalogController _catalog;

  /// Set by the chat screen. Without it a paid/unknown model is never sent silently.
  PaidConfirmer? paidConfirmer;

  List<Chat> chats = [];
  Chat? current;
  bool streaming = false;
  ApiException? error;
  StreamSubscription<String>? _sub;
  TokenUsage? _usage;
  bool _gating = false;

  void newChat() {
    stop();
    current = null;
    error = null;
    notifyListeners();
  }

  void open(Chat chat) {
    stop();
    current = chat;
    error = null;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> delete(Chat chat) async {
    if (current?.id == chat.id) {
      stop();
      current = null;
    }
    chats.removeWhere((c) => c.id == chat.id);
    notifyListeners();
    await _repo.delete(chat.id);
  }

  /// Checks configuration and, for a specific model that is paid or price-unknown,
  /// asks for confirmation. Returns true when the request may be sent.
  ///
  /// `auto` cannot be judged before sending (Manifest picks the model per request):
  /// the chat screen shows a persistent notice for it, and every reply gets a badge.
  Future<bool> _preflight() async {
    if (_gating) return false;
    if (!_settings.isConfigured) {
      error = ApiException(
          _settings.agentKey.isEmpty ? ErrorKind.missingKey : ErrorKind.notConfigured);
      notifyListeners();
      return false;
    }
    final model = _settings.model;
    if (!_settings.warnPaid || model == kAutoModel) return true;

    _gating = true;
    try {
      await _catalog.whenIdle();
      final cat = _catalog.catalog;
      final lookup = cat.lookup(model);
      if (lookup.costClass == CostClass.free) return true;
      final confirm = paidConfirmer;
      if (confirm == null) return false;
      final d = await confirm(PaidWarning(
        model: model,
        costClass: lookup.costClass,
        cost: lookup.cost,
        listUnavailable: !cat.available,
      ));
      if (d == PaidDecision.switchToAuto) {
        await _settings.setModel(kAutoModel);
        return true;
      }
      return d == PaidDecision.sendOnce;
    } finally {
      _gating = false;
    }
  }

  /// Returns false when nothing was sent (error, or the user cancelled the paid-model
  /// dialog), so the screen can put the text back in the composer.
  Future<bool> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || streaming) return false;
    error = null;
    if (!await _preflight()) return false;
    if (streaming) return false;

    final chat = current ??= Chat(
      id: newId(),
      title: _titleOf(text),
      messages: [],
    );
    if (!chats.any((c) => c.id == chat.id)) chats.insert(0, chat);
    chat.messages.add(ChatMessage.create('user', text));
    _begin(chat);
    return true;
  }

  /// Edit a user message: everything after it is dropped and the chat continues from the edit.
  Future<void> editAndResend(ChatMessage message, String raw) async {
    final text = raw.trim();
    final chat = current;
    if (chat == null || text.isEmpty || streaming) return;
    final i = chat.messages.indexWhere((m) => m.id == message.id);
    if (i < 0) return;
    error = null;
    if (!await _preflight()) return;
    if (streaming || !identical(current, chat)) return;
    final j = chat.messages.indexWhere((m) => m.id == message.id);
    if (j < 0) return;
    chat.messages.removeRange(j, chat.messages.length);
    if (j == 0) chat.title = _titleOf(text);
    chat.messages.add(ChatMessage.create('user', text));
    _begin(chat);
  }

  /// Regenerate the last reply (also used as "retry" after an error).
  Future<void> regenerate() async {
    final chat = current;
    if (chat == null || streaming || chat.messages.isEmpty) return;
    error = null;
    if (!await _preflight()) return;
    if (streaming || !identical(current, chat) || chat.messages.isEmpty) return;
    if (chat.messages.last.role == 'assistant') chat.messages.removeLast();
    if (chat.messages.isEmpty || chat.messages.last.role != 'user') return;
    _begin(chat);
  }

  String _titleOf(String t) => t.length > 40 ? '${t.substring(0, 40)}…' : t;

  void _begin(Chat chat) {
    chat.messages.add(ChatMessage.create('assistant'));
    streaming = true;
    _usage = null;
    notifyListeners();
    _stream(chat);
  }

  void _stream(Chat chat) {
    final reply = chat.messages.last;
    final history = trimHistory(chat.messages.sublist(0, chat.messages.length - 1));

    final provider = OpenAiCompatibleProvider(
      baseUrl: _settings.baseUrl,
      apiKey: _settings.agentKey,
      // Read as soon as the response headers arrive, before any token.
      onHeaders: (h) {
        reply.served = buildServed(parseManifestHeaders(h), _catalog.catalog);
        notifyListeners();
      },
      onUsage: (u) => _usage = u,
    );
    _sub = provider.streamChat(messages: history, model: _settings.model).listen(
      (token) {
        reply.content += token;
        notifyListeners();
      },
      onError: (Object e) {
        _sub = null;
        error = e is ApiException ? e : ApiException(ErrorKind.unknown, '$e');
        _finish(chat);
      },
      onDone: () {
        _sub = null;
        _finish(chat);
      },
      cancelOnError: true,
    );
  }

  /// Stop button: abort the request and keep whatever was already received.
  void stop() {
    final sub = _sub;
    _sub = null;
    sub?.cancel();
    if (streaming && current != null) _finish(current!);
  }

  void _finish(Chat chat) {
    if (chat.messages.isNotEmpty && chat.messages.last.role == 'assistant') {
      final last = chat.messages.last;
      if (last.content.isEmpty) {
        chat.messages.removeLast();
      } else if (error == null) {
        final notice = parseManifestNotice(last.content);
        if (notice != null) {
          // Manifest wrote an error (spend limit, bad key, ...) as the reply text:
          // show it as an error, not as an answer, and keep it out of the history.
          chat.messages.removeLast();
          error = ApiException.fromNotice(notice);
        } else {
          final u = _usage;
          final s = last.served;
          if (u != null && s != null) last.served = s.withUsage(u);
        }
      }
    }
    _usage = null;
    streaming = false;
    chat.updatedAt = DateTime.now();
    chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
    _repo.save(chat);
  }
}
