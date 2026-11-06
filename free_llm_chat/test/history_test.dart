import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/data/history.dart';
import 'package:free_llm_chat/data/manifest_cost.dart';
import 'package:free_llm_chat/data/models.dart';
import 'package:free_llm_chat/data/served_by.dart';

ChatMessage _m(String role, int n) => ChatMessage.create(role, 'x' * n);

void main() {
  test('keeps everything when under budget', () {
    final msgs = [_m('user', 10), _m('assistant', 10), _m('user', 10)];
    expect(trimHistory(msgs, maxChars: 100).length, 3);
  });

  test('drops the oldest messages first and starts with a user message', () {
    final msgs = [_m('user', 50), _m('assistant', 50), _m('user', 50), _m('assistant', 50), _m('user', 50)];
    final out = trimHistory(msgs, maxChars: 120);
    expect(out.first.role, 'user');
    expect(out.last, same(msgs.last));
    expect(out.length, lessThan(msgs.length));
  });

  test('always keeps the newest message even if it exceeds the budget', () {
    final msgs = [_m('user', 10), _m('assistant', 10), _m('user', 500)];
    final out = trimHistory(msgs, maxChars: 100);
    expect(out.length, 1);
    expect(out.single, same(msgs.last));
  });

  test('empty input gives empty output', () {
    expect(trimHistory(const []), isEmpty);
  });

  group('saved chats', () {
    test('old chats (with the removed "via" key) still load, without a badge', () {
      final chat = Chat.fromJson({
        'id': '1',
        'title': 'old',
        'updatedAt': '2026-01-01T00:00:00.000',
        'messages': [
          {'id': 'a', 'role': 'user', 'content': 'hi', 'createdAt': '2026-01-01T00:00:00.000'},
          {
            'id': 'b',
            'role': 'assistant',
            'content': 'hello',
            'via': 'Groq · llama-3.3-70b',
            'createdAt': '2026-01-01T00:00:01.000',
          },
        ],
      });
      expect(chat.messages.length, 2);
      expect(chat.messages.last.content, 'hello');
      expect(chat.messages.last.served, isNull);
    });

    test('missing optional fields do not break loading', () {
      final chat = Chat.fromJson({'id': '1'});
      expect(chat.title, '');
      expect(chat.messages, isEmpty);
    });

    test('served model, provider and billing class survive save and load', () {
      final reply = ChatMessage.create('assistant', 'answer')
        ..served = const ServedBy(
          costClass: CostClass.paid,
          model: 'claude-sonnet-4-6',
          provider: 'anthropic',
          fallbackFrom: 'gpt-5',
          inputPrice: 3,
          outputPrice: 15,
        );
      final chat = Chat(id: 'c', title: 't', messages: [ChatMessage.create('user', 'q'), reply]);
      final back = Chat.fromJson(Map<String, dynamic>.from(chat.toJson()));
      final s = back.messages.last.served!;
      expect(s.costClass, CostClass.paid);
      expect(s.model, 'claude-sonnet-4-6');
      expect(s.provider, 'anthropic');
      expect(s.fallbackFrom, 'gpt-5');
      expect(s.inputPrice, 3);
      expect(back.messages.first.served, isNull);
    });
  });
}
