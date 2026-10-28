import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'message_time.dart';

/// The waiting-for-answer affordance: a label plus dots that animate on their
/// own frame timer, independent of token arrival.
///
/// The timer lives with this widget only, so it stops the moment the
/// placeholder leaves the tree (answer began, cancel, or error).
class AnimatedPlaceholder extends StatefulWidget {
  const AnimatedPlaceholder({super.key, required this.label});

  /// `Waiting` or `Thinking`.
  final String label;

  static const frameRate = Duration(milliseconds: 320);

  @override
  State<AnimatedPlaceholder> createState() => _AnimatedPlaceholderState();
}

class _AnimatedPlaceholderState extends State<AnimatedPlaceholder> {
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(AnimatedPlaceholder.frameRate, (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % 3);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '${widget.label}${'.' * (_frame + 1)}',
      style: theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor),
    );
  }
}

/// One conversation turn.
///
/// An assistant turn is rendered as GitHub-flavoured markdown; a user turn
/// shows exactly what was typed. Rendering is display-only: the stored and
/// transmitted text stays raw markdown, so exports and the wire format are
/// untouched. Reasoning is deliberately never rendered: only [content] reaches
/// the screen. While a reply has no visible text yet, [placeholderLabel] drives
/// the animated `Waiting` / `Thinking` placeholder.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.content,
    required this.isMine,
    this.placeholderLabel,
    this.createdAt,
  });

  final String content;
  final bool isMine;
  final String? placeholderLabel;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bubbleColor = isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (content.isNotEmpty)
              isMine
                  ? SelectableText(content, style: theme.textTheme.bodyLarge)
                  : _ReplyMarkdown(data: content, theme: theme),
            if (placeholderLabel != null) AnimatedPlaceholder(
              label: placeholderLabel!,
            ),
            if (createdAt != null)
              Text(
                formatMessageTime(createdAt!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isMine
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An assistant turn, rendered.
///
/// Selection stays on: copying a reply is a daily affordance. A single newline
/// from the model stays a line break, because CommonMark would otherwise
/// collapse it and run the lines together - in a chat reply that reads as
/// damage, not as a missing blank line.
///
/// [MarkdownBody.onTapLink] is deliberately unset, so the package's default
/// handler does nothing: a link in a reply cannot lead the app anywhere. The
/// same holds for images - see [_replyImage].
class _ReplyMarkdown extends StatelessWidget {
  const _ReplyMarkdown({required this.data, required this.theme});

  final String data;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: _replyStyleSheet(theme),
      imageBuilder: (uri, title, alt) => _replyImage(theme, alt),
    );
  }
}

/// What an image reference in a reply becomes.
///
/// A reply can name an image on a host the user never configured, and the app
/// never contacts a destination the user did not choose. So the reference is
/// shown as text - its alternative text when the model supplied one, otherwise
/// a marker naming it as an image - and nothing is fetched.
Widget _replyImage(ThemeData theme, String? alt) {
  final label = (alt != null && alt.trim().isNotEmpty) ? alt.trim() : '[image]';
  return Text(
    label,
    style: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontStyle: FontStyle.italic,
    ),
  );
}

/// The reply's typography, derived from the app theme so light and dark stay
/// correct on their own.
///
/// The package's default sheet sets its own text styles, which is exactly how a
/// rendered reply ends up a different size from a user bubble. Everything here
/// comes from the theme; only the few shapes the package cannot inherit -
/// inline code, block edges, link affordance - are added.
MarkdownStyleSheet _replyStyleSheet(ThemeData theme) {
  final scheme = theme.colorScheme;
  final body = theme.textTheme.bodyLarge ?? const TextStyle();
  final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
    // Match the user bubble exactly, so the two roles differ in shape, not size.
    p: body,
    listBullet: body,
    blockquote: body.copyWith(color: scheme.onSurfaceVariant),
    tableBody: body,
    // Inert (see [_ReplyMarkdown]) but still legible as a link: colour plus
    // underline, never colour alone.
    a: body.copyWith(color: scheme.primary, decoration: TextDecoration.underline),
    // Inline code: monospace at a size that reads as code without shrinking
    // below comfortable body size, and text kept on the bubble's own token so
    // the code's own background never carries the contrast.
    code: (theme.textTheme.bodySmall ?? body).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier', 'monospace'],
      fontSize: (body.fontSize ?? 14) * 0.85,
      color: scheme.onSurface,
      backgroundColor: scheme.surfaceContainerLowest,
    ),
    // A code block's tint alone does not read against the assistant bubble
    // (about 1.3:1), so its edge is drawn with a line that clears WCAG AA for
    // non-text content in both themes. Same for table rules and quotes.
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerLowest,
      border: Border.all(color: scheme.onSurfaceVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: scheme.onSurfaceVariant, width: 3),
      ),
    ),
    tableBorder: TableBorder.all(color: scheme.onSurfaceVariant),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.onSurfaceVariant, width: 1)),
    ),
  );
  // Headings keep the package's relative sizes (the structure is why the
  // feature exists) but take the body's font family and colour, so a heading
  // cannot come out in a face or ink the theme did not choose.
  TextStyle? themed(TextStyle? style) => style?.copyWith(
    inherit: false,
    color: scheme.onSurface,
    fontFamily: style.fontFamily ?? body.fontFamily,
  );
  return sheet.copyWith(
    h1: themed(sheet.h1),
    h2: themed(sheet.h2),
    h3: themed(sheet.h3),
    h4: themed(sheet.h4),
    h5: themed(sheet.h5),
    h6: themed(sheet.h6),
  );
}
