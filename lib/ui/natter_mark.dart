import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Geometry of the Natter mark on the 108-unit adaptive-icon grid.
///
/// The Android launcher layers (`res/drawable/ic_launcher_foreground.xml`
/// and `ic_launcher_monochrome.xml`) transcribe these numbers by hand, so a
/// change here owes the same change there.
abstract final class NatterMarkGeometry {
  static const double grid = 108;
  static const Offset centre = Offset(54, 54);

  /// Adaptive icons promise only this circle survives every launcher mask.
  static const double safeZoneRadius = 33;

  /// The whole mark leans this far, about [centre], for the quirky tilt.
  static const double tiltDegrees = -8;

  static const Rect bubble = Rect.fromLTRB(26, 30, 82, 72);
  static const double bubbleRadius = 20;

  /// Tail at the bubble's lower left: two base points inside it, one tip.
  static const List<Offset> tail = [
    Offset(36, 64),
    Offset(50, 70),
    Offset(34, 79),
  ];

  static const Offset leftEye = Offset(44, 47);
  static const double leftEyeRadius = 4.5;
  static const Offset rightEye = Offset(64, 46);
  static const double rightEyeRadius = 5.5;

  /// A small "o", slightly right of centre, as if mid-word.
  static const Offset mouth = Offset(56, 59);
  static const Size mouthRadii = Size(3.5, 4);

  static const Offset leftBlush = Offset(38, 57);
  static const Offset rightBlush = Offset(70, 57);
  static const Size blushRadii = Size(4.5, 2.8);

  /// The part of the grid an adaptive-icon mask shows (the inner 72 units).
  static const Rect launcherViewport = Rect.fromLTWH(18, 18, 72, 72);

  /// A tight crop around the tilted bubble, for small in-app use.
  static const Rect tightViewport = Rect.fromLTWH(22, 22, 64, 64);
}

/// Fixed launcher colours from the 0xFF6750A4 seed's tonal palette; the
/// launcher cannot read the Flutter theme. Mirrored in
/// `res/values/ic_launcher_background.xml` and the foreground drawable.
abstract final class NatterLauncherPalette {
  static const Color background = Color(0xFF6750A4); // primary 40
  static const Color bubble = Color(0xFFEADDFF); // primary 90
  static const Color face = Color(0xFF21005D); // primary 10
  static const Color blush = Color(0xFFEFB8C8); // tertiary 80
}

typedef _G = NatterMarkGeometry;

class NatterMarkPainter extends CustomPainter {
  const NatterMarkPainter({
    required this.bubbleColor,
    required this.faceColor,
    required this.blushColor,
    this.backgroundColor,
    this.viewport = NatterMarkGeometry.tightViewport,
  });

  final Color bubbleColor;
  final Color faceColor;
  final Color blushColor;

  /// When set, fills the canvas as a rounded square first (legacy icons).
  final Color? backgroundColor;

  /// The region of the 108-unit grid scaled to fill the canvas.
  final Rect viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final background = backgroundColor;
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.shortestSide * 0.22),
        ),
        Paint()..color = background,
      );
    }

    canvas.save();
    canvas.scale(size.width / viewport.width, size.height / viewport.height);
    canvas.translate(-viewport.left, -viewport.top);
    canvas.translate(_G.centre.dx, _G.centre.dy);
    canvas.rotate(_G.tiltDegrees * math.pi / 180);
    canvas.translate(-_G.centre.dx, -_G.centre.dy);

    final bubble = Paint()..color = bubbleColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _G.bubble,
        const Radius.circular(_G.bubbleRadius),
      ),
      bubble,
    );
    canvas.drawPath(Path()..addPolygon(_G.tail, true), bubble);

    final blush = Paint()..color = blushColor;
    for (final cheek in [_G.leftBlush, _G.rightBlush]) {
      canvas.drawOval(_oval(cheek, _G.blushRadii), blush);
    }

    final face = Paint()..color = faceColor;
    canvas.drawCircle(_G.leftEye, _G.leftEyeRadius, face);
    canvas.drawCircle(_G.rightEye, _G.rightEyeRadius, face);
    canvas.drawOval(_oval(_G.mouth, _G.mouthRadii), face);

    canvas.restore();
  }

  static Rect _oval(Offset centre, Size radii) => Rect.fromCenter(
    center: centre,
    width: radii.width * 2,
    height: radii.height * 2,
  );

  @override
  bool shouldRepaint(NatterMarkPainter oldDelegate) =>
      oldDelegate.bubbleColor != bubbleColor ||
      oldDelegate.faceColor != faceColor ||
      oldDelegate.blushColor != blushColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.viewport != viewport;
}

/// The Natter mark in the active colour scheme. Decorative: callers that
/// place it beside a title exclude it from semantics.
class NatterMark extends StatelessWidget {
  const NatterMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: NatterMarkPainter(
        bubbleColor: scheme.primaryContainer,
        faceColor: scheme.onPrimaryContainer,
        blushColor: scheme.tertiary.withValues(alpha: 0.5),
      ),
    );
  }
}
