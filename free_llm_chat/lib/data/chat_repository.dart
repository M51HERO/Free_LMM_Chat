import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'models.dart';

/// Local chat history stored in Hive (one JSON document per chat).
class ChatRepository {
  ChatRepository(this._box);

  final Box<String> _box;

  List<Chat> all() {
    final out = <Chat>[];
    for (final raw in _box.values) {
      try {
        out.add(Chat.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map)));
      } catch (_) {
        // Skip corrupted entries.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> save(Chat chat) => _box.put(chat.id, jsonEncode(chat.toJson()));

  Future<void> delete(String id) => _box.delete(id);
}
