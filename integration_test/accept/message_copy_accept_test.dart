// Acceptance suite - message-copy capability (message-copy-actions).
//
// Scenario map (openspec/changes/message-copy-actions/specs/message-copy/):
//   - A rendered reply copies its source ....... the markdown source lands on
//     the clipboard, with the markup characters the screen consumed, and no
//     surface had to be dismissed
//   - An in-flight reply offers nothing ........ a draft carries no control,
//     and the partial answer committed on cancel carries one
//   - A user turn copies verbatim ............... markup characters and a line
//     break land exactly as typed
//   - Copy one block from a mixed reply ......... the tapped block's own text
//     lands alone, with indentation and line breaks (covers "The block's text
//     is copied intact")
//   - History and the next request are unchanged ... a copy makes no request,
//     the follow-up body still carries the copied turn whole, and a reopen
//     reads the same raw markdown back
//
// Deliberately not here:
//   - "Screen readers hear the result" and the largest-font-scale / both-themes
//     bar. Those belong to the accessibility pass and the semantics assertions
//     in test/message_bubble_test.dart; the suite has no way to drive TalkBack.
//   - "Selection stays as the partial path", pinned at unit level
//     (message_bubble_test's selectable-block case) rather than by a selection
//     gesture this harness can't keep honest on-device.
//
// Hermetic: the app talks only to harness.dart's scripted endpoint on the
// device's loopback interface. The clipboard is read back through the real
// platform channel, so a scenario confirms what landed rather than what the app
// meant to write.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  late ScriptedEndpoint endpoint;

  setUpAll(() async => endpoint = await ScriptedEndpoint.start());
  tearDownAll(() => endpoint.close());

  testWidgets(
    'message-copy / A rendered reply copies its markdown source',
    (tester) async {
      await launchApp(tester);
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      scriptNormalStream(endpoint, chunks: [
        '# Copy probe heading\n\n',
        'Some **bold** and `inline code`.\n\n',
        '```text\nfenced( \'code\' );\n```\n',
      ]);
      await awaitExchange(tester, endpoint, '$stamp copy source probe');

      // One control for the user turn, one for the committed reply.
      expect(copyControls(), findsNWidgets(2),
          reason: 'a committed turn of either role carries a control');

      final copied = await tapCopy(tester, copyControls().last);

      // The screen consumed the markup; the clipboard kept it, so a paste into
      // a markdown editor round-trips what the endpoint produced.
      expect(copied, contains('# Copy probe heading'),
          reason: 'the clipboard must hold the markdown source');
      expect(copied, contains('**bold**'));
      expect(copied, contains('`inline code`'));
      expect(copied, contains("fenced( 'code' );"));

      // The screen still draws structure, and nothing had to be dismissed.
      expect(renderedTextContains(tester, '# Copy probe heading'), isFalse,
          reason: 'copying must not change what the reply draws as');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      // The tapped control showed the copy happened, in place.
      expect(copyConfirmations(), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'message-copy / An in-flight reply offers nothing, a cancelled partial offers one',
    (tester) async {
      await launchApp(tester);
      // Each scenario opens its own chat: the app restores the last
      // conversation on launch, and the control counts below only mean
      // something against a transcript this scenario owns.
      await startNewChat(tester);
      scriptAnswerThenHang(endpoint, chunks: ['```python\ndef half_written(']);
      await sendMessage(tester, '$stamp in-flight probe');
      await waitForText(tester, 'half_written(', endpoint: endpoint);

      // Text has arrived, the reply is not committed: the user's own turn has
      // a control, the draft has none - and the partial block must not show a
      // button that would take half a block.
      expect(copyControls(), findsNWidgets(1),
          reason: 'only the committed user turn has something to copy');
      expect(codeBlockCopyButtons(), findsNothing);
      expect(renderedTextContains(tester, 'half_written('), isTrue);

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await waitForNoStream(tester);

      // The partial answer is a committed turn now: control, and its block.
      expect(copyControls(), findsNWidgets(2));
      expect(codeBlockCopyButtons(), findsOneWidget);

      final copied = await tapCopy(tester, copyControls().last);
      expect(copied, '```python\ndef half_written(',
          reason: 'a committed partial copies its own raw markdown');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'message-copy / A user turn copies verbatim',
    (tester) async {
      await launchApp(tester);
      await startNewChat(tester);
      final typed =
          '$stamp verbatim copy: **keep** `this`\nand a second line';
      scriptNormalStream(endpoint, chunks: ['Noted.']);
      await sendMessage(tester, typed);
      await waitForNoStream(tester);

      final copied = await tapCopy(tester, copyControls().first);
      expect(copied, typed,
          reason: 'a user turn must land exactly what was typed');
      expect(renderedTextContains(tester, '**keep** `this`\nand a second line'),
          isTrue, reason: 'and a user turn still draws its own markup');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'message-copy / A code block copies on its own, indentation intact',
    (tester) async {
      await launchApp(tester);
      await startNewChat(tester);
      scriptNormalStream(endpoint, chunks: [
        'Prose before.\n\n',
        '```python\nfirst_block():\n    return 1\n```\n\n',
        'Prose between.\n\n',
        '```python\nsecond_block():\n    return 2\n```\n',
      ]);
      await awaitExchange(tester, endpoint, '$stamp block copy probe');

      expect(codeBlockCopyButtons(), findsNWidgets(2),
          reason: 'each rendered block carries a button of its own');

      final copied = await tapCopy(tester, codeBlockCopyButtons().first);

      // Only the tapped block, with its indentation and line break, and no
      // trailing blank line: what a paste into an editor should produce.
      expect(copied, 'first_block():\n    return 1');
      expect(copied, isNot(contains('second_block')));
      expect(copied, isNot(contains('Prose')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'message-copy / A copy leaves the conversation untouched',
    (tester) async {
      await launchApp(tester);
      await startNewChat(tester);
      scriptNormalStream(endpoint, chunks: ['# Untouched heading\n\nBody.\n']);
      await awaitExchange(tester, endpoint, '$stamp untouched probe');

      final baseline = endpoint.requestCount;
      await tapCopy(tester, copyControls().last);
      expect(endpoint.requestCount, baseline,
          reason: 'a copy makes no request of any kind');

      // A follow-up still carries the copied turn whole, markup and all.
      scriptNormalStream(endpoint, chunks: ['Follow-up answer.']);
      await awaitExchange(tester, endpoint, '$stamp follow-up probe');
      final body = jsonEncode(endpoint.lastRequestBody);
      expect(body, contains('# Untouched heading'),
          reason: 'the next request must hold the stored turn exactly');

      // Reopening from history reads back the same raw markdown, which is what
      // the copy control copies.
      await startNewChat(tester);
      await openDrawer(tester);
      await waitForDrawerTile(tester, '$stamp untouched probe');
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('$stamp untouched probe'),
        ),
      );
      await settle(tester);
      expect(hasAssistantBubbleWith(tester, '# Untouched heading'), isTrue,
          reason: 'a reopened conversation keeps the turn it had before the copy');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
