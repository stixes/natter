// Acceptance suite - conversation-history capability (add-acceptance-suite).
//
// Scenario map (openspec/specs/conversation-history/spec.md):
//   - Conversation list and switching .. two chats appear in the drawer,
//     opening one loads its stored turns, and relaunching the app restores
//     the most recent conversation from durable storage
//
// The relaunch re-runs app.main() in the same process: a fresh provider
// container and a fresh Drift connection reading the device's database file.
// That proves restore-from-storage; a true process kill stays a manual round
// recorded in validation.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:natter/main.dart' as app;

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  late ScriptedEndpoint endpoint;

  setUpAll(() async => endpoint = await ScriptedEndpoint.start());
  tearDownAll(() => endpoint.close());

  testWidgets(
    'conversation-history / List and switching: drawer, open, relaunch',
    (tester) async {
      await launchApp(tester);
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      await startNewChat(tester);

      scriptNormalStream(endpoint, chunks: ['Alpha reply.']);
      await awaitExchange(tester, endpoint, '$stamp alpha first');
      expect(hasAssistantBubbleWith(tester, 'Alpha reply'), isTrue,
          reason: 'the alpha chat must stream and commit its reply');

      await startNewChat(tester);
      scriptNormalStream(endpoint, chunks: ['Beta reply.']);
      await awaitExchange(tester, endpoint, '$stamp beta first');

      // Scope to the Drawer: the open conversation stays rendered behind it,
      // so an unscoped find.text also hits the on-screen user bubble. The
      // list itself loads from storage, so poll for each tile first.
      await openDrawer(tester);
      final drawer = find.byType(Drawer);
      await waitForDrawerTile(tester, '$stamp alpha first');
      expect(
        find.descendant(
          of: drawer,
          matching: find.text('$stamp alpha first'),
        ),
        findsOneWidget,
        reason: 'the drawer must list the earlier chat by its first turn',
      );
      await waitForDrawerTile(tester, '$stamp beta first');
      expect(
        find.descendant(
          of: drawer,
          matching: find.text('$stamp beta first'),
        ),
        findsOneWidget,
        reason: 'the drawer must list the current chat too',
      );

      await tester.tap(find.descendant(
        of: drawer,
        matching: find.text('$stamp alpha first'),
      ));
      await settle(tester);
      expect(hasAssistantBubbleWith(tester, 'Alpha reply'), isTrue,
          reason: 'opening a saved chat must load its stored turns');
      expect(hasAssistantBubbleWith(tester, 'Beta reply'), isFalse,
          reason: 'the opened conversation replaces what was on screen');

      // Relaunch: restoreMostRecent in main() must reopen the newest chat
      // (beta) from the database, not from memory.
      await app.main();
      await settle(tester);
      expect(hasAssistantBubbleWith(tester, 'Beta reply'), isTrue,
          reason: 'relaunch must restore the most recent conversation');
      expect(hasAssistantBubbleWith(tester, 'Alpha reply'), isFalse,
          reason: 'the restored screen must show only the newest chat');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
