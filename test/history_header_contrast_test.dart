import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG AA contrast for the history drawer's section headers in both themes.
///
/// Headers use `onSurfaceVariant` (labelLarge) on the drawer background, which
/// defaults to `surfaceContainerLow` in this Flutter version (see
/// flutter/lib/src/material/drawer.dart). These ratios are computed from the
/// same seed and scheme construction the app uses in `lib/main.dart`.
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
    test('the section header meets WCAG AA in $brightness', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );

      expect(
        _ratio(scheme.onSurfaceVariant, scheme.surfaceContainerLow),
        greaterThanOrEqualTo(4.5),
        reason: 'the $brightness section header must meet WCAG AA',
      );
    });
  }
}
