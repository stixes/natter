import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/domain/assistant_draft.dart';
import 'package:natter/domain/chat_message.dart';
import 'package:natter/domain/conversation_summary.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/stream_delta.dart';
import 'package:natter/state/chat_providers.dart';

import 'support/test_support.dart';

void main() {
  group('conversation', () {
    test('a chat request reads URL, key, and model from profile state', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);

      notifier.send('hello');
      await settle();

      expect(t.service.requests, hasLength(1));
      expect(t.service.requests.single.profile, testProfile);
      expect(
        t.service.requests.single.messages.map((m) => m.content).toList(),
        ['hello'],
      );
    });

    test('an unconfigured profile produces an error and no request', () async {
      final t = createTestContainer();
      t.container.read(conversationProvider.notifier).send('hello');
      await settle();

      expect(
        t.container.read(conversationProvider).error,
        contains('Settings'),
      );
      expect(t.service.requests, isEmpty);
    });

    test('streaming grows the draft, then commits one assistant turn', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();

      t.service.emit(0, const [
        StreamDelta(content: 'Hel'),
        StreamDelta(content: 'lo'),
      ]);
      await settle();

      var state = t.container.read(conversationProvider);
      expect(state.draft, isNotNull);
      expect(state.draft!.visibleText, 'Hello');

      t.service.end(0);
      await settle();

      state = t.container.read(conversationProvider);
      expect(state.draft, isNull);
      expect(state.messages.map((m) => m.content).toList(), ['hi', 'Hello']);
    });

    test('committed turns keep the same creation time in memory and storage',
        () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();

      final userTurn = t.container.read(conversationProvider).messages.single;
      expect(userTurn.role, ChatRole.user);
      final savedUser = t.repository.savedTurns.single;
      expect(savedUser.message.createdAt, userTurn.createdAt);
      expect(savedUser.at, userTurn.createdAt);

      t.service.emit(0, const [StreamDelta(content: 'Hello')]);
      t.service.end(0);
      await settle();

      final assistantTurn =
          t.container.read(conversationProvider).messages.last;
      expect(assistantTurn.role, ChatRole.assistant);
      final savedAssistant = t.repository.savedTurns
          .where((turn) => turn.message.role == ChatRole.assistant)
          .single;
      expect(savedAssistant.message.createdAt, assistantTurn.createdAt);
      expect(savedAssistant.at, assistantTurn.createdAt);
    });

    test('reasoning is retained on the message but never in the answer', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();

      t.service.emit(0, const [
        StreamDelta(reasoning: 'hidden chain of thought'),
        StreamDelta(content: 'visible answer'),
      ]);
      t.service.end(0);
      await settle();

      final reply = t.container.read(conversationProvider).messages.last;
      expect(reply.role, ChatRole.assistant);
      expect(reply.content, 'visible answer');
      expect(reply.reasoning, 'hidden chain of thought');
    });

    test('blank answer falls back to the captured reasoning', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();

      t.service.emit(0, const [
        StreamDelta(reasoning: 'everything landed in reasoning'),
      ]);
      t.service.end(0);
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.messages, hasLength(2));
      expect(state.messages.last.content, 'everything landed in reasoning');
    });

    test('cancel mid-stream keeps prior state and ignores late tokens',
        () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();

      t.service.emit(0, const [StreamDelta(content: 'partial')]);
      await settle();
      notifier.cancel();
      await settle();

      // The endpoint keeps talking after the cancel; none of it may land.
      t.service.emit(0, const [StreamDelta(content: ' too far')]);
      t.service.end(0);
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.draft, isNull);
      expect(state.error, isNull);
      expect(state.isStreaming, isFalse);
      expect(
        state.messages.map((m) => m.content).toList(),
        ['hi', 'partial'],
      );
      // The conversation is still sendable.
      notifier.send('next');
      await settle();
      expect(t.service.requests, hasLength(2));
      expect(
        t.service.requests.last.messages.map((m) => m.content).toList(),
        ['hi', 'partial', 'next'],
      );
    });

    test('cancel before any token leaves the conversation clean', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();
      notifier.cancel();
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.messages.map((m) => m.content).toList(), ['hi']);
      expect(state.draft, isNull);
      expect(state.error, isNull);
    });

    test('cancel during thinking commits nothing: half a chain of thought is '
        'not an answer', () async {
      // This is the case a live thinking model hits: reasoning lands, then the
      // user cancels before any answer token. The blank-answer fallback belongs
      // to a completed stream, not to a deliberate abort.
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();
      t.service.emit(0, const [
        StreamDelta(reasoning: 'let me think'),
        StreamDelta(reasoning: ' about it'),
      ]);
      await settle();
      expect(t.container.read(conversationProvider).draft?.phase,
          AssistantPhase.thinking);

      notifier.cancel();
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.messages.map((m) => m.content).toList(), ['hi'],
          reason: 'no assistant turn may be committed from reasoning alone');
      expect(state.draft, isNull);
      expect(state.error, isNull);
    });

    test('a mid-stream error surfaces and leaves earlier messages intact',
        () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);

      // First turn completes normally.
      notifier.send('one');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'first reply')]);
      t.service.end(0);
      await settle();
      final before = List.of(t.container.read(conversationProvider).messages);

      // Second turn dies after some output.
      notifier.send('two');
      await settle();
      t.service.emit(1, const [StreamDelta(content: 'half a sentence')]);
      await settle();
      t.service.fail(1, const ChatRequestFailure('The stream failed'));
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.draft, isNull, reason: 'the failed attempt leaves no draft');
      expect(state.error, 'The stream failed');
      expect(
        state.messages.take(before.length).map((m) => m.content).toList(),
        before.map((m) => m.content).toList(),
      );
      expect(
        state.messages.map((m) => m.content).toList(),
        ['one', 'first reply', 'two'],
        reason: 'no half-finished reply is committed',
      );
    });

    test('retry re-sends the existing conversation', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);

      notifier.send('one');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'first reply')]);
      t.service.end(0);
      await settle();

      notifier.send('two');
      await settle();
      t.service.fail(1, const ChatRequestFailure('boom'));
      await settle();

      notifier.retry();
      await settle();

      expect(t.service.requests, hasLength(3));
      expect(
        t.service.requests.last.messages.map((m) => m.content).toList(),
        ['one', 'first reply', 'two'],
        reason: 'retry sends the existing conversation, adding no new turn',
      );
      expect(t.service.requests.last.profile, testProfile);

      // The retried attempt behaves like any other.
      t.service.emit(2, const [StreamDelta(content: 'second reply')]);
      t.service.end(2);
      await settle();
      expect(
        t.container.read(conversationProvider).messages
            .map((m) => m.content)
            .toList(),
        ['one', 'first reply', 'two', 'second reply'],
      );
      expect(t.container.read(conversationProvider).error, isNull);
    });

    test('dismissError clears the banner without touching messages', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();
      t.service.fail(0, const ChatRequestFailure('nope'));
      await settle();

      notifier.dismissError();
      await settle();
      final state = t.container.read(conversationProvider);
      expect(state.error, isNull);
      expect(state.messages.map((m) => m.content).toList(), ['hi']);
    });

    test('the conversation is never written to storage', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('conversation needle alpha');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'reply needle beta')]);
      t.service.end(0);
      await settle();

      for (final store in [t.settings, t.secrets]) {
        final contents = await store.contents();
        expect(contents.values.any((value) => value.contains('needle')), isFalse);
      }
    });

    test('a fresh session starts with an empty conversation', () async {
      final first = createTestContainer();
      final firstNotifier = first.container.read(conversationProvider.notifier);
      await first.container
          .read(profileProvider.notifier)
          .save(testProfile);
      firstNotifier.send('hello');
      await settle();
      first.service.emit(0, const [StreamDelta(content: 'reply')]);
      first.service.end(0);
      await settle();
      expect(first.container.read(conversationProvider).messages, hasLength(2));

      // Same stored config, new session: the conversation is not restored.
      final second = createTestContainer();
      await second.container
          .read(profileProvider.notifier)
          .save(first.container.read(profileProvider));
      final state = second.container.read(conversationProvider);
      expect(state.messages, isEmpty);
      expect(state.draft, isNull);
      expect(state.error, isNull);
    });

    test('reasoning is not replayed to the endpoint', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);
      notifier.send('hi');
      await settle();
      t.service.emit(0, const [
        StreamDelta(reasoning: 'hidden'),
        StreamDelta(content: 'shown'),
      ]);
      t.service.end(0);
      await settle();

      notifier.send('follow up');
      await settle();
      expect(
        t.service.requests.last.messages.map((m) => m.toWireFormat()).toList(),
        const [
          {'role': 'user', 'content': 'hi'},
          {'role': 'assistant', 'content': 'shown'},
          {'role': 'user', 'content': 'follow up'},
        ],
      );
    });
    test('a silence failure keeps the partial answer and stays sendable',
        () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial answer')]);
      await settle();
      t.service.fail(
        0,
        const ChatRequestFailure(
          'The reply stopped arriving.',
          isSilenceFailure: true,
        ),
      );
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.error, 'The reply stopped arriving.');
      expect(state.draft, isNull);
      expect(
        state.messages.map((m) => m.content).toList(),
        ['hi', 'partial answer'],
      );
      final committed = state.messages.last;
      expect(committed.role, ChatRole.assistant);
      expect(committed.content, 'partial answer');

      // The conversation is still well-formed and sendable.
      notifier.send('next');
      await settle();
      expect(t.service.requests, hasLength(2));
      expect(
        t.service.requests.last.messages.map((m) => m.content).toList(),
        ['hi', 'partial answer', 'next'],
      );
    });

    test('a non-silence failure still drops the partial', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial answer')]);
      await settle();
      t.service.fail(0, const ChatRequestFailure('boom'));
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.error, 'boom');
      expect(state.draft, isNull);
      expect(
        state.messages.map((m) => m.content).toList(),
        ['hi'],
        reason: 'a non-silence failure must not commit the partial',
      );
    });

    test('a silence failure with only reasoning commits no answer', () async {
      final t = createTestContainer();
      final notifier = t.container.read(conversationProvider.notifier);
      await t.container.read(profileProvider.notifier).save(testProfile);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(reasoning: 'thinking only')]);
      await settle();
      t.service.fail(
        0,
        const ChatRequestFailure(
          'The reply stopped arriving.',
          isSilenceFailure: true,
        ),
      );
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.error, 'The reply stopped arriving.');
      expect(
        state.messages.map((m) => m.content).toList(),
        ['hi'],
        reason: 'reasoning alone is not an answer, as with cancel',
      );
    });
  });

  group('profile state', () {
    test('saved config survives a reload of the same stores', () async {
      final t = createTestContainer();
      await t.container
          .read(profileProvider.notifier)
          .save(const EndpointProfile(
            baseUrl: 'http://host:8080/v1',
            apiKey: 'key-material',
            model: 'm',
          ));

      final reloaded = createTestContainer();
      // Same locations, new controller: reload what is stored.
      await reloaded.settings
          .write('endpoint.baseUrl', 'http://host:8080/v1');
      await reloaded.settings.write('endpoint.model', 'm');
      await reloaded.secrets.write('endpoint.apiKey', 'key-material');
      await reloaded.container.read(profileProvider.notifier).loadStored();

      final profile = reloaded.container.read(profileProvider);
      expect(profile.baseUrl, 'http://host:8080/v1');
      expect(profile.apiKey, 'key-material');
      expect(profile.model, 'm');
      expect(profile.isConfigured, isTrue);
    });
  });

  group('history restore', () {
    test('restores the most recent saved conversation', () async {
      final summary = ConversationSummary(
        id: 'saved',
        title: 'Saved conversation',
        updatedAt: DateTime(2024, 1, 1),
      );
      final repository = FakeConversationRepository(
        conversations: [summary],
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'hello',
            createdAt: DateTime(2026, 1, 1, 9),
          ),
          ChatMessage(
            role: ChatRole.assistant,
            content: 'hi',
            createdAt: DateTime(2026, 1, 1, 9, 1),
          ),
        ],
      );
      final t = createTestContainer(repository: repository);
      final notifier = t.container.read(conversationProvider.notifier);

      await notifier.restoreMostRecent();

      final state = t.container.read(conversationProvider);
      expect(state.conversationId, 'saved');
      expect(state.messages.map((m) => m.content).toList(), ['hello', 'hi']);
      expect(state.historyNotice, isNull);
      expect(state.draft, isNull);
      expect(state.error, isNull);
    });

    test('a load failure starts empty with a history notice', () async {
      final repository = FakeConversationRepository()
        ..loadError = StateError('history unavailable');
      final t = createTestContainer(repository: repository);
      final notifier = t.container.read(conversationProvider.notifier);

      await notifier.restoreMostRecent();

      final state = t.container.read(conversationProvider);
      expect(state.messages, isEmpty);
      expect(state.conversationId, isNull);
      expect(state.historyNotice, isNotNull);
      expect(state.error, isNull);
    });
  });

  group('history persistence', () {
    test('saves the user turn before the request starts', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hello history');
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.conversationId, isNotNull);
      expect(t.repository.savedTurns, hasLength(1));
      final saved = t.repository.savedTurns.single;
      expect(saved.conversationId, state.conversationId);
      expect(saved.message.role, ChatRole.user);
      expect(saved.message.content, 'hello history');
      expect(saved.title, 'hello history');
      expect(t.service.requests, hasLength(1),
          reason: 'the request starts after the save');
      expect(
        t.service.requests.single.messages.map((m) => m.content).toList(),
        ['hello history'],
      );
    });

    test('a failed save warns and still streams a reply', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      t.repository.saveError = StateError('disk full');
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hello');
      await settle();

      var state = t.container.read(conversationProvider);
      expect(state.historyNotice, contains('not saved'));
      expect(t.service.requests, hasLength(1),
          reason: 'the request still starts');
      expect(state.messages.map((m) => m.content).toList(), ['hello']);

      t.service.emit(0, const [StreamDelta(content: 'reply')]);
      t.service.end(0);
      await settle();

      state = t.container.read(conversationProvider);
      expect(state.messages.map((m) => m.content).toList(), ['hello', 'reply']);
      expect(state.historyNotice, contains('not saved'),
          reason: 'the warning stays until dismissed');
      expect(state.error, isNull);
    });

    test('an in-flight draft never reaches the repository', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial answer')]);
      await settle();

      expect(
        t.repository.savedTurns.where(
          (turn) => turn.message.role == ChatRole.assistant,
        ),
        isEmpty,
        reason: 'the streaming draft must not be written',
      );
      expect(t.container.read(conversationProvider).draft, isNotNull);

      t.service.end(0);
      await settle();
    });
  });

  group('assistant persistence', () {
    test('saves the assistant turn on normal end', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'reply')]);
      t.service.end(0);
      await settle();

      expect(
        t.repository.savedTurns.map((turn) => turn.message.role).toList(),
        [ChatRole.user, ChatRole.assistant],
      );
      expect(t.repository.savedTurns.last.message.content, 'reply');
      final state = t.container.read(conversationProvider);
      expect(state.messages.map((m) => m.content).toList(), ['hi', 'reply']);
      expect(state.historyNotice, isNull);
    });

    test('saves the assistant turn on cancel with answer text', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial')]);
      await settle();
      notifier.cancel();
      await settle();

      expect(
        t.repository.savedTurns.map((turn) => turn.message.role).toList(),
        [ChatRole.user, ChatRole.assistant],
      );
      expect(t.repository.savedTurns.last.message.content, 'partial');
    });

    test('saves nothing when cancel arrives before any answer text',
        () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hi');
      await settle();
      notifier.cancel();
      await settle();

      expect(
        t.repository.savedTurns.map((turn) => turn.message.role).toList(),
        [ChatRole.user],
        reason: 'cancel without answer text commits no assistant turn',
      );
    });

    test('saves the partial answer when a silence failure commits it',
        () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hi');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial')]);
      await settle();
      t.service.fail(
        0,
        const ChatRequestFailure(
          'The reply stopped arriving.',
          isSilenceFailure: true,
        ),
      );
      await settle();

      expect(
        t.repository.savedTurns.map((turn) => turn.message.role).toList(),
        [ChatRole.user, ChatRole.assistant],
      );
      expect(t.repository.savedTurns.last.message.content, 'partial');
      final state = t.container.read(conversationProvider);
      expect(state.messages.map((m) => m.content).toList(), ['hi', 'partial']);
      expect(state.error, 'The reply stopped arriving.');
    });

    test('a failed assistant save keeps the reply visible', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hi');
      await settle();
      // The user turn saved; only the assistant save fails.
      t.repository.saveError = StateError('disk full');
      t.service.emit(0, const [StreamDelta(content: 'reply')]);
      t.service.end(0);
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.messages.map((m) => m.content).toList(), ['hi', 'reply']);
      expect(state.historyNotice, contains('not saved'));
      expect(state.error, isNull);
    });
  });

  group('titles and new chat', () {
    test('sets the title once from the first user message', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('first message');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'reply')]);
      t.service.end(0);
      await settle();

      notifier.send('second message');
      await settle();
      t.service.emit(1, const [StreamDelta(content: 'reply two')]);
      t.service.end(1);
      await settle();

      final summary = await t.repository.loadMostRecent();
      expect(summary?.title, 'first message',
          reason: 'later messages must not change the title');
    });

    test('shortens a long title for the list', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('a' * 60);
      await settle();

      final summary = await t.repository.loadMostRecent();
      expect(summary?.title, '${'a' * 48}…');
      expect(summary?.title.length, 49);
    });

    test('makes no title request to the stream service', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('hello');
      await settle();

      expect(t.service.requests, hasLength(1),
          reason: 'the title is derived locally');
    });

    test('New chat clears the screen without inserting a row', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('first');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'reply')]);
      t.service.end(0);
      await settle();
      final savedBefore = t.repository.savedTurns.length;

      notifier.startNewChat();
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.messages, isEmpty);
      expect(state.conversationId, isNull);
      expect(state.draft, isNull);
      expect(t.repository.savedTurns, hasLength(savedBefore),
          reason: 'New chat inserts no row');
    });

    test('New chat stops an in-flight reply and keeps its answer text',
        () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('first');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial')]);
      await settle();

      notifier.startNewChat();
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.messages, isEmpty);
      expect(state.conversationId, isNull);
      expect(state.draft, isNull);
      expect(t.repository.savedTurns.last.message.content, 'partial',
          reason: 'the answer already received stays in the old conversation');
    });
  });

  group('open conversation', () {
    test('loads the target conversation messages', () async {
      final target = ConversationSummary(
        id: 'target',
        title: 'Target',
        updatedAt: DateTime(2024, 1, 1),
      );
      final repository = FakeConversationRepository(
        conversations: [target],
        messagesByConversation: {
          'target': [
            ChatMessage(
              role: ChatRole.user,
              content: 'saved question',
              createdAt: DateTime(2026, 1, 1, 9),
            ),
            ChatMessage(
              role: ChatRole.assistant,
              content: 'saved answer',
              createdAt: DateTime(2026, 1, 1, 9, 1),
            ),
          ],
        },
      );
      final t = createTestContainer(repository: repository);
      final notifier = t.container.read(conversationProvider.notifier);

      await notifier.openConversation('target');

      final state = t.container.read(conversationProvider);
      expect(state.conversationId, 'target');
      expect(
        state.messages.map((m) => m.content).toList(),
        ['saved question', 'saved answer'],
      );
      expect(state.historyNotice, isNull);
      expect(state.draft, isNull);
    });

    test('switching mid-stream keeps the partial in the conversation left',
        () async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'target',
            title: 'Target',
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        messagesByConversation: {
          'target': [
            ChatMessage(
              role: ChatRole.user,
              content: 'saved question',
              createdAt: DateTime(2026, 1, 1, 9),
            ),
          ],
        },
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('outgoing');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial')]);
      await settle();

      await notifier.openConversation('target');
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.conversationId, 'target');
      expect(state.messages.map((m) => m.content).toList(), ['saved question']);
      expect(
        t.repository.savedTurns
            .where((turn) => turn.message.role == ChatRole.assistant)
            .map((turn) => turn.message.content)
            .toList(),
        ['partial'],
        reason: 'the partial stays in the conversation being left',
      );
      expect(t.service.requests, hasLength(1),
          reason: 'switching does not start a new request');
    });

    test('switching when no answer text arrived commits nothing', () async {
      final repository = FakeConversationRepository(
        conversations: [
          ConversationSummary(
            id: 'target',
            title: 'Target',
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        messagesByConversation: {
          'target': [
            ChatMessage(
              role: ChatRole.user,
              content: 'saved question',
              createdAt: DateTime(2026, 1, 1, 9),
            ),
          ],
        },
      );
      final t = createTestContainer(repository: repository);
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('outgoing');
      await settle();
      await notifier.openConversation('target');
      await settle();

      expect(
        t.repository.savedTurns
            .where((turn) => turn.message.role == ChatRole.assistant),
        isEmpty,
        reason: 'cancel without answer text commits no assistant turn',
      );
      final state = t.container.read(conversationProvider);
      expect(state.conversationId, 'target');
    });

    test('a load failure leaves the current conversation usable', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('outgoing');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'partial')]);
      await settle();
      t.repository.loadError = StateError('unavailable');

      await notifier.openConversation('target');
      await settle();

      final state = t.container.read(conversationProvider);
      expect(state.conversationId, isNotNull);
      expect(
        state.messages.map((m) => m.content).toList(),
        ['outgoing', 'partial'],
      );
      expect(state.historyNotice, contains('could not be loaded'));
      expect(state.draft, isNull);
    });
  });
}
