import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/ui/markdown_view.dart';

void main() {
  test('parses code fence, heading, lists and paragraph', () {
    final b = parseMarkdown('# Title\n\nHello **world**\n\n- one\n- two\n1. first\n\n```dart\nvar a = 1;\n```\n');
    expect(b.map((e) => e.kind), [
      MdKind.heading,
      MdKind.paragraph,
      MdKind.bullet,
      MdKind.bullet,
      MdKind.numbered,
      MdKind.code,
    ]);
    expect(b.first.level, 1);
    expect(b.last.lang, 'dart');
    expect(b.last.text, 'var a = 1;');
  });

  test('an unclosed fence (still streaming) becomes code to the end', () {
    final b = parseMarkdown('text\n```py\nprint(1)\nprint(2)');
    expect(b.last.kind, MdKind.code);
    expect(b.last.text, 'print(1)\nprint(2)');
  });

  test('bold at line start is not a bullet', () {
    final b = parseMarkdown('**Note:** careful');
    expect(b.single.kind, MdKind.paragraph);
  });

  test('inline spans split bold and code', () {
    final spans = inlineSpans('a **b** `c` d', const TextStyle());
    expect(spans.map((s) => (s as TextSpan).text), ['a ', 'b', ' ', 'c', ' d']);
  });
}
