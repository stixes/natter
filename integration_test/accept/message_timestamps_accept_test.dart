// Acceptance suite - message-timestamps capability (add-acceptance-suite).
//
// Scenario map (openspec/specs/message-timestamps/spec.md):
//   - Timestamp display .. committed turns carry an HH:MM label; the
//     in-flight draft carries none
//
// The scripted reply streams slowly enough that the "no label while
// streaming" check lands between the user commit and the reply commit.

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
    'message-timestamps / Display: committed labelled, in-flight not',
    (tester) async {
      await launchApp(tester);
      await configureEndpoint(
        tester,
        baseUrl: endpoint.baseUrl,
        model: 'accept-model',
      );
      await startNewChat(tester);

      scriptNormalStream(
        endpoint,
        chunks: ['One. ', 'Two. ', 'Three.'],
        chunkGap: const Duration(milliseconds: 600),
      );
      await sendMessage(tester, '$stamp timestamp probe');

      // The user turn commits immediately; the reply is still streaming.
      await tick(tester, const Duration(milliseconds: 300));
      expect(timestampLabels(tester), hasLength(1),
          reason: 'the committed user turn must carry a time label');

      await waitForNoStream(tester);
      expect(timestampLabels(tester), hasLength(2),
          reason: 'the committed reply must add a second time label');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
