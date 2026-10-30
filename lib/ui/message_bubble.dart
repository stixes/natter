import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

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
///
/// [copyText] says the turn is committed and names the text a copy control
/// offers; the in-flight draft passes null, which also takes the code block
/// buttons away - an answer still arriving has nothing committed to copy.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.content,
    required this.isMine,
    this.copyText,
    this.placeholderLabel,
    this.createdAt,
  });

  final String content;
  final bool isMine;

  /// The text a copy control offers, or null for "no copy affordance at all".
  ///
  /// An assistant turn passes its markdown source, so a paste round-trips what
  /// the endpoint produced; a user turn passes what was typed.
  final String? copyText;
  final String? placeholderLabel;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bubbleColor = isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final ink = isMine ? scheme.onPrimaryContainer : scheme.onSurface;
    final time = createdAt == null
        ? null
        : Text(
            formatMessageTime(createdAt!),
            style: theme.textTheme.labelSmall?.copyWith(color: ink),
          );

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
                  : _ReplyMarkdown(
                      data: content,
                      theme: theme,
                      copyEnabled: copyText != null,
                    ),
            if (placeholderLabel != null) AnimatedPlaceholder(
              label: placeholderLabel!,
            ),
            // The footer carries whatever the turn has. A timestamp on its own
            // stays a bare Text, so a plain bubble keeps the widget order the
            // timestamp spec pins; a copy control joins it in one row.
            if (time != null && copyText != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  time,
                  _CopyControl(
                    text: copyText!,
                    actionLabel: 'Copy message',
                    color: ink,
                  ),
                ],
              )
            else if (time != null)
              time
            else if (copyText != null)
              _CopyControl(
                text: copyText!,
                actionLabel: 'Copy message',
                color: ink,
              ),
          ],
        ),
      ),
    );
  }
}

/// The copy affordance on a turn, and on one rendered code block.
///
/// A tap writes [text] to the clipboard and the icon answers by swapping to a
/// check for [confirmFor]: the copy is confirmed where it was made, with no
/// surface to dismiss. Like [AnimatedPlaceholder]'s, the timer belongs to this
/// state and stops the moment the control leaves the tree.
class _CopyControl extends StatefulWidget {
  const _CopyControl({
    required this.text,
    required this.actionLabel,
    required this.color,
  });

  final String text;

  /// What the control offers, as its tooltip and its screen-reader label.
  final String actionLabel;

  /// The bubble's own ink token, so the icon carries the contrast its
  /// neighbouring text does.
  final Color color;

  static const confirmFor = Duration(milliseconds: 1200);

  @override
  State<_CopyControl> createState() => _CopyControlState();
}

class _CopyControlState extends State<_CopyControl> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(_CopyControl.confirmFor, () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // The label is carried here rather than left to the tooltip: a tooltip on
      // an icon button does not reach the Android accessibility tree, so the
      // control would otherwise be named nothing. It is also a live region, so
      // a screen reader hears the copy happen instead of hearing the button's
      // label only once.
      liveRegion: true,
      button: true,
      label: _copied ? 'Copied' : widget.actionLabel,
      child: IconButton(
        tooltip: widget.actionLabel,
        color: widget.color,
        iconSize: 24,
        icon: Icon(_copied ? Icons.check : Icons.content_copy),
        onPressed: _copy,
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
  const _ReplyMarkdown({
    required this.data,
    required this.theme,
    this.copyEnabled = true,
  });

  final String data;
  final ThemeData theme;

  /// Whether a rendered code block may carry a copy button.
  ///
  /// The in-flight draft passes false: an answer still arriving has nothing
  /// committed to copy, so no button appears mid-stream either.
  final bool copyEnabled;

  @override
  Widget build(BuildContext context) {
    final sheet = _replyStyleSheet(theme);
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: sheet,
      // The code block is taken over so it can carry a copy button of its own.
      // The builder reads the same sheet, so its text, box, and button stay on
      // the tokens this sheet chose.
      builders: {
        'pre': _CodeBlockBuilder(
          sheet: sheet,
          copyEnabled: copyEnabled,
          // The block button carries the ink its own code text is drawn in, so
          // icon and code agree in either theme.
          ink: sheet.code?.color ?? theme.colorScheme.onSurface,
        ),
      },
      imageBuilder: (uri, title, alt) => _replyImage(theme, alt),
    );
  }
}

/// A rendered fenced code block: its text, its sideways scroll, its copy button.
///
/// The package builds a `pre` block on its own - text wrapped in a `Scrollbar`
/// and a horizontal `SingleChildScrollView`, then tinted with the sheet's
/// `codeblockDecoration` (`flutter_markdown_plus-1.0.7/lib/src/builder.dart:
/// 344-357, 470-476`). That scroll wrapper is private, so taking the block over
/// means reproducing it here, one controller per block. It also means the
/// wrap-versus-scroll decision, if it is ever taken, lands here.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({
    required this.sheet,
    required this.copyEnabled,
    required this.ink,
  });

  final MarkdownStyleSheet sheet;

  /// The ink the block's own code text is drawn in.
  final Color ink;

  final bool copyEnabled;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // The same trailing-newline strip the package's own delegate applies, so a
    // pasted block does not end on a blank line. This is the string the block
    // draws, never the fenced source.
    final code = text.text.replaceAll(RegExp(r'\n$'), '');
    final codeText = SelectableText.rich(
      // A unique key keeps two blocks in one reply from sharing state, as the
      // package does for every piece of text it builds.
      key: UniqueKey(),
      TextSpan(style: sheet.code, text: code),
      textScaler: sheet.textScaler,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (copyEnabled)
          Align(
            // Above the code, never over it: the scroll view keeps the box's
            // whole width, so the sideways drag region is untouched.
            alignment: Alignment.topRight,
            child: _CopyControl(
              text: code,
              actionLabel: 'Copy code block',
              color: ink,
            ),
          ),
        _CodeBlockScroll(
          padding: sheet.codeblockPadding ?? const EdgeInsets.all(8),
          child: codeText,
        ),
      ],
    );
  }
}

/// The block's sideways scroll, with a controller of its own per block.
///
/// A reproduction of what the package does for a `pre` block - a `Scrollbar`
/// bound to a horizontal `SingleChildScrollView` - because that copy is
/// private and the block is taken over to carry a button.
class _CodeBlockScroll extends StatefulWidget {
  const _CodeBlockScroll({required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<_CodeBlockScroll> createState() => _CodeBlockScrollState();
}

class _CodeBlockScrollState extends State<_CodeBlockScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: widget.child,
      ),
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
