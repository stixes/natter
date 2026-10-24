import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/key_value_store.dart';
import 'package:natter/data/profile_repository.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/stream_delta.dart';
import 'package:natter/state/chat_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_support.dart';

void main() {
  group('single-endpoint configuration storage', () {
    test('the api key lands only in the secure store', () async {
      final settings = InMemoryKeyValueStore();
      final secrets = InMemoryKeyValueStore();
      final repo = ProfileRepository(settings: settings, secrets: secrets);

      await repo.save(testProfile);

      final plain = await settings.contents();
      final secure = await secrets.contents();
      expect(plain[ProfileRepository.baseUrlField], testProfile.baseUrl);
      expect(plain[ProfileRepository.modelField], testProfile.model);
      expect(secure[ProfileRepository.apiKeyField], testProfile.apiKey);
      expect(
        plain.values.any((value) => value.contains(testProfile.apiKey)),
        isFalse,
        reason: 'the key must not sit in the non-secure settings store',
      );
      expect(plain.keys.any((key) => key.contains('apiKey')), isFalse);
    });

    test('config round-trips through storage', () async {
      final settings = InMemoryKeyValueStore();
      final secrets = InMemoryKeyValueStore();
      await ProfileRepository(settings: settings, secrets: secrets)
          .save(testProfile);

      final restored = await ProfileRepository(
        settings: settings,
        secrets: secrets,
      ).load();

      expect(restored, testProfile);
      expect(restored.isConfigured, isTrue);
    });

    test('a blank key is removed from secure storage', () async {
      final settings = InMemoryKeyValueStore();
      final secrets = InMemoryKeyValueStore();
      final repo = ProfileRepository(settings: settings, secrets: secrets);
      await repo.save(testProfile);
      await repo.save(
        const EndpointProfile(
          baseUrl: 'http://host/v1',
          apiKey: '',
          model: 'm',
        ),
      );
      expect((await secrets.contents()).containsKey(ProfileRepository.apiKeyField), isFalse);
      expect((await settings.contents()).containsKey(ProfileRepository.apiKeyField), isFalse);
    });

    test('the default secret store is the keystore-backed one', () {
      expect(SecureKeyValueStore(), isA<KeyValueStore>());
      expect(
        SecureKeyValueStore().runtimeType.toString(),
        'SecureKeyValueStore',
      );
    });

    test('an unset config is incomplete and reads as empty', () async {
      final repo = ProfileRepository(
        settings: InMemoryKeyValueStore(),
        secrets: InMemoryKeyValueStore(),
      );
      final profile = await repo.load();
      expect(profile, const EndpointProfile());
      expect(profile.isConfigured, isFalse);
    });
  });

  group('durable preferences-backed store', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('read, write, delete, and contents all work', () async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesKeyValueStore(
        preferences: preferences,
      );

      expect(await store.read('missing'), isNull);

      await store.write('endpoint.baseUrl', 'http://127.0.0.1:8080/v1');
      await store.write('endpoint.model', 'qwen3-test');
      expect(await store.read('endpoint.baseUrl'), 'http://127.0.0.1:8080/v1');
      expect(await store.contents(), {
        'endpoint.baseUrl': 'http://127.0.0.1:8080/v1',
        'endpoint.model': 'qwen3-test',
      });

      await store.delete('endpoint.baseUrl');
      expect(await store.read('endpoint.baseUrl'), isNull);
      expect(await store.contents(), {'endpoint.model': 'qwen3-test'});
    });
  });

  group('ephemeral conversation', () {
    test('nothing about the conversation is written to storage', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);

      notifier.send('conversation needle alpha');
      await settle();
      t.service.emit(0, const [
        StreamDelta(reasoning: 'hidden needle reasoning'),
        StreamDelta(content: 'reply needle beta'),
      ]);
      t.service.end(0);
      await settle();

      expect(t.container.read(conversationProvider).messages, hasLength(2));
      for (final store in [t.settings, t.secrets]) {
        final contents = await store.contents();
        for (final value in contents.values) {
          expect(value.contains('needle'), isFalse);
        }
      }
    });

    test('a new session starts with an empty conversation', () async {
      final t = createTestContainer();
      await t.container.read(profileProvider.notifier).save(testProfile);
      final notifier = t.container.read(conversationProvider.notifier);
      notifier.send('hello');
      await settle();
      t.service.emit(0, const [StreamDelta(content: 'hi')]);
      t.service.end(0);
      await settle();
      expect(t.container.read(conversationProvider).messages, hasLength(2));

      // A reopened session: same stores, but no conversation to restore.
      final reopened = createTestContainer();
      final settings = await t.settings.contents();
      final secrets = await t.secrets.contents();
      for (final entry in settings.entries) {
        await reopened.settings.write(entry.key, entry.value);
      }
      for (final entry in secrets.entries) {
        await reopened.secrets.write(entry.key, entry.value);
      }
      await reopened.container.read(profileProvider.notifier).loadStored();

      final state = reopened.container.read(conversationProvider);
      expect(state.messages, isEmpty);
      expect(state.draft, isNull);
      expect(reopened.container.read(profileProvider), testProfile);
    });
  });
}
