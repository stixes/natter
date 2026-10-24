import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/key_value_store.dart';
import 'package:natter/data/profile_repository.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/state/chat_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_support.dart';

void main() {
  group('durable endpoint settings', () {
    test(
      'a preferences-backed container loads a saved base URL and model',
      () async {
        SharedPreferences.setMockInitialValues({
          ProfileRepository.baseUrlField: 'http://127.0.0.1:8080/v1',
          ProfileRepository.modelField: 'qwen3-test',
        });
        final preferences = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            settingsStoreProvider.overrideWithValue(
              SharedPreferencesKeyValueStore(preferences: preferences),
            ),
            secretStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          ],
        );
        addTearDown(container.dispose);

        await container.read(profileProvider.notifier).loadStored();

        final profile = container.read(profileProvider);
        expect(profile.baseUrl, 'http://127.0.0.1:8080/v1');
        expect(profile.model, 'qwen3-test');
        expect(profile.isConfigured, isTrue);
      },
    );

    test('a saved profile survives a simulated restart', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SharedPreferencesKeyValueStore(preferences: preferences);
      final secrets = InMemoryKeyValueStore();
      final first = ProfileRepository(settings: settings, secrets: secrets);

      await first.save(testProfile);

      // A restart re-acquires the plugin handle and builds a fresh repository
      // over the same durable settings and secure storage.
      final restartedPreferences = await SharedPreferences.getInstance();
      final restored = await ProfileRepository(
        settings: SharedPreferencesKeyValueStore(
          preferences: restartedPreferences,
        ),
        secrets: secrets,
      ).load();

      expect(restored.baseUrl, testProfile.baseUrl);
      expect(restored.model, testProfile.model);
      expect(restored.apiKey, testProfile.apiKey);
      expect(restored.isConfigured, isTrue);

      final plain = await settings.contents();
      expect(plain[ProfileRepository.baseUrlField], testProfile.baseUrl);
      expect(plain[ProfileRepository.modelField], testProfile.model);
      expect(plain.containsKey(ProfileRepository.apiKeyField), isFalse);
      expect(
        plain.values.any((value) => value.contains(testProfile.apiKey)),
        isFalse,
        reason: 'the key must never land in the plain settings store',
      );

      final secure = await secrets.contents();
      expect(secure[ProfileRepository.apiKeyField], testProfile.apiKey);
    });

    test('a keyless endpoint survives a restart and stays configured', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SharedPreferencesKeyValueStore(preferences: preferences);
      final secrets = InMemoryKeyValueStore();
      const keyless = EndpointProfile(
        baseUrl: 'http://127.0.0.1:8080/v1',
        apiKey: '',
        model: 'qwen3-test',
      );

      await ProfileRepository(settings: settings, secrets: secrets)
          .save(keyless);

      final restored = await ProfileRepository(
        settings: SharedPreferencesKeyValueStore(
          preferences: await SharedPreferences.getInstance(),
        ),
        secrets: secrets,
      ).load();

      expect(restored.baseUrl, keyless.baseUrl);
      expect(restored.model, keyless.model);
      expect(restored.apiKey, isEmpty);
      expect(restored.isConfigured, isTrue);

      final plain = await settings.contents();
      expect(plain.containsKey(ProfileRepository.apiKeyField), isFalse);
      expect(plain.keys.any((key) => key.contains('apiKey')), isFalse);
    });
  });
}
