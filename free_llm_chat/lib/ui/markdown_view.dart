import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';

/// Small dependency-free Markdown renderer for chat replies.
/// Supports: fenced code blocks (with copy), headings, bullet and numbered
/// lists, block quotes, horizontal rules, **bold** and `inline code`.
/// Anything else is shown as plain text, so nothing is ever lost.

enum MdKind { paragraph, heading, bullet, numbered, quote, code, rule }

class MdBlock {
  const MdBlock(this.kind, this.text, {this.level = 0, this.marker = '', this.lang = ''});

  final MdKind kind;
  final String text;

  /// Heading level (1-6) or list indentation level (0, 1, 2...).
  final int level;

  /// Number text for numbered items ("1", "2"...).
  final String marker;

  /// Language tag after the opening code fence.
  final String lang;
}

final RegExp _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _ruleRe = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
final RegExp _bulletRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final RegExp _numberedRe = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final RegExp _inlineRe = RegExp(r'`([^`\n]+)`|\*\*([^\n]+?)\*\*');

/// Splits Markdown into blocks. An unclosed code fence (the reply is still
/// streaming) is treated as code up to the end of the text.
List<MdBlock> parseMarkdown(String src) {
  final out = <MdBlock>[];
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  final para = <String>[];

  void flushPara() {
    if (para.isNotEmpty) {
      out.add(MdBlock(MdKind.paragraph, para.join('\n')));
      para.clear();
    }
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();

    if (t.startsWith('```')) {
      flushPara();
      final lang = t.substring(3).trim();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      i++; // Skip the closing fence (or step past the end while streaming).
      out.add(MdBlock(MdKind.code, code.join('\n'), lang: lang));
      continue;
    }

    if (t.isEmpty) {
      flushPara();
      i++;
      continue;
    }

    final h = _headingRe.firstMatch(t);
    if (h != null) {
      flushPara();
      out.add(MdBlock(MdKind.heading, h.group(2)!.trim(), level: h.group(1)!.length));
      i++;
      continue;
    }

    if (_ruleRe.hasMatch(t)) {
      flushPara();
      out.add(const MdBlock(MdKind.rule, ''));
      i++;
      continue;
    }

    final b = _bulletRe.firstMatch(line);
    if (b != null) {
      flushPara();
      out.add(MdBlock(MdKind.bullet, b.group(2)!.trim(), level: b.group(1)!.length ~/ 2));
      i++;
      continue;
    }

    final n = _numberedRe.firstMatch(line);
    if (n != null) {
      flushPara();
      out.add(MdBlock(MdKind.numbered, n.group(3)!.trim(),
          level: n.group(1)!.length ~/ 2, marker: n.group(2)!));
      i++;
      continue;
    }

    if (t.startsWith('>')) {
      flushPara();
      out.add(MdBlock(MdKind.quote, t.substring(1).trim()));
      i++;
      continue;
    }

    para.add(line);
    i++;
  }
  flushPara();
  return out;
}

/// `inline code` and **bold** inside one block of text.
List<InlineSpan> inlineSpans(String s, TextStyle code) {
  final spans = <InlineSpan>[];
  var pos = 0;
  for (final m in _inlineRe.allMatches(s)) {
    if (m.start > pos) spans.add(TextSpan(text: s.substring(pos, m.start)));
    final c = m.group(1);
    if (c != null) {
      spans.add(TextSpan(text: c, style: code));
    } else {
      spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontWeight: FontWeight.w700)));
    }
    pos = m.end;
  }
  if (pos < s.length) spans.add(TextSpan(text: s.substring(pos)));
  return spans;
}

const List<String> _monoFallback = ['Consolas', 'Menlo', 'Roboto Mono', 'monospace'];

class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(height: 1.5);
    final size = base.fontSize ?? 16;
    final codeStyle = base.copyWith(
      fontFamily: 'Consolas',
      fontFamilyFallback: _monoFallback,
      fontSize: size - 1.5,
      backgroundColor: cs.surfaceContainerHigh,
    );

    Widget text(String s, TextStyle style, TextDirection? dir) => SizedBox(
          width: double.infinity,
          child: Text.rich(
            TextSpan(style: style, children: inlineSpans(s, codeStyle)),
            textDirection: dir,
          ),
        );

    final children = <Widget>[];
    for (final b in parseMarkdown(data)) {
      final dir = directionOf(b.text);
      switch (b.kind) {
        case MdKind.paragraph:
          children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: text(b.text, base, dir)));
        case MdKind.heading:
          final extra = b.level <= 1 ? 6.0 : (b.level == 2 ? 3.0 : 1.0);
          children.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: text(b.text, base.copyWith(fontSize: size + extra, fontWeight: FontWeight.w700), dir),
          ));
        case MdKind.bullet:
        case MdKind.numbered:
          final mark = b.kind == MdKind.bullet ? '•' : '${b.marker}.';
          children.add(Directionality(
            textDirection: dir ?? Directionality.of(context),
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: 8.0 + 16.0 * b.level, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: Text(mark, style: base)),
                  Expanded(child: text(b.text, base, dir)),
                ],
              ),
            ),
          ));
        case MdKind.quote:
          children.add(Directionality(
            textDirection: dir ?? Directionality.of(context),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsetsDirectional.only(start: 12),
              decoration: BoxDecoration(
                border: BorderDirectional(start: BorderSide(color: cs.outlineVariant, width: 3)),
              ),
              child: text(b.text, base.copyWith(color: cs.onSurfaceVariant), dir),
            ),
          ));
        case MdKind.rule:
          children.add(const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)));
        case MdKind.code:
          children.add(_CodeBlock(code: b.text, lang: b.lang, style: codeStyle.copyWith(backgroundColor: Colors.transparent)));
      }
    }

    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.lang, required this.style});

  final String code;
  final String lang;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2, bottom: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(lang,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
                  ),
                  IconButton(
                    tooltip: context.tr('copy'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: cs.outline,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => _copyCode(context, code),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(code, style: style),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _copyCode(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  final done = context.trNow('copied');
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 1)));
}
