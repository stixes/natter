import 'dart:async';

import 'package:flutter/material.dart';

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

/// One conversation turn, rendered as plain text.
///
/// Reasoning is deliberately never rendered: only [content] reaches the
/// screen. While a reply has no visible text yet, [placeholderLabel] drives
/// the animated `Waiting` / `Thinking` placeholder.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.content,
    required this.isMine,
    this.placeholderLabel,
  });

  final String content;
  final bool isMine;
  final String? placeholderLabel;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (content.isNotEmpty)
              SelectableText(content, style: theme.textTheme.bodyLarge),
            if (placeholderLabel != null) AnimatedPlaceholder(
              label: placeholderLabel!,
            ),
          ],
        ),
      ),
    );
  }
}
