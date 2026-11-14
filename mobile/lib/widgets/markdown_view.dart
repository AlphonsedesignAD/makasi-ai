import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';


/// Rendu Markdown léger et soigné (titres, listes, code, liens, citations).
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    this.baseStyle,
    this.color,
  });

  final String text;
  final TextStyle? baseStyle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (baseStyle ?? theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: color ?? theme.colorScheme.onSurface);

    final blocks = <Widget>[];
    final fence = RegExp(r'```([\w+-]*)[ \t]*\n?([\s\S]*?)(?:```|$)');
    var last = 0;

    for (final match in fence.allMatches(text)) {
      if (match.start > last) {
        _appendTextBlocks(blocks, text.substring(last, match.start), style, context);
      }
      final language = (match.group(1) ?? '').trim();
      var code = match.group(2) ?? '';
      if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
      blocks.add(
        _CodeBlock(
          language: language,
          code: code,
          key: ValueKey('${language}_${code.hashCode}_${blocks.length}'),
        ),
      );
      last = match.end;
    }

    if (last < text.length) {
      _appendTextBlocks(blocks, text.substring(last), style, context);
    }

    if (blocks.isEmpty) {
      return Text(text, style: style);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  void _appendTextBlocks(
    List<Widget> out,
    String segment,
    TextStyle style,
    BuildContext context,
  ) {
    final lines = segment.split('\n');
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final content = paragraph.join('\n').trimRight();
      paragraph.clear();
      if (content.trim().isEmpty) return;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(
            TextSpan(children: _buildInlineSpans(content, style, context)),
            style: style,
          ),
        ),
      );
    }

    for (final raw in lines) {
      final line = raw.trimRight();

      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        flushParagraph();
        final level = heading.group(1)!.length;
        final title = heading.group(2)!;
        final size = level == 1 ? 20.0 : (level == 2 ? 17.5 : 15.5);
        out.add(
          Padding(
            padding: EdgeInsets.only(top: out.isEmpty ? 0 : 8, bottom: 7),
            child: Text.rich(
              TextSpan(
                children: _buildInlineSpans(
                  title,
                  style.copyWith(
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                  context,
                ),
              ),
              style: style.copyWith(
                fontSize: size,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: -0.2,
              ),
            ),
          ),
        );
        continue;
      }

      final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        out.add(
          _ListLine(
            marker: '•',
            content: bullet.group(1) ?? '',
            style: style,
          ),
        );
        continue;
      }

      final numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (numbered != null) {
        flushParagraph();
        out.add(
          _ListLine(
            marker: '${numbered.group(1)}.',
            content: numbered.group(2) ?? '',
            style: style,
          ),
        );
        continue;
      }

      final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);
      if (quote != null) {
        flushParagraph();
        out.add(_QuoteLine(content: quote.group(1) ?? '', style: style));
        continue;
      }

      if (RegExp(r'^\s*([-*_])\s*(\1\s*){2,}$').hasMatch(line)) {
        flushParagraph();
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Theme.of(context).colorScheme.outline),
          ),
        );
        continue;
      }

      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      paragraph.add(line);
    }

    flushParagraph();
  }

}

List<InlineSpan> _buildInlineSpans(
  String text,
  TextStyle base,
  BuildContext context,
) {
  final colors = Theme.of(context).colorScheme;
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'(`[^`\n]+`|\*\*[^*\n]+\*\*|\*[^*\n]+\*|\[[^\]]+\]\(https?://[^\s)]+\))',
  );

  var index = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    final token = match.group(0)!;

    if (token.startsWith('`') && token.endsWith('`') && token.length > 2) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.9,
            backgroundColor: colors.surfaceContainerHighest,
            color: colors.onSurface,
          ),
        ),
      );
    } else if (token.startsWith('**') && token.endsWith('**')) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    } else if (token.startsWith('*') &&
        token.endsWith('*') &&
        token.length > 2) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else if (token.startsWith('[')) {
      final link =
          RegExp(r'^\[([^\]]+)\]\((https?://[^\s)]+)\)$').firstMatch(token);
      if (link != null) {
        final label = link.group(1) ?? '';
        final url = link.group(2) ?? '';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => _openLinkUrl(url),
              child: Text(
                label,
                style: base.copyWith(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.primary.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: token));
      }
    } else {
      spans.add(TextSpan(text: token));
    }

    index = match.end;
  }

  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return spans;
}

Future<void> _openLinkUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Lien non ouvrable : on ignore silencieusement.
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({
    required this.marker,
    required this.content,
    required this.style,
  });

  final String marker;
  final String content;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                marker,
                style: style.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: _buildInlineSpans(content, style, context),
              ),
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteLine extends StatelessWidget {
  const _QuoteLine({required this.content, required this.style});

  final String content;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: colors.primary.withValues(alpha: 0.7), width: 2.5),
        ),
      ),
      child: Text(
        content,
        style: style.copyWith(
          color: colors.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    super.key,
    required this.language,
    required this.code,
  });

  final String language;
  final String code;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié !'), duration: Duration(milliseconds: 1400)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    const codeColor = Color(0xFFE6EDF3);
    const bg = Color(0xFF0D1117);
    final label = widget.language.trim().isEmpty ? 'code' : widget.language.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                _dot(const Color(0xFFFF5F57)),
                const SizedBox(width: 5),
                _dot(const Color(0xFFFEBC2E)),
                const SizedBox(width: 5),
                _dot(const Color(0xFF28C840)),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.45),
                    letterSpacing: 0.1,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _copy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                          size: 12,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copié' : 'Copier',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
            child: Text(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.2,
                height: 1.55,
                color: codeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
