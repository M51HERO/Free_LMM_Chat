import 'models.dart';

/// Rough budget for the conversation sent with each request (characters, not
/// tokens: about 4 characters per token, so this is roughly 6k-8k tokens).
/// Small enough for the small free models, large enough for normal chats.
const int kMaxHistoryChars = 24000;

/// Returns the most recent messages that fit in [maxChars].
/// - The newest message is always kept, even if it alone exceeds the budget.
/// - The result starts with a user message (a reply without its question
///   confuses some providers).
/// The stored chat is never changed: only what is sent.
List<ChatMessage> trimHistory(List<ChatMessage> messages, {int maxChars = kMaxHistoryChars}) {
  if (messages.isEmpty) return const [];
  var total = 0;
  var start = messages.length;
  for (var i = messages.length - 1; i >= 0; i--) {
    final len = messages[i].content.length;
    if (start < messages.length && total + len > maxChars) break;
    total += len;
    start = i;
  }
  while (start < messages.length - 1 && messages[start].role != 'user') {
    start++;
  }
  return messages.sublist(start);
}
