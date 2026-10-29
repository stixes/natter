/// The built-in default system prompt: it shapes replies for a small phone
/// chat - brief, direct, lightly formatted. Shipped in code so a fresh
/// install needs no setup, and so a better default in a later release reaches
/// users who never edited it. Final wording is settled by the live on-device
/// round (see the adjustable-system-prompt change's validation.md).
const String kDefaultSystemPrompt =
    'You are the assistant in Natter, a small chat app on a phone. Keep '
    'replies brief and direct; give detail only when asked. Use light '
    'formatting: short paragraphs, simple lists, and code blocks for code. '
    'Avoid tables wider than three columns and avoid large headings, '
    'because the screen is narrow.';

/// The system prompt setting as three states (design.md: tri-state storage).
///
/// [SystemPromptSetting.stored] is what a repository read yields: a null
/// value means the user never saved anything, so the built-in default is in
/// effect; the empty string means the user cleared it; anything else is the
/// prompt as saved. Resolution lives here, so "what rides the wire" and
/// "what the field shows" can never disagree.
class SystemPromptSetting {
  const SystemPromptSetting._(this.state, this._text);

  /// Resolves one stored value: null -> default, '' -> cleared, else edited.
  factory SystemPromptSetting.stored(String? storedValue) {
    if (storedValue == null) {
      return const SystemPromptSetting._(
        SystemPromptState.defaultValue,
        null,
      );
    }
    if (storedValue.isEmpty) {
      return const SystemPromptSetting._(
        SystemPromptState.clearedValue,
        '',
      );
    }
    return SystemPromptSetting._(SystemPromptState.editedValue, storedValue);
  }

  final SystemPromptState state;

  /// The stored text; null while following the built-in default.
  final String? _text;

  /// The prompt to send with a request; '' means send no system message.
  String get inEffect => switch (state) {
    SystemPromptState.defaultValue => kDefaultSystemPrompt,
    SystemPromptState.clearedValue => '',
    SystemPromptState.editedValue => _text!,
  };

  /// What the settings field shows pre-filled.
  String get fieldText => inEffect;

  bool get isDefault => state == SystemPromptState.defaultValue;

  @override
  bool operator ==(Object other) =>
      other is SystemPromptSetting &&
      other.state == state &&
      other._text == _text;

  @override
  int get hashCode => Object.hash(state, _text);

  @override
  String toString() => 'SystemPromptSetting($state)';
}

enum SystemPromptState {
  /// No key stored: the built-in default is in effect.
  defaultValue,

  /// Stored text of the user's own, kept verbatim across restarts.
  editedValue,

  /// Stored as the empty string: requests carry no system message.
  clearedValue,
}
