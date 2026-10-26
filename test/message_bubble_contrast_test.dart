import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG AA contrast for the message timestamp label in both themes.
///
/// The label uses the bubble's on-container token: `onPrimaryContainer` on the
/// user bubble (`primaryContainer`) and `onSurface` on the assistant bubble
/// (`surfaceContainerHighest`). These ratios are computed from the same seed
/// and scheme construction the app uses in `lib/main.dart`.
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
  }
}
