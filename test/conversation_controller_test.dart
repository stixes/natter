import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/domain/chat_message.dart';
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
}
