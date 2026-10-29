import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/key_value_store.dart';
import 'package:natter/data/profile_repository.dart';
import 'package:natter/data/system_prompt_repository.dart';
import 'package:natter/domain/system_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_support.dart';

void main() {
  group('system prompt setting', () {
    test('the built-in default asks for brief, phone-readable replies', () {
      expect(kDefaultSystemPrompt, contains('brief'));
      expect(kDefaultSystemPrompt, isNotEmpty);
      // Per design.md the default stays small so the per-request cost is
      // negligible; a rough word count keeps it near that budget.
      expect(
        kDefaultSystemPrompt.split(RegExp(r'\s+')).length,
        lessThan(120),
        reason: 'the default must stay under ~80 tokens',
      );
    });

    test('no stored value means the built-in default is in effect', () {
      final setting = SystemPromptSetting.stored(null);

      expect(setting.state, SystemPromptState.defaultValue);
      expect(setting.isDefault, isTrue);
      expect(setting.inEffect, kDefaultSystemPrompt);
      expect(setting.fieldText, kDefaultSystemPrompt);
    });

    test('stored text other than the default is kept verbatim', () {
      const edited = 'Answer in haiku, always.';
      final setting = SystemPromptSetting.stored(edited);

      expect(setting.state, SystemPromptState.editedValue);
      expect(setting.isDefault, isFalse);
      expect(setting.inEffect, edited);
      expect(setting.fieldText, edited);
    });

    test('a stored empty string means no prompt at all', () {
      final setting = SystemPromptSetting.stored('');

      expect(setting.state, SystemPromptState.clearedValue);
      expect(setting.isDefault, isFalse);
      expect(setting.inEffect, isEmpty);
      expect(setting.fieldText, isEmpty);
    });
  });

  group('system prompt repository save rules', () {
    test('saving text equal to the built-in default leaves the key absent', () async {
      final settings = InMemoryKeyValueStore();
      final repo = SystemPromptRepository(settings: settings);

      await repo.save(kDefaultSystemPrompt);

      final stored = await settings.contents();
      expect(stored.containsKey(SystemPromptRepository.promptField), isFalse,
          reason: 'the user keeps following the shipped default');
      expect((await repo.load()).isDefault, isTrue);
    });

    test('whitespace-only text stores the cleared state', () async {
      final settings = InMemoryKeyValueStore();
      final repo = SystemPromptRepository(settings: settings);

      await repo.save('   \n\t ');

      final setting = await repo.load();
      expect(setting.state, SystemPromptState.clearedValue);
      expect(setting.inEffect, isEmpty);
    });

    test('other text is stored trimmed and read back verbatim', () async {
      final settings = InMemoryKeyValueStore();
      final repo = SystemPromptRepository(settings: settings);

      await repo.save('  Answer in haiku, always.  ');

      final stored = await settings.contents();
      expect(stored[SystemPromptRepository.promptField],
          'Answer in haiku, always.');
      expect((await repo.load()).inEffect, 'Answer in haiku, always.');
    });
  });

  group('durable system prompt setting', () {
    Future<SystemPromptRepository> repoOverPrefs() async {
      final preferences = await SharedPreferences.getInstance();
      return SystemPromptRepository(
        settings: SharedPreferencesKeyValueStore(preferences: preferences),
      );
    }

    test('an edited prompt survives a simulated restart', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await repoOverPrefs();

      await first.save('Answer in haiku, always.');

      // A restart re-acquires the plugin handle and builds a fresh
      // repository over the same durable settings.
      final restored = await repoOverPrefs();
      final setting = await restored.load();

      expect(setting.state, SystemPromptState.editedValue);
      expect(setting.inEffect, 'Answer in haiku, always.');
      expect(setting.fieldText, 'Answer in haiku, always.');
    });

    test('a cleared prompt survives a simulated restart', () async {
      SharedPreferences.setMockInitialValues({
        SystemPromptRepository.promptField: 'Answer in haiku, always.',
      });
      final first = await repoOverPrefs();

      await first.save('   '); // clearing the field

      final restored = await repoOverPrefs();
      final setting = await restored.load();

      expect(setting.state, SystemPromptState.clearedValue);
      expect(setting.fieldText, isEmpty);
      expect(setting.inEffect, isEmpty,
          reason: 'a cleared prompt stays cleared, not the default');
    });

    test('saving the untouched default keeps the key absent across restarts',
        () async {
      SharedPreferences.setMockInitialValues({});
      final first = await repoOverPrefs();

      await first.save(kDefaultSystemPrompt);

      final restored = await repoOverPrefs();
      final setting = await restored.load();

      expect(setting.isDefault, isTrue);
      expect(setting.inEffect, kDefaultSystemPrompt);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().contains(SystemPromptRepository.promptField),
        isFalse,
      );
    });

    test('the prompt never appears in the secure store', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SharedPreferencesKeyValueStore(
        preferences: await SharedPreferences.getInstance(),
      );
      final secrets = InMemoryKeyValueStore();
      const edited = 'Remember this prompt verbatim, it is sensitive.';

      await SystemPromptRepository(settings: settings).save(edited);
      // The profile save is what normally touches the keystore; run one so
      // the assertion covers a fully configured app.
      await ProfileRepository(settings: settings, secrets: secrets)
          .save(testProfile);

      final secure = await secrets.contents();
      expect(secure.containsKey(SystemPromptRepository.promptField), isFalse);
      expect(
        secure.values.any((value) => value.contains(edited)),
        isFalse,
        reason: 'the prompt must never reach keystore-backed storage',
      );
      final plain = await settings.contents();
      expect(plain[SystemPromptRepository.promptField], edited);
    });
  });
}
