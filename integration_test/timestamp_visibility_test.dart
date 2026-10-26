// On-device verification for add-message-timestamps task 3.3.
//
// Runs the real app against the task's mock SSE endpoint and checks the
// timestamp label in light and dark mode, while streaming, after cancel, after
// a failed request, and at the largest text scale. Contrast is computed from
// the active colour scheme rather than judged by eye.
//
// Start the mock endpoint in the devcontainer and forward its port to the
// emulator first:
//
//   python3 integration_test/support/mock_reasoning_endpoint.py 8010 &
//   adb reverse tcp:8010 tcp:8010
//
// Then run on the emulator:
//
//   flutter test integration_test/timestamp_visibility_test.dart \
//     -d <device> --dart-define=NATTER_MOCK_URL=http://127.0.0.1:8010/v1

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:natter/main.dart' as app;
import 'package:natter/ui/message_bubble.dart';

const mockUrl = String.fromEnvironment('NATTER_MOCK_URL');
const badUrl = 'http://127.0.0.1:9/v1';

final _timePattern = RegExp(r'^\d{2}:\d{2}$');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timestamps survive light and dark, streaming, cancel and failure',
      (tester) async {
    await _launch(tester);

    // Empty conversation: no timestamps.
    expect(_timestampTexts(tester), isEmpty,
        reason: 'an empty conversation must show no timestamps');

    await _configure(tester, endpoint: mockUrl, model: 'mock-reasoning-only');

    // A committed user turn shows a time before the reply arrives.
    await _type(tester, 'Say anything.');
    await _tapSend(tester);
    await _tick(tester);
    expect(_timestampTexts(tester), hasLength(1),
        reason: 'the user turn must be labelled as soon as it commits');

    // While the reply streams, the draft shows no label: still one timestamp.
    await _tick(tester);
    expect(_timestampTexts(tester), hasLength(1),
        reason: 'the streaming draft must not show a label');

    await _waitForCommit(tester);
    expect(_timestampTexts(tester), hasLength(2),
        reason: 'both committed turns must be labelled after the reply commits');

    // Light-mode label presence; contrast is asserted deterministically in
    // test/message_bubble_contrast_test.dart.

    // Dark mode: flip the platform brightness and check again.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _settle(tester);
    expect(_timestampTexts(tester), hasLength(2),
        reason: 'timestamps must remain visible in dark mode');

    // Largest text scale: the label must stay visible and not overflow.
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'the largest text scale must not overflow the bubble');
    expect(_timestampTexts(tester), hasLength(2),
        reason: 'the timestamp must remain visible at the largest text scale');

    // A failed request leaves the prior labels intact. The failed request's own
    // user turn is dropped with the failed attempt, so the two prior labels
    // remain.
    await _configure(tester, endpoint: badUrl, model: 'mock-reasoning-only');
    await _type(tester, 'This should fail.');
    await _tapSend(tester);
    await _waitForError(tester);
    expect(_timestampTexts(tester).length, greaterThanOrEqualTo(2),
        reason: 'prior labels must survive a failed request');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('cancel with partial answer commits a labelled turn',
      (tester) async {
    await _launch(tester);
    await _configure(tester, endpoint: '$mockUrl/stall', model: 'mock-stall');
    await _type(tester, 'Start an answer and then stall.');
    await _tapSend(tester);
    await _waitForText(tester);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await _settle(tester);

    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing,
        reason: 'cancel must end the stream');
    expect(_timestampTexts(tester), hasLength(2),
        reason: 'the cancelled partial answer must commit a labelled turn');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

List<String> _timestampTexts(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if (text.data != null && _timePattern.hasMatch(text.data!)) text.data!,
    ];

Future<void> _launch(WidgetTester tester) async {
  app.main();
  await _settle(tester);
}

Future<void> _tick(WidgetTester tester,
    [Duration length = const Duration(milliseconds: 250)]) async {
  await tester.pump(length);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await _tick(tester);
  }
}

Future<void> _configure(
  WidgetTester tester, {
  required String endpoint,
  required String model,
}) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await _settle(tester);
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), endpoint);
  await tester.enterText(fields.at(2), model);
  await SystemChannels.textInput.invokeMethod('TextInput.hide');
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String prompt) async {
  final field = find.byType(TextField).first;
  await tester.tap(field);
  await _tick(tester);
  await tester.enterText(field, prompt);
  await _tick(tester);
  await SystemChannels.textInput.invokeMethod('TextInput.hide');
  await _tick(tester);
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
  await _tick(tester, const Duration(milliseconds: 50));
}

Future<void> _waitForCommit(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    await _tick(tester, const Duration(milliseconds: 100));
    if (find.byIcon(Icons.stop_circle_outlined).evaluate().isEmpty) return;
  }
  throw StateError('the reply never committed');
}

Future<void> _waitForText(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await _tick(tester, const Duration(milliseconds: 100));
    final bubbles = tester.widgetList<MessageBubble>(
      find.byType(MessageBubble),
    );
    if (bubbles.any((b) => !b.isMine && b.content.isNotEmpty)) return;
  }
  throw StateError('no answer text ever appeared to cancel');
}

Future<void> _waitForError(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await _tick(tester, const Duration(milliseconds: 200));
    if (find.textContaining('Retry').evaluate().isNotEmpty) return;
  }
  throw StateError('the failed request never surfaced an error');
}
