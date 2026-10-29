import '../domain/system_prompt.dart';
import 'key_value_store.dart';

/// Persists the system prompt setting in the plain settings store, beside
/// base URL and model. The prompt is configuration, not a secret and not
/// conversation content, so it must never reach the keystore.
///
/// One key holds all three states (design.md: tri-state storage): absent
/// means the built-in default is in effect, the empty string means cleared,
/// any other value is the prompt as saved.
class SystemPromptRepository {
  SystemPromptRepository({required this.settings});

  final KeyValueStore settings;

  static const promptField = 'chat.systemPrompt';

  Future<SystemPromptSetting> load() async {
    return SystemPromptSetting.stored(await settings.read(promptField));
  }

  /// Applies the save rules from design.md: text that trims to empty stores
  /// the empty string (cleared); text that trims equal to the built-in
  /// default deletes the key, so the user keeps following the default across
  /// releases; anything else stores the text trimmed at the edges.
  Future<void> save(String fieldText) async {
    final trimmed = fieldText.trim();
    if (trimmed.isEmpty) {
      await settings.write(promptField, '');
    } else if (trimmed == kDefaultSystemPrompt.trim()) {
      await settings.delete(promptField);
    } else {
      await settings.write(promptField, trimmed);
    }
  }
}
