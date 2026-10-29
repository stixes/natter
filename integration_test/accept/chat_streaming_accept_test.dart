// Acceptance suite - chat-streaming capability (add-acceptance-suite).
//
// Scenario map (openspec/specs/chat-streaming/spec.md):
//   - Endpoint configuration .......... first launch is unconfigured
//   - Streaming reply delivery ........ configure, send, stream, commit
//                                        (and the request shape: one system
//                                        message ahead of the turns)
//   - Cancellation ..................... stop mid-stream keeps partial;
//                                        stop during thinking commits nothing
//   - Request failures ............... unreachable endpoint surfaces Retry,
//                                        and a retry after fixing config works
//   - Reasoning capture .............. reasoning-only reply lands the
//                                      blank-answer fallback
//
// Hermetic: the app talks only to harness.dart's scripted endpoint on the
// device's loopback interface. First-launch state is forced from inside the
// test (settings + keystore wipe), so this file needs no `pm clear`.

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
    'chat-streaming / Endpoint configuration: first launch is unconfigured',
    (tester) async {
      await clearStoredConfig();
      await launchApp(tester);

      expect(find.textContaining('No endpoint configured'), findsOneWidget,
          reason: 'an unconfigured launch must tell the user what is missing');
      final send = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_upward),
      );
      expect(send.onPressed, isNull,
          reason: 'Send must be inert until an endpoint is configured');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'chat-streaming / Streaming reply: configure, send, stream, commit',
    (tester) async {
      await launchApp(tester);
      scriptNormalStream(
        endpoint,
        chunks: ['Acceptance ', 'stream ', 'delivered'],
      );
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      await awaitExchange(tester, endpoint, '$stamp streaming probe');

      expect(hasAssistantBubbleWith(tester, 'Acceptance stream delivered'),
          isTrue,
          reason: 'the scripted reply must arrive piecewise and commit whole');
      expect(endpoint.lastRequestBody?['model'], 'accept-model',
          reason: 'the configured model must ride the wire');
      expect(endpoint.lastRequestBody?['stream'], true,
          reason: 'the app must ask for a streaming reply');

      // Request shape, now that a system prompt leads it (the widened
      // `Streaming reply delivery` scenario in adjustable-system-prompt).
      final messages = endpoint.lastRequestBody?['messages'] as List<Object?>;
      final roles = messages
          .map((m) => (m as Map<String, Object?>)['role'])
          .toList();
      expect(roles, ['system', 'user'],
          reason: 'one system message must lead the conversation turns');
      final prompt =
          (messages.first as Map<String, Object?>)['content'] as String;
      expect(prompt, isNotEmpty,
          reason: 'a fresh install sends the built-in default, not nothing');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'chat-streaming / Cancel mid-stream: partial answer stays',
    (tester) async {
      await launchApp(tester);
      scriptAnswerThenHang(endpoint, chunks: ['Half an answer ', 'arrived.']);
      await sendMessage(tester, '$stamp cancel mid-stream');
      await waitForText(tester, 'Half an answer', endpoint: endpoint);

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await settle(tester);

      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing,
          reason: 'stop must end the in-flight state');
      expect(hasAssistantBubbleWith(tester, 'Half an answer'), isTrue,
          reason: 'the text that already arrived must survive as a turn');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'chat-streaming / Cancel during thinking: nothing commits',
    (tester) async {
      await launchApp(tester);
      scriptReasoningThenHang(endpoint, chunks: ['Musing in secret.']);
      await sendMessage(tester, '$stamp cancel while thinking');
      await waitForText(tester, 'Thinking', endpoint: endpoint);

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await settle(tester);

      expect(find.textContaining('Thinking'), findsNothing,
          reason: 'the placeholder must leave when stopped');
      expect(hasAssistantBubbleWith(tester, 'Musing'), isFalse,
          reason: 'reasoning that never answered must not commit');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'chat-streaming / Failure and retry: unreachable endpoint, fix, retry',
    (tester) async {
      await launchApp(tester);
      scriptNormalStream(endpoint, chunks: ['Recovered reply.']);
      // Port 9 (discard) on loopback: connection refuses immediately.
      await configureEndpoint(
        tester,
        baseUrl: 'http://127.0.0.1:9/v1',
        model: 'accept-model',
      );
      await sendMessage(tester, '$stamp should fail first');
      await waitForRetry(tester);

      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await waitForNoStream(tester);

      expect(hasAssistantBubbleWith(tester, 'Recovered reply'), isTrue,
          reason: 'retry after a fixed config must succeed');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'chat-streaming / Reasoning-only reply: blank-answer fallback lands',
    (tester) async {
      await launchApp(tester);
      scriptReasoningOnly(
        endpoint,
        chunks: ['The whole answer ', 'landed in reasoning.'],
      );
      await awaitExchange(tester, endpoint, '$stamp reasoning only probe');

      expect(
          hasAssistantBubbleWith(tester, 'The whole answer landed in reasoning'),
          isTrue,
          reason: 'an answer-less reasoning stream must surface as the answer');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
