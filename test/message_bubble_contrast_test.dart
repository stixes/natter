import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG AA contrast for the message timestamp label and for every pair the
/// rendered reply puts on screen, in both themes.
///
/// The label uses the bubble's on-container token: `onPrimaryContainer` on the
/// user bubble (`primaryContainer`) and `onSurface` on the assistant bubble
/// (`surfaceContainerHighest`). The reply pairs come from the style sheet in
/// `lib/ui/message_bubble.dart`: prose, table text, and code text on their
/// backgrounds, link text on the assistant bubble, and the structural lines
/// (code block edge, table rules, quote bar) against their surroundings.
/// Ratios are computed from the same seed and scheme construction the app uses
/// in `lib/main.dart`.
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  final hi = max(la, lb);
  final lo = min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const _seed = Color(0xFF6750A4);

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    test('the timestamp label meets WCAG AA in $brightness', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );

      // User bubble: onPrimaryContainer on primaryContainer.
      expect(
        _ratio(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness user label must meet WCAG AA',
      );

      // Assistant bubble: onSurface on surfaceContainerHighest.
      expect(
        _ratio(scheme.onSurface, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness assistant label must meet WCAG AA',
      );
    });

    test('the copy control meets WCAG AA on its bubble in $brightness', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );

      // The control carries the same ink token as the timestamp beside it, so
      // it clears the bar the label clears. An icon-only control has no text,
      // but its glyph still has to read against the bubble.
      expect(
        _ratio(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness control on the user bubble must clear AA',
      );
      expect(
        _ratio(scheme.onSurface, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
        reason:
            'the $brightness control on the assistant bubble must clear AA',
      );
    });

    test('a rendered reply meets WCAG AA in $brightness', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );
      final bubble = scheme.surfaceContainerHighest;
      final codeFill = scheme.surfaceContainerLowest;

      // Reply prose and table cells sit directly on the assistant bubble.
      expect(
        _ratio(scheme.onSurface, bubble),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness reply text must meet WCAG AA',
      );

      // Code text against the code block's fill.
      expect(
        _ratio(scheme.onSurface, codeFill),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness code text must meet WCAG AA',
      );

      // Link text on the bubble. Links are never underlined-and-coloured alone:
      // the underline carries the signal if a scheme narrows this ratio.
      expect(
        _ratio(scheme.primary, bubble),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness link text must meet WCAG AA',
      );

      // Structural lines. The code block's fill reads only about 1.3:1 against
      // the bubble, so its edge - and the table rules and quote bar - must
      // clear WCAG AA's 3:1 for non-text content against both surroundings.
      expect(
        _ratio(scheme.onSurfaceVariant, bubble),
        greaterThanOrEqualTo(3.0),
        reason: 'the $brightness table and quote lines must be perceivable',
      );
      expect(
        _ratio(scheme.onSurfaceVariant, codeFill),
        greaterThanOrEqualTo(3.0),
        reason: 'the $brightness code block edge must be perceivable',
      );
    });
  }
}
