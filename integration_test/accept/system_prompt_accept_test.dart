// Acceptance suite - system-prompt capability (adjustable-system-prompt).
//
// Scenario map (openspec/changes/adjustable-system-prompt/specs/system-prompt/spec.md):
//   - Built-in default prompt ............ fresh install uses the default
//   - Editable prompt setting ............ an edited prompt takes effect
//   - Cleared prompt sends no system
//     message ............................ clearing the prompt
//   - Prompt stays out of the
//     conversation ....................... transcript shows only the exchange
//
// Durability across a restart and the reset action's screen-reader label are
// confirmed by unit tests instead: the suite launches the app in-process and
// cannot kill and relaunch it, and it has no screen reader on the device.
//
// This file runs last in the suite (alphabetical) and ends by resetting the
// prompt to the built-in default, so later additions inherit a default install.
//
// Hermetic: the app talks only to harness.dart's scripted endpoint on the
// device's loopback interface.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:natter/domain/system_prompt.dart';
import 'package:natter/ui/message_bubble.dart';

import 'harness.dart';

/// A prompt the endpoint never repeats, so its absence from the screen means
/// something.
final markerPrompt = 'Acceptance marker plumtree: answer in one word.';

/// The roles of the messages the endpoint last received, in order.
List<String> wireRoles(ScriptedEndpoint endpoint) => [
  for (final message
      in endpoint.lastRequestBody?['messages'] as List<Object?>? ??
          const <Object?>[])
    (message as Map<String, Object?>)['role'] as String,
];

/// The content of the single system message the endpoint last received, or
/// null when it sent none.
String? wireSystemContent(ScriptedEndpoint endpoint) {
  final system =
      (endpoint.lastRequestBody?['messages'] as List<Object?>? ??
              const <Object?>[])
          .where(
            (message) => (message as Map<String, Object?>)['role'] == 'system',
          )
          .toList();
  if (system.isEmpty) return null;
  expect(
    system,
    hasLength(1),
    reason: 'a request carries at most one system message',
  );
  return (system.single as Map<String, Object?>)['content'] as String;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  late ScriptedEndpoint endpoint;

  setUpAll(() async => endpoint = await ScriptedEndpoint.start());
  tearDownAll(() => endpoint.close());

  testWidgets(
    'system-prompt / Built-in default prompt: a fresh install sends the default',
    (tester) async {
      await clearStoredConfig();
      await launchApp(tester);
      scriptNormalStream(endpoint, chunks: ['Default prompt probe reply.']);
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );

      // What the field shows on a fresh install is confirmed by the widget
      // tests; this scenario keeps to what rides the wire, to stay inside the
      // suite's five-minute budget.

      await awaitExchange(tester, endpoint, '$stamp default prompt probe');

      expect(
        wireRoles(endpoint).first,
        'system',
        reason: 'the prompt must come before the conversation turns',
      );
      expect(
        wireSystemContent(endpoint),
        kDefaultSystemPrompt,
        reason: 'a fresh install sends the built-in default text',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'system-prompt / Editable prompt setting: an edited prompt takes effect',
    (tester) async {
      await launchApp(tester);
      await setPromptField(tester, markerPrompt);

      scriptNormalStream(endpoint, chunks: ['Edited prompt reply.']);
      await awaitExchange(tester, endpoint, '$stamp edited prompt probe');

      expect(
        wireRoles(endpoint).first,
        'system',
        reason: 'the edited prompt still leads the turns',
      );
      expect(
        wireSystemContent(endpoint),
        markerPrompt,
        reason: 'the saved text, not the default, must ride the wire',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'system-prompt / Cleared prompt sends no system message: clearing the prompt',
    (tester) async {
      await launchApp(tester);
      await setPromptField(tester, '');

      // That the field stays empty on reopen is a widget-test claim;
      // this one is about the request.

      scriptNormalStream(endpoint, chunks: ['No system prompt reply.']);
      await awaitExchange(tester, endpoint, '$stamp cleared prompt probe');

      expect(
        wireSystemContent(endpoint),
        isNull,
        reason: 'a cleared prompt must send no system message at all',
      );
      expect(
        wireRoles(endpoint),
        isNot(contains('system')),
        reason: 'the request carries only the conversation turns',
      );
      expect(
        wireRoles(endpoint).last,
        'user',
        reason: 'the turn just sent is still on the wire',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'system-prompt / Prompt stays out of the conversation: transcript shows '
    'only the exchange',
    (tester) async {
      await launchApp(tester);
      await setPromptField(tester, markerPrompt);
      await startNewChat(tester);

      scriptNormalStream(endpoint, chunks: ['The visible reply.']);
      await awaitExchange(tester, endpoint, '$stamp out-of-transcript probe');

      expect(
        hasAssistantBubbleWith(tester, 'The visible reply'),
        isTrue,
        reason: 'the reply itself must still render',
      );
      expect(
        renderedTextContains(tester, 'plumtree'),
        isFalse,
        reason: 'the prompt must not appear anywhere on screen',
      );
      expect(
        find.byType(MessageBubble),
        findsNWidgets(2),
        reason: 'one user turn and one reply, with no bubble for the prompt',
      );

      // Leave a default install for anything that runs after this file.
      await setPromptField(tester, kDefaultSystemPrompt);
      await openSettings(tester);
      expect(
        promptFieldText(tester),
        kDefaultSystemPrompt,
        reason: 'resetting the setting leaves the suite on the default',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
