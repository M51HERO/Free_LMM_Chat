import 'served_by.dart';

int _counter = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

class ChatMessage {
  ChatMessage(
      {required this.id, required this.role, this.content = '', this.served, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  factory ChatMessage.create(String role, [String content = '']) =>
      ChatMessage(id: newId(), role: role, content: content);

  /// Tolerant of old saved chats: the removed `via` key (app-side auto-switch) is
  /// ignored, and a missing `served` simply means "no badge".
  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final s = j['served'];
    return ChatMessage(
      id: (j['id'] as String?) ?? newId(),
      role: (j['role'] as String?) ?? 'assistant',
      content: (j['content'] as String?) ?? '',
      served: s is Map ? ServedBy.fromJson(Map<String, dynamic>.from(s)) : null,
      createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? ''),
    );
  }

  final String id;
  final String role; // 'user' | 'assistant'
  String content;

  /// For assistant replies: which model served it and how it is billed
  /// (read from the `X-Manifest-*` headers when the response starts).
  ServedBy? served;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        if (served != null) 'served': served!.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };
}

class Chat {
  Chat({required this.id, required this.title, required this.messages, DateTime? updatedAt})
      : updatedAt = updatedAt ?? DateTime.now();

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
        messages: ((j['messages'] as List?) ?? const [])
            .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );

  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}
