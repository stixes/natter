// Renders the legacy launcher PNGs (Android 6.0 to 7.1) from the same painter
// the app uses. Lives in tool/ so the default `flutter test` never runs it.
//
//   flutter test tool/render_launcher_icons_test.dart
//
// Run from the repo root; the output is committed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/ui/natter_mark.dart';

const _densities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render legacy launcher icons', () async {
    const painter = NatterMarkPainter(
      bubbleColor: NatterLauncherPalette.bubble,
      faceColor: NatterLauncherPalette.face,
      blushColor: NatterLauncherPalette.blush,
      backgroundColor: NatterLauncherPalette.background,
      viewport: NatterMarkGeometry.launcherViewport,
    );

    for (final MapEntry(key: density, value: px) in _densities.entries) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Size.square(px.toDouble()));
      final image = await recorder.endRecording().toImage(px, px);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      await file.writeAsBytes(png!.buffer.asUint8List());
    }
  });
}
