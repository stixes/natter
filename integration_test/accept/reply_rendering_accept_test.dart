// Acceptance suite - reply-rendering capability (render-markdown-replies).
//
// Scenario map (openspec/changes/render-markdown-replies/specs/):
//   - Assistant replies render as markdown .. a scripted reply carrying a
//     heading, bold, inline code, and a fenced block arrives formatted, with
//     the markup characters gone from what is drawn
//   - User turns stay verbatim .............. the same markup, sent by the
//     user, is drawn literally
//   - Live rendering during a stream ........ a multi-chunk reply that opens a
//     code fence keeps what has arrived on screen mid-stream, and the
//     committed reply renders as formatted blocks
//   - Reopening a chat renders the same way ... the same reply re-read from
//     storage renders as structure, with its markup still absent
//
// Hermetic: the app talks only to harness.dart's scripted endpoint on the
// device's loopback interface. This file configures its own endpoint, because
// each acceptance file is its own binary and therefore its own port.
//
// The rendered assertions read what is drawn, not what is stored:
// `assistantBubbleTexts` keeps reading `MessageBubble.content`, which is the
// raw markdown, and each scenario asserts both sides so storage stays whole
// while the screen shows structure.

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
    'reply-rendering / Assistant replies render as markdown',
    (tester) async {
      await launchApp(tester);
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      scriptNormalStream(endpoint, chunks: [
        '# Acceptance heading\n\n',
        'Some **bold** and `inline code`.\n\n',
        '```text\nfenced( \'code\' );\n```\n',
      ]);
      await awaitExchange(tester, endpoint, '$stamp markdown reply probe');

      // Structure is drawn.
      expect(renderedTextContains(tester, 'Acceptance heading'), isTrue,
          reason: 'the heading text must reach the screen');
      expect(renderedTextContains(tester, 'Some bold'), isTrue,
          reason: 'emphasis must be drawn, not written out');
      expect(renderedTextContains(tester, 'inline code'), isTrue);
      expect(renderedTextContains(tester, "fenced( 'code' );"), isTrue,
          reason: 'a fenced block must reach the screen as text');

      // Markup characters are what the parser consumes; their absence is what
      // "rendered" means.
      for (final markup in [
        '# Acceptance heading',
        '**bold**',
        '`inline code`',
        '```',
      ]) {
        expect(renderedTextContains(tester, markup), isFalse,
            reason: '"$markup" is markdown syntax, not reply text');
      }

      // Rendering is display-only: the stored reply is still whole markdown,
      // so exports and the next request keep every character the model sent.
      expect(hasAssistantBubbleWith(tester, '# Acceptance heading'), isTrue,
          reason: 'the stored turn must keep its raw markdown');
      expect(hasAssistantBubbleWith(tester, '**bold**'), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'reply-rendering / User turns stay verbatim',
    (tester) async {
      await launchApp(tester);
      final typed =
          '$stamp verbatim probe: **keep** `this` and #literal';
      scriptNormalStream(endpoint, chunks: ['Noted.']);
      await sendMessage(tester, typed);
      await waitForNoStream(tester);

      // The user's own markup is drawn as typed, even though the same
      // characters are invisible in an assistant bubble.
      expect(renderedTextContains(tester, '**keep** `this` and #literal'),
          isTrue,
          reason: 'a user turn must show exactly what was typed');
      expect(
        assistantBubbleTexts(tester).any((content) => content == 'Noted.'),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'reply-rendering / Live rendering during a stream',
    (tester) async {
      await launchApp(tester);
      scriptAnswerThenHang(endpoint, chunks: [
        '## Live\n\n',
        '```text\nhalf-written(',
      ]);
      await sendMessage(tester, '$stamp live rendering probe');
      await waitForText(tester, 'half-written(', endpoint: endpoint);

      // Mid-stream: an unterminated fence must not hide the reply that has
      // arrived, and the visible text is already being drawn as structure.
      expect(renderedTextContains(tester, 'half-written('), isTrue,
          reason: 'text received so far must stay visible mid-stream');
      expect(renderedTextContains(tester, '## Live'), isFalse,
          reason: 'a live reply is rendered, not shown as markup');
      expect(renderedTextContains(tester, '```'), isFalse,
          reason: 'an open fence is not drawn as characters');

      // Stop: the partial reply commits, and it renders as formatted blocks.
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await waitForNoStream(tester);
      expect(renderedTextContains(tester, 'Live'), isTrue);
      expect(renderedTextContains(tester, '## Live'), isFalse);
      expect(renderedTextContains(tester, '```'), isFalse);
      expect(hasAssistantBubbleWith(tester, '```text\nhalf-written('), isTrue,
          reason: 'the committed partial must keep its raw markdown');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'reply-rendering / Reopening a chat renders the same way',
    (tester) async {
      await launchApp(tester);
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      // A launch restores the last conversation, so the exchange has to open
      // its own chat for the round trip below to have something to reopen.
      await startNewChat(tester);
      scriptNormalStream(endpoint, chunks: [
        '# Reopened heading\n\n',
        'Still **bold** after the round trip.\n\n',
        '| a | b |\n| --- | --- |\n| 1 | 2 |\n',
      ]);
      await awaitExchange(tester, endpoint, '$stamp reopen probe');
      expect(renderedTextContains(tester, '# Reopened heading'), isFalse,
          reason: 'the fresh reply must render before the round trip is judged');

      // Leave and come back: the turn is re-read from storage, and rendering
      // is a property of the bubble, not of the stream that produced it.
      await startNewChat(tester);
      await openDrawer(tester);
      await waitForDrawerTile(tester, '$stamp reopen probe');
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('$stamp reopen probe'),
        ),
      );
      await settle(tester);

      expect(renderedTextContains(tester, 'Reopened heading'), isTrue,
          reason: 'a reopened reply still shows its heading text');
      expect(renderedTextContains(tester, 'Still bold after the round trip'),
          isTrue);
      for (final markup in ['# Reopened heading', '**bold**', '| a | b |']) {
        expect(renderedTextContains(tester, markup), isFalse,
            reason: '"$markup" is markdown syntax, not reply text');
      }
      expect(hasAssistantBubbleWith(tester, '# Reopened heading'), isTrue,
          reason: 'the stored turn keeps its raw markdown across the round trip');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
