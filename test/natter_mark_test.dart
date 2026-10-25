import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/ui/natter_mark.dart';

typedef _G = NatterMarkGeometry;

const _painter = NatterMarkPainter(
  bubbleColor: Color(0xFF000001),
  faceColor: Color(0xFF000002),
  blushColor: Color(0xFF000003),
);

NatterMarkPainter _paintedMark(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!
        as NatterMarkPainter;

void main() {
  group('geometry', () {
    // Rotation about the centre keeps distances, so the untilted numbers
    // are enough to prove no launcher mask can crop the face.
    test('eyes and mouth sit inside the adaptive-icon safe zone', () {
      final features = {
        'left eye': (_G.leftEye, _G.leftEyeRadius),
        'right eye': (_G.rightEye, _G.rightEyeRadius),
        'mouth': (_G.mouth, _G.mouthRadii.longestSide),
      };
      for (final MapEntry(key: name, value: (centre, radius))
          in features.entries) {
        final reach = (centre - _G.centre).distance + radius;
        expect(reach, lessThan(_G.safeZoneRadius), reason: name);
      }
    });

    test('the tail tip stays inside the safe zone', () {
      expect((_G.tail.last - _G.centre).distance, lessThan(_G.safeZoneRadius));
    });
  });

  group('shouldRepaint', () {
    test('is false when nothing changes', () {
      expect(_painter.shouldRepaint(_painter), isFalse);
    });

    test('is true when any colour changes', () {
      const changed = [
        NatterMarkPainter(
          bubbleColor: Color(0xFF0000FF),
          faceColor: Color(0xFF000002),
          blushColor: Color(0xFF000003),
        ),
        NatterMarkPainter(
          bubbleColor: Color(0xFF000001),
          faceColor: Color(0xFF0000FF),
          blushColor: Color(0xFF000003),
        ),
        NatterMarkPainter(
          bubbleColor: Color(0xFF000001),
          faceColor: Color(0xFF000002),
          blushColor: Color(0xFF0000FF),
        ),
      ];
      for (final painter in changed) {
        expect(painter.shouldRepaint(_painter), isTrue);
      }
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('NatterMark paints from the ${brightness.name} scheme', (
      tester,
    ) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme, useMaterial3: true),
          home: const Center(child: NatterMark()),
        ),
      );

      final painter = _paintedMark(tester);
      expect(painter.bubbleColor, scheme.primaryContainer);
      expect(painter.faceColor, scheme.onPrimaryContainer);
      expect(painter.blushColor, scheme.tertiary.withValues(alpha: 0.5));
      expect(tester.getSize(find.byType(NatterMark)), const Size.square(24));
    });
  }
}
