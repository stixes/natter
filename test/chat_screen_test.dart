import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/stream_delta.dart';
import 'package:natter/state/chat_providers.dart';
import 'package:natter/ui/chat_screen.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/ui/message_bubble.dart';

import 'support/test_support.dart';

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: ChatScreen()),
);

Future<void> _sendMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.tap(find.byIcon(Icons.arrow_upward));
  await tester.pump();
}

void main() {
  testWidgets('user and assistant turns render, and the answer grows as '
      'tokens arrive', (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'hi there');
    await tester.pump();

    expect(find.text('hi there'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsOneWidget);

    t.service.emit(0, const [StreamDelta(content: 'Hel')]);
    await tester.pump();
    expect(find.text('Hel'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsNothing);

    t.service.emit(0, const [StreamDelta(content: 'lo world')]);
    await tester.pump();
    expect(find.text('Hello world'), findsOneWidget);

    t.service.end(0);
    await tester.pump();
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.byType(AnimatedPlaceholder), findsNothing);
  });

  testWidgets('markdown arrives as literal plain text', (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'show me');
    t.service.emit(0, const [
      StreamDelta(content: '# Title\n**bold** and `code`'),
    ]);
    t.service.end(0);
    await tester.pump();

    // Plain text: the markdown syntax reaches the screen literally.
    expect(find.text('# Title\n**bold** and `code`'), findsOneWidget);
  });

  testWidgets('reasoning switches Waiting to Thinking and is never rendered',
      (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'hi');
    expect(find.textContaining('Waiting'), findsOneWidget);

    t.service.emit(0, const [
      StreamDelta(hasRole: true),
      StreamDelta(reasoning: 'secret reasoning text'),
    ]);
    await tester.pump();

    expect(find.textContaining('Thinking'), findsOneWidget);
    expect(find.textContaining('secret reasoning'), findsNothing);

    t.service.emit(0, const [StreamDelta(content: 'public answer')]);
    await tester.pump();
    expect(find.text('public answer'), findsOneWidget);
    expect(find.textContaining('secret reasoning'), findsNothing);
  });

  testWidgets('the placeholder dots animate on a timer while no tokens arrive',
      (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'hi');
    await tester.pump();

    expect(find.text('Waiting.'), findsOneWidget);
    // No tokens arrive at all; the animation is driven by its own timer.
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Waiting..'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Waiting...'), findsOneWidget);
  });

  testWidgets('cancel stops the stream, keeps partial output, and halts the '
      'placeholder timer', (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'hi');
    t.service.emit(0, const [StreamDelta(content: 'par')]);
    await tester.pump();
    expect(find.text('par'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();

    expect(find.text('par'), findsOneWidget);
    expect(find.byType(AnimatedPlaceholder), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    // A leaked periodic timer would make the pending-timer check at teardown
    // fail; pumping well past the frame rate proves it is gone.
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mid-stream error is surfaced with retry and keeps earlier '
      'messages', (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'first');
    t.service.emit(0, const [StreamDelta(content: 'reply one')]);
    t.service.end(0);
    await tester.pump();

    await _sendMessage(tester, 'second');
    t.service.emit(1, const [StreamDelta(content: 'partial')]);
    t.service.fail(1, const ChatRequestFailure('upstream died'));
    await tester.pump();

    expect(find.textContaining('upstream died'), findsOneWidget);
    expect(find.text('reply one'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.byType(AnimatedPlaceholder), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(t.service.requests, hasLength(3));
    expect(
      t.service.requests.last.messages.map((m) => m.content).toList(),
      ['first', 'reply one', 'second'],
    );
  });

  testWidgets('blank answer with reasoning renders the reasoning as the answer',
      (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'hi');
    t.service.emit(0, const [
      StreamDelta(reasoning: 'the entire answer was reasoning'),
    ]);
    t.service.end(0);
    await tester.pump();

    expect(find.text('the entire answer was reasoning'), findsOneWidget);
    expect(find.textContaining('empty reply'), findsNothing);
  });

  testWidgets('endpoint config round-trips through the settings screen',
      (tester) async {
    final t = createTestContainer();
    await tester.pumpWidget(_app(t.container));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://192.0.2.10:8080/v1');
    await tester.enterText(fields.at(1), 'sk-super-secret');
    await tester.enterText(fields.at(2), 'qwen3-14b');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Back on the chat screen the profile is live and the key is not echoed.
    expect(t.container.read(profileProvider), const EndpointProfile(
      baseUrl: 'http://192.0.2.10:8080/v1',
      apiKey: 'sk-super-secret',
      model: 'qwen3-14b',
    ));
    expect(find.text('sk-super-secret'), findsNothing);

    // Reopening the screen shows the stored values again.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final reopened = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(reopened, [
      'http://192.0.2.10:8080/v1',
      'sk-super-secret',
      'qwen3-14b',
    ]);
  });

  testWidgets('the key reaches secure storage only, never plain settings',
      (tester) async {
    final t = createTestContainer();
    await tester.pumpWidget(_app(t.container));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://openrouter.ai/api/v1');
    await tester.enterText(fields.at(1), 'sk-plain-text-never-store-me');
    await tester.enterText(fields.at(2), 'some-model');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final plain = await t.settings.contents();
    final secure = await t.secrets.contents();

    expect(plain['endpoint.baseUrl'], 'https://openrouter.ai/api/v1');
    expect(plain['endpoint.model'], 'some-model');
    expect(secure['endpoint.apiKey'], 'sk-plain-text-never-store-me');
    expect(
      plain.values.any((value) => value.contains('sk-plain-text-never-store-me')),
      isFalse,
      reason: 'the key must not appear in any plain settings value',
    );
    expect(
      plain.keys.any((key) => key.toLowerCase().contains('key')),
      isFalse,
      reason: 'no key-shaped field may live in plain settings',
    );
  });

  testWidgets('the send button is disabled until an endpoint is configured',
      (tester) async {
    final t = createTestContainer();
    await tester.pumpWidget(_app(t.container));

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('No endpoint configured. Open Settings to set a base URL '
          'and model.'),
      findsOneWidget,
    );
  });

  testWidgets('a base URL and model with no key is enough to send',
      (tester) async {
    // The proposal's own use case is a live llama.cpp server, which needs no
    // key at all: demanding one would lock local endpoints out of the app.
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(const EndpointProfile(
          baseUrl: 'http://192.0.2.10:8080/v1',
          model: 'qwen3-14b',
        ));
    await tester.pumpWidget(_app(t.container));

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNotNull,
        reason: 'Send must work for an endpoint that needs no key');
    expect(find.textContaining('No endpoint configured'), findsNothing);

    await _sendMessage(tester, 'hi');
    expect(t.service.requests, hasLength(1),
        reason: 'and the request must go out');
    expect(t.service.requests.single.profile.apiKey, '',
        reason: 'an empty key must stay empty rather than be invented');
  });
}
