import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natter/data/system_prompt_repository.dart';
import 'package:natter/domain/system_prompt.dart';
import 'package:natter/state/chat_providers.dart';
import 'package:natter/ui/settings_screen.dart';

import 'support/test_support.dart';

// Pumps here stay bounded once a field has focus: a focused text field keeps
// scheduling frames for its blinking cursor, so an unbounded settle after
// typing spins until it times out. Transitions are pumped by hand instead.
// Saving is the one step that needs real futures, so it runs under runAsync.

/// A stand-in for the chat screen, so settings is reached the way it is in
/// the app: pushed on top of a route that stays behind it.
class SettingsHost extends StatelessWidget {
  const SettingsHost({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
        child: const Text('Open settings'),
      ),
    ),
  );
}

/// Opens the settings screen over a test container, as the app does.
Future<void> pumpSettings(
  WidgetTester tester,
  ProviderContainer container, {
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: const SettingsHost(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openSettings(tester);
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Open settings'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Leaves the settings screen without saving, as the back affordance does.
Future<void> leaveSettings(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Closes and reopens the screen, so what it shows is what the container
/// holds rather than what was typed into the previous instance. Saving already
/// closes the screen, so this leaves only when the screen is still up.
Future<void> reopenSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  if (find.byType(SettingsScreen).evaluate().isNotEmpty) {
    await leaveSettings(tester);
  }
  await openSettings(tester);
}

Finder promptField() => find.widgetWithText(TextField, 'System prompt');

/// The editable inside the prompt field, for typing.
Finder promptEditable() => find.descendant(
  of: promptField(),
  matching: find.byType(EditableText),
);

Finder resetButton() => find.widgetWithText(TextButton, 'Reset to default');

Finder saveButton() => find.widgetWithText(FilledButton, 'Save');

/// The System prompt field's current text, as the widget holds it.
String promptFieldValue(WidgetTester tester) =>
    tester.widget<EditableText>(promptEditable()).controller.text;

bool resetIsEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(resetButton()).onPressed != null;

/// Jumps the settings list to its bottom, then taps Save.
///
/// The list builds its children lazily, so typing in the prompt field can
/// push Save out of the built range - a bare tap would then fail on an empty
/// finder rather than on the behaviour under test. The scroll offset is moved
/// directly because a gesture drag at the list's centre is swallowed by the
/// prompt field's own scrollable.
Future<void> tapSave(WidgetTester tester) async {
  await scrollSettingsToListBottom(tester);
  // The save reaches the durable store through real futures, which the fake
  // test clock does not advance; runAsync lets them finish before asserting.
  await tester.runAsync(() async {
    await tester.tap(saveButton());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> scrollSettingsToListBottom(WidgetTester tester) async {
  // Tree order puts the settings ListView's scrollable first: it is an
  // ancestor of every field, whose own scrollables come later.
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  if (position.pixels < position.maxScrollExtent) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
  }
}

void main() {
  group('system prompt setting states', () {
    testWidgets('a fresh install pre-fills the built-in default', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      expect(find.text('Settings'), findsOneWidget,
          reason: 'the screen is no longer only about the endpoint');
      expect(promptFieldValue(tester), kDefaultSystemPrompt);
      expect(resetIsEnabled(tester), isFalse,
          reason: 'there is nothing to reset while the default is showing');
    });

    testWidgets('an edited prompt is saved, shown, and in effect', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      await tester.enterText(promptEditable(), 'Answer in haiku, always.');
      await tapSave(tester);

      expect(
        t.container.read(systemPromptProvider).inEffect,
        'Answer in haiku, always.',
      );
      final stored = await t.settings.contents();
      expect(
        stored[SystemPromptRepository.promptField],
        'Answer in haiku, always.',
      );

      // Reopening shows what was saved, and Reset is available again.
      await reopenSettings(tester, t.container);
      expect(promptFieldValue(tester), 'Answer in haiku, always.');
      expect(resetIsEnabled(tester), isTrue);
    });

    testWidgets('a cleared prompt saves as empty and stays empty', (tester) async {
      final t = createTestContainer();
      await t.container
          .read(systemPromptProvider.notifier)
          .save('Answer in haiku, always.');
      await pumpSettings(tester, t.container);

      await tester.enterText(promptEditable(), '');
      await tapSave(tester);

      final setting = t.container.read(systemPromptProvider);
      expect(setting.state, SystemPromptState.clearedValue);
      expect(setting.inEffect, isEmpty,
          reason: 'a cleared prompt must not revert to the default');

      await reopenSettings(tester, t.container);
      expect(promptFieldValue(tester), isEmpty);
      expect(
        find.text('Sent before every chat. Leave empty to send none.'),
        findsOneWidget,
        reason: 'the helper explains the empty field',
      );
    });

    testWidgets('reset-then-save follows the built-in default again', (tester) async {
      final t = createTestContainer();
      await t.container
          .read(systemPromptProvider.notifier)
          .save('Answer in haiku, always.');
      await pumpSettings(tester, t.container);

      expect(resetIsEnabled(tester), isTrue);
      await tester.tap(resetButton());
      await tester.pump();

      expect(promptFieldValue(tester), kDefaultSystemPrompt,
          reason: 'reset replaces the field text without saving it');
      expect(t.container.read(systemPromptProvider).inEffect,
          'Answer in haiku, always.',
          reason: 'reset takes effect only when the user saves');
      expect(resetIsEnabled(tester), isFalse,
          reason: 'the field now holds the default, so reset is spent');

      await tapSave(tester);

      expect(t.container.read(systemPromptProvider).isDefault, isTrue);
      final stored = await t.settings.contents();
      expect(stored.containsKey(SystemPromptRepository.promptField), isFalse,
          reason: 'saving the default keeps following the shipped default');
    });

    testWidgets('leaving without saving changes nothing', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      await tester.enterText(promptEditable(), 'Typed but never saved.');
      await leaveSettings(tester);

      expect(
        t.container.read(systemPromptProvider).inEffect,
        kDefaultSystemPrompt,
      );
      final stored = await t.settings.contents();
      expect(stored.containsKey(SystemPromptRepository.promptField), isFalse);

      await pumpSettings(tester, t.container);
      expect(promptFieldValue(tester), kDefaultSystemPrompt);
    });

    testWidgets('saving the untouched default leaves the key absent', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      await tapSave(tester);

      final stored = await t.settings.contents();
      expect(stored.containsKey(SystemPromptRepository.promptField), isFalse);
      expect(t.container.read(systemPromptProvider).isDefault, isTrue);
    });

    testWidgets('the prompt never reaches the secure store', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      await tester.enterText(promptEditable(), 'A prompt that must stay local.');
      await tapSave(tester);

      final secrets = await t.secrets.contents();
      expect(
        secrets.values.any((v) => v.contains('A prompt that must stay local')),
        isFalse,
      );
      expect(secrets, isEmpty);
    });
  });

  group('system prompt field presentation', () {
    testWidgets('the field grows with text and stops at maxLines', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      // Start from one stored line: a short prompt must not arrive already
      // wearing the field's maximum height.
      await t.container.read(systemPromptProvider.notifier).save('one line');
      await reopenSettings(tester, t.container);
      final oneLine = tester.getSize(promptField()).height;

      await tester.enterText(promptEditable(), 'one\ntwo\nthree\nfour');
      await tester.pump();
      final fourLines = tester.getSize(promptField()).height;
      expect(fourLines, greaterThan(oneLine),
          reason: 'the field grows with the text it holds');
      // One extra line over the three-line minimum is one line tall.
      final perLine = fourLines - oneLine;

      await tester.enterText(
        promptEditable(),
        List.filled(40, 'line').join('\n'),
      );
      await tester.pump();
      final tall = tester.getSize(promptField()).height;
      // Eight lines is the cap: the three-line minimum plus five more.
      expect(tall, closeTo(oneLine + 5 * perLine, 0.5),
          reason: 'a long prompt grows to maxLines and then scrolls '
              'internally instead of stretching the screen');

      // Save stays reachable: scrolling to the bottom of the list reveals it.
      await scrollSettingsToListBottom(tester);
      expect(saveButton(), findsOneWidget);
    });

    testWidgets('the field does not clip at 2.0 text scale', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container, textScale: 2.0);

      expect(tester.takeException(), isNull,
          reason: 'large text must not overflow the field or the screen');
      expect(promptField(), findsOneWidget);
      expect(find.text('System prompt'), findsOneWidget);

      // Nothing clips horizontally at this scale, and everything the screen
      // offers stays reachable by scrolling.
      final viewPort = tester.getRect(find.byType(Scaffold));
      expect(
        tester.getRect(promptField()).right,
        lessThanOrEqualTo(viewPort.right),
      );
      await scrollSettingsToListBottom(tester);
      expect(saveButton(), findsOneWidget);
      expect(
        tester.getRect(saveButton()).right,
        lessThanOrEqualTo(viewPort.right),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the screen reader announces the Reset label', (tester) async {
      final t = createTestContainer();
      await t.container
          .read(systemPromptProvider.notifier)
          .save('Answer in haiku, always.');
      await pumpSettings(tester, t.container);

      final handle = tester.ensureSemantics();
      await tester.pump();

      expect(
        tester.getSemantics(resetButton()),
        containsSemantics(
          label: 'Reset to default',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
        reason: 'the announced label says what the action does',
      );

      handle.dispose();
    });

    testWidgets('a disabled Reset is announced as disabled', (tester) async {
      final t = createTestContainer();
      await pumpSettings(tester, t.container);

      final handle = tester.ensureSemantics();
      await tester.pump();

      expect(
        tester.getSemantics(resetButton()),
        containsSemantics(
          label: 'Reset to default',
          isEnabled: false,
          hasTapAction: false,
        ),
        reason: 'a screen reader is told the action is unavailable',
      );

      handle.dispose();
    });

    testWidgets('Reset carries a 48x48 dp target in focus order', (tester) async {
      final t = createTestContainer();
      await t.container
          .read(systemPromptProvider.notifier)
          .save('Answer in haiku, always.');
      await pumpSettings(tester, t.container);

      final size = tester.getSize(resetButton());
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      // Focus order follows the visual order: field, Reset, Save.
      final field = tester.getRect(promptField());
      final reset = tester.getRect(resetButton());
      final save = tester.getRect(saveButton());
      expect(reset.top, greaterThanOrEqualTo(field.bottom));
      expect(save.top, greaterThanOrEqualTo(reset.bottom));
    });
  });
}
