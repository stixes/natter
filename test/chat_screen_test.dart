import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natter/domain/chat_message.dart';
import 'package:natter/domain/conversation_summary.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/system_prompt.dart';
import 'package:natter/domain/stream_delta.dart';
import 'package:natter/state/chat_providers.dart';
import 'package:natter/ui/chat_screen.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/ui/message_bubble.dart';
import 'package:natter/ui/natter_mark.dart';
import 'package:natter/ui/settings_screen.dart';

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

/// Scrolls the settings list to its bottom and taps Save.
///
/// The list builds its children lazily: with the system prompt field in it,
/// Save can sit outside the built range, so a bare tap would fail on an empty
/// finder. The offset is moved directly because a gesture drag at the list's
/// centre is swallowed by whichever text field sits there.
Future<void> _saveSettings(WidgetTester tester) async {
  final position = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
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
    // The live render is coalesced: text that arrives inside a render window
    // shows when that window closes, so growth is observed a tick later.
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Hello world'), findsOneWidget);

    t.service.end(0);
    await tester.pump();
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.byType(AnimatedPlaceholder), findsNothing);
  });

  testWidgets('a streamed reply renders as markdown, not markup', (
    tester,
  ) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'show me');
    t.service.emit(0, const [
      StreamDelta(content: '# Title\n**bold** and `code`'),
    ]);
    t.service.end(0);
    await tester.pump();

    // The reply bubble renders: markup characters are consumed by the parser.
    final shown = renderedBlocks(tester, find.byType(MessageBubble)).join('\n');
    expect(shown, contains('Title'));
    expect(shown, contains('bold'));
    expect(shown, contains('code'));
    expect(shown, isNot(contains('#')));
    expect(shown, isNot(contains('**')));
    expect(shown, isNot(contains('`')));
  });

  testWidgets('a streamed heading is a heading mid-stream, and not markup', (
    tester,
  ) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'plan');
    t.service.emit(0, const [StreamDelta(content: '# Plan\n\n- first')]);
    // Leading edge: the first token renders at once, markup and all.
    await tester.pump();
    final spans = renderedSpans(tester, find.byType(MessageBubble));
    final joined = renderedBlocks(
      tester,
      find.byType(MessageBubble),
    ).join('\n');
    expect(joined, contains('Plan'));
    expect(joined, isNot(contains('#')));
    final heading = spans.firstWhere((s) => s.text == 'Plan');
    final item = spans.firstWhere((s) => s.text == 'first');
    expect(
      heading.style!.fontSize!,
      greaterThan(item.style!.fontSize!),
      reason: 'a streamed heading must read as a heading',
    );
  });

  testWidgets('tokens inside a render window show when it closes, unchanged', (
    tester,
  ) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'plan');
    t.service.emit(0, const [StreamDelta(content: '# Plan\n\n- first')]);
    await tester.pump();

    t.service.emit(0, const [StreamDelta(content: '\n- second')]);
    await tester.pump();
    // Coalesced: still inside the window, so the text is not re-rendered yet.
    expect(
      renderedBlocks(tester, find.byType(MessageBubble)).join('\n'),
      isNot(contains('second')),
    );

    await tester.pump(const Duration(milliseconds: 120));
    final shown = renderedBlocks(tester, find.byType(MessageBubble)).join('\n');
    expect(shown, contains('first'));
    expect(shown, contains('second'));
    expect(shown, isNot(contains('- first')));

    t.service.end(0);
    await tester.pump();
    final committed = renderedBlocks(
      tester,
      find.byType(MessageBubble),
    ).join('\n');
    expect(committed, contains('Plan'));
    expect(committed, contains('first'));
    expect(committed, contains('second'));
  });

  testWidgets('an open code fence mid-stream keeps its text visible', (
    tester,
  ) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'show code');
    t.service.emit(0, const [
      StreamDelta(content: 'Here:\n\n```python\nprint("half'),
    ]);
    await tester.pump();
    var shown = renderedBlocks(tester, find.byType(MessageBubble)).join('\n');
    expect(shown, contains('print("half'));
    expect(shown, isNot(contains('```')));

    t.service.emit(0, const [StreamDelta(content: '1")\n```')]);
    await tester.pump(const Duration(milliseconds: 120));
    shown = renderedBlocks(tester, find.byType(MessageBubble)).join('\n');
    expect(shown, contains('print("half1")'));
    expect(shown, isNot(contains('`')));
    expect(shown, isNot(contains('python')));

    t.service.end(0);
    await tester.pump();
    expect(
      renderedBlocks(tester, find.byType(MessageBubble)).join('\n'),
      contains('print("half1")'),
    );
  });

  testWidgets('reasoning switches Waiting to Thinking and is never rendered', (
    tester,
  ) async {
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

  testWidgets(
    'the placeholder dots animate on a timer while no tokens arrive',
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
    },
  );

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
    expect(t.service.requests.last.messages.map((m) => m.content).toList(), [
      'first',
      'reply one',
      'second',
    ]);
  });

  testWidgets('a timed-out request replaces Waiting with the error banner and '
      'Retry re-sends the conversation', (tester) async {
    final t = createTestContainer();
    await t.container.read(profileProvider.notifier).save(testProfile);
    await tester.pumpWidget(_app(t.container));

    await _sendMessage(tester, 'hi');
    expect(find.textContaining('Waiting'), findsOneWidget);

    t.service.fail(
      0,
      const ChatRequestFailure('The endpoint did not respond.'),
    );
    await tester.pump();

    expect(find.textContaining('Waiting'), findsNothing);
    expect(find.text('The endpoint did not respond.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(t.service.requests, hasLength(2));
    expect(t.service.requests.last.messages.map((m) => m.content).toList(), [
      'hi',
    ]);
    expect(find.textContaining('Waiting'), findsOneWidget);
  });

  testWidgets(
    'blank answer with reasoning renders the reasoning as the answer',
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
    },
  );

  testWidgets('endpoint config round-trips through the settings screen', (
    tester,
  ) async {
    final t = createTestContainer();
    await tester.pumpWidget(_app(t.container));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(
      find.byType(TextField),
      findsNWidgets(4),
      reason: 'settings exposes base URL, API key, model, and the system '
          'prompt - and nothing else',
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://192.0.2.10:8080/v1');
    await tester.enterText(fields.at(1), 'sk-super-secret');
    await tester.enterText(fields.at(2), 'qwen3-14b');
    await _saveSettings(tester);

    // Back on the chat screen the profile is live and the key is not echoed.
    expect(
      t.container.read(profileProvider),
      const EndpointProfile(
        baseUrl: 'http://192.0.2.10:8080/v1',
        apiKey: 'sk-super-secret',
        model: 'qwen3-14b',
      ),
    );
    expect(find.text('sk-super-secret'), findsNothing);

    // Reopening the screen shows the stored values again.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final reopened =
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller!.text)
            .toList();
    expect(reopened, [
      'http://192.0.2.10:8080/v1',
      'sk-super-secret',
      'qwen3-14b',
      kDefaultSystemPrompt,
    ]);
  });

  testWidgets('the key reaches secure storage only, never plain settings', (
    tester,
  ) async {
    final t = createTestContainer();
    await tester.pumpWidget(_app(t.container));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://openrouter.ai/api/v1');
    await tester.enterText(fields.at(1), 'sk-plain-text-never-store-me');
    await tester.enterText(fields.at(2), 'some-model');
    await _saveSettings(tester);

    final plain = await t.settings.contents();
    final secure = await t.secrets.contents();

    expect(plain['endpoint.baseUrl'], 'https://openrouter.ai/api/v1');
    expect(plain['endpoint.model'], 'some-model');
    expect(secure['endpoint.apiKey'], 'sk-plain-text-never-store-me');
    expect(
      plain.values.any(
        (value) => value.contains('sk-plain-text-never-store-me'),
      ),
      isFalse,
      reason: 'the key must not appear in any plain settings value',
    );
    expect(
      plain.keys.any((key) => key.toLowerCase().contains('key')),
      isFalse,
      reason: 'no key-shaped field may live in plain settings',
    );
  });

  testWidgets('the send button is disabled until an endpoint is configured', (
    tester,
  ) async {
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
      find.text(
        'No endpoint configured. Open Settings to set a base URL '
        'and model.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a base URL and model with no key is enough to send', (
    tester,
  ) async {
    // The proposal's own use case is a live llama.cpp server, which needs no
    // key at all: demanding one would lock local endpoints out of the app.
    final t = createTestContainer();
    await t.container
        .read(profileProvider.notifier)
        .save(
          const EndpointProfile(
            baseUrl: 'http://192.0.2.10:8080/v1',
            model: 'qwen3-14b',
          ),
        );
    await tester.pumpWidget(_app(t.container));

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'Send must work for an endpoint that needs no key',
    );
    expect(find.textContaining('No endpoint configured'), findsNothing);

    await _sendMessage(tester, 'hi');
    expect(
      t.service.requests,
      hasLength(1),
      reason: 'and the request must go out',
    );
    expect(
      t.service.requests.single.profile.apiKey,
      '',
      reason: 'an empty key must stay empty rather than be invented',
    );
  });

  group('history drawer', () {
    testWidgets('lists conversations newest first', (tester) async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'old',
            title: 'Older conversation',
            updatedAt: DateTime(2024, 1, 1),
          ),
          ConversationSummary(
            id: 'new',
            title: 'Newest conversation',
            updatedAt: DateTime(2024, 2, 1),
          ),
        ],
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final newest = tester.getTopLeft(find.text('Newest conversation')).dy;
      final older = tester.getTopLeft(find.text('Older conversation')).dy;
      expect(
        newest,
        lessThan(older),
        reason: 'the most recently updated conversation is listed first',
      );
    });

    testWidgets('groups conversations under recency headers', (tester) async {
      final now = DateTime.now();
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'today',
            title: 'Chat from today',
            updatedAt: now,
          ),
          ConversationSummary(
            id: 'yday',
            title: 'Chat from yesterday',
            updatedAt: now.subtract(const Duration(days: 1)),
          ),
          ConversationSummary(
            id: 'midweek',
            title: 'Chat from earlier',
            updatedAt: now.subtract(const Duration(days: 2)),
          ),
          ConversationSummary(
            id: 'ancient',
            title: 'Chat from long ago',
            updatedAt: now.subtract(const Duration(days: 60)),
          ),
        ],
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Chat from earlier'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);

      // Two days back lands in This week unless the week boundary (Monday)
      // pushed it into Older; the header follows the same rule.
      final twoDaysAgoIsThisWeek = DateTime.now().weekday >= 3;
      expect(
        find.text('This week'),
        twoDaysAgoIsThisWeek ? findsOneWidget : findsNothing,
        reason: 'an empty section renders no header',
      );

      final todayHeaderY = tester.getTopLeft(find.text('Today')).dy;
      final todayItemY = tester.getTopLeft(find.text('Chat from today')).dy;
      final yesterdayHeaderY = tester.getTopLeft(find.text('Yesterday')).dy;
      final yesterdayItemY =
          tester.getTopLeft(find.text('Chat from yesterday')).dy;
      final olderHeaderY = tester.getTopLeft(find.text('Older')).dy;
      expect(
        todayHeaderY,
        lessThan(todayItemY),
        reason: 'the Today header sits above its conversations',
      );
      expect(
        todayItemY,
        lessThan(yesterdayHeaderY),
        reason: 'sections run most recent first',
      );
      expect(yesterdayHeaderY, lessThan(yesterdayItemY));
      expect(yesterdayItemY, lessThan(olderHeaderY));
    });

    testWidgets('header rows carry header semantics', (tester) async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'today',
            title: 'Chat from today',
            updatedAt: DateTime.now(),
          ),
        ],
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      final headers = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      );
      expect(
        headers,
        findsWidgets,
        reason: 'screen readers must be able to find section headers',
      );
      expect(
        find.descendant(of: headers, matching: find.text('Today')),
        findsOneWidget,
      );
    });

    testWidgets('the drawer shows Loading... until the first list arrives', (
      tester,
    ) async {
      final repository = _SlowConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'today',
            title: 'Chat from today',
            updatedAt: DateTime.now(),
          ),
        ],
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Loading...'), findsOneWidget);

      repository.releaseFirstBatch();
      await tester.pumpAndSettle();
      expect(find.text('Loading...'), findsNothing);
      expect(find.text('Chat from today'), findsOneWidget);
    });

    testWidgets('shows an empty state when no history exists', (tester) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.text('No conversations yet.'), findsOneWidget);
    });

    testWidgets('New chat keeps earlier conversations in the drawer', (
      tester,
    ) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await _sendMessage(tester, 'first conversation');
      t.service.emit(0, const [StreamDelta(content: 'reply')]);
      t.service.end(0);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('first conversation'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();
      expect(
        find.text('New chat'),
        findsNothing,
        reason: 'the drawer closes after New chat',
      );

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('first conversation'),
        ),
        findsOneWidget,
        reason: 'starting a new chat leaves earlier conversations stored',
      );
    });

    testWidgets('selecting a conversation loads its messages', (tester) async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'target',
            title: 'Target conversation',
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        messagesByConversation: {
          'target': [
            ChatMessage(
              role: ChatRole.user,
              content: 'target question',
              createdAt: DateTime(2026, 1, 1, 9),
            ),
            ChatMessage(
              role: ChatRole.assistant,
              content: 'target answer',
              createdAt: DateTime(2026, 1, 1, 9, 1),
            ),
          ],
        },
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Target conversation'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('target question'), findsOneWidget);
      expect(find.text('target answer'), findsOneWidget);
      expect(
        find.text('New chat'),
        findsNothing,
        reason: 'selecting a conversation closes the drawer',
      );
    });
  });

  group('restored conversation', () {
    testWidgets('restores a saved conversation with its turns in order', (
      tester,
    ) async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'saved',
            title: 'Saved conversation',
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        messagesByConversation: {
          'saved': [
            ChatMessage(
              role: ChatRole.user,
              content: 'first question',
              createdAt: DateTime(2026, 1, 1, 9),
            ),
            ChatMessage(
              role: ChatRole.assistant,
              content: 'first answer',
              createdAt: DateTime(2026, 1, 1, 9, 1),
            ),
            ChatMessage(
              role: ChatRole.user,
              content: 'second question',
              createdAt: DateTime(2026, 1, 1, 9, 2),
            ),
            ChatMessage(
              role: ChatRole.assistant,
              content: 'second answer',
              createdAt: DateTime(2026, 1, 1, 9, 3),
            ),
          ],
        },
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await t.container.read(conversationProvider.notifier).restoreMostRecent();
      await tester.pumpWidget(_app(t.container));
      await tester.pump();

      final first = tester.getTopLeft(find.text('first question')).dy;
      final second = tester.getTopLeft(find.text('first answer')).dy;
      final third = tester.getTopLeft(find.text('second question')).dy;
      final fourth = tester.getTopLeft(find.text('second answer')).dy;
      expect(first < second, isTrue, reason: 'turns keep their stored order');
      expect(second < third, isTrue);
      expect(third < fourth, isTrue);
    });

    testWidgets('a long restored conversation opens scrolled to the bottom', (
      tester,
    ) async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'saved',
            title: 'Long conversation',
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        messagesByConversation: {
          'saved': [
            for (var i = 0; i < 12; i++)
              ChatMessage(
                role: i.isEven ? ChatRole.user : ChatRole.assistant,
                content: 'message $i',
                createdAt: DateTime(2026, 1, 1, 9, i),
              ),
          ],
        },
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      await t.container.read(conversationProvider.notifier).restoreMostRecent();
      await tester.pumpWidget(_app(t.container));
      await tester.pump();
      await tester.pump();

      expect(find.text('message 11'), findsOneWidget);
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(
        position.pixels,
        position.maxScrollExtent,
        reason: 'the restored list opens at its newest turn',
      );
    });
  });

  group('history failures', () {
    testWidgets('a save failure warns without Retry and keeps the turn', (
      tester,
    ) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      t.repository.saveError = Exception('disk full');
      await tester.pumpWidget(_app(t.container));
      await _sendMessage(tester, 'keep me');
      await tester.pump();
      await tester.pump();

      expect(
        find.text('keep me'),
        findsOneWidget,
        reason: 'the user turn stays visible despite the failed save',
      );
      expect(find.text('This turn was not saved to history.'), findsOneWidget);
      expect(
        find.text('Retry'),
        findsNothing,
        reason: 'retrying a storage failure would re-send the conversation',
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('This turn was not saved to history.'), findsNothing);
    });

    testWidgets('a load failure warns without Retry', (tester) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      t.repository.loadError = Exception('corrupt');
      await tester.pumpWidget(_app(t.container));
      await t.container.read(conversationProvider.notifier).restoreMostRecent();
      await tester.pump();

      expect(find.text('History could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('the drawer shows History unavailable when the list errors', (
      tester,
    ) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      t.repository.watchError = Exception('db closed');
      await tester.pumpWidget(_app(t.container));
      await tester.pump();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('History unavailable.'), findsOneWidget);
      expect(find.text('No conversations yet.'), findsNothing);
    });
  });

  group('title row', () {
    void expectMarkBeforeTitle(WidgetTester tester) {
      final appBar = find.byType(AppBar);
      final mark = find.descendant(
        of: appBar,
        matching: find.byType(NatterMark),
      );
      final title = find.descendant(of: appBar, matching: find.text('Natter'));
      expect(mark, findsOneWidget);
      expect(title, findsOneWidget);
      expect(tester.getCenter(mark).dx, lessThan(tester.getCenter(title).dx));
    }

    testWidgets('shows the mark before the title when the chat is empty', (
      tester,
    ) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      expectMarkBeforeTitle(tester);
    });

    testWidgets('keeps the mark unchanged while streaming and after an error', (
      tester,
    ) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      await _sendMessage(tester, 'hi');
      t.service.emit(0, const [StreamDelta(content: 'par')]);
      await tester.pump();
      expectMarkBeforeTitle(tester);

      t.service.fail(0, Exception('boom'));
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      expectMarkBeforeTitle(tester);
    });

    testWidgets('the mark is decorative: one title label and no tap target', (
      tester,
    ) async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(_app(t.container));

      expect(find.bySemanticsLabel('Natter'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(NatterMark),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      final tappable = find.ancestor(
        of: find.byType(NatterMark),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector || w is InkWell,
        ),
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: tappable),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('fits the app bar at the largest text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: t.container,
          child: MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2.0)),
                  child: child!,
                ),
            home: const ChatScreen(),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expectMarkBeforeTitle(tester);
      final endpoint = find.byTooltip('Settings');
      expect(endpoint.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.text('Natter')).right,
        lessThanOrEqualTo(tester.getRect(endpoint).left),
      );
    });
  });
}

/// A fake whose first emission waits for the test, so the drawer's loading
/// state is observable.
class _SlowConversationRepository extends FakeConversationRepository {
  _SlowConversationRepository({super.conversations});

  final Completer<void> _firstBatch = Completer<void>();

  void releaseFirstBatch() => _firstBatch.complete();

  @override
  Stream<List<ConversationSummary>> watchConversations() async* {
    if (!_firstBatch.isCompleted) await _firstBatch.future;
    yield* super.watchConversations();
  }
}
