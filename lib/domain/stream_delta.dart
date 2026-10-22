import 'dart:convert';

/// One classified delta from a streaming `chat/completions` chunk.
///
/// A delta is one of:
/// - answer text ([content] non-empty)
/// - reasoning text ([reasoning] non-empty)
/// - role-only ([isRoleOnly]: carried a `role` but no text)
/// - empty ([isEmpty]: no text and no role marker)
///
/// Role-only and empty deltas must not advance the assistant state machine.
class StreamDelta {
  const StreamDelta({
    this.content = '',
    this.reasoning = '',
    this.hasRole = false,
  });

  final String content;
  final String reasoning;
  final bool hasRole;

  bool get hasContent => content.isNotEmpty;
  bool get hasReasoning => reasoning.isNotEmpty;

  bool get isText => hasContent || hasReasoning;

  /// A `role` marker with no text: must not end the waiting state.
  bool get isRoleOnly => hasRole && !isText;

  /// No text and no role marker.
  bool get isEmpty => !isText && !hasRole;

  @override
  String toString() =>
      'StreamDelta(content: $content, reasoning: $reasoning, role: $hasRole)';
}

String? _text(Object? value) => value is String ? value : null;

/// Reads the reasoning out of a delta map using the flat-string superset
/// `reasoning_content ?? reasoning`, which covers llama.cpp/llamaswap
/// (`reasoning_content`) and OpenRouter/Ollama-style (`reasoning`) with no
/// configuration. `reasoning_details` is out of scope for this change.
String _reasoningOf(Map<Object?, Object?> delta) {
  final content = _text(delta['reasoning_content']);
  if (content != null && content.isNotEmpty) return content;
  return _text(delta['reasoning']) ?? '';
}

/// Parses one SSE `data:` payload into a [StreamDelta].
///
/// Returns null when the payload carries no text-bearing choice delta (usage
/// chunks, keepalives, heartbeats), which the caller skips.
StreamDelta? parseCompletionDelta(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final choice = choices.first;
  if (choice is! Map) return null;

  // Some gateways put the incremental text on `delta`, others on `message`.
  final delta = choice['delta'] ?? choice['message'];
  if (delta is! Map) return null;

  return StreamDelta(
    content: _text(delta['content']) ?? '',
    reasoning: _reasoningOf(delta),
    hasRole: delta.containsKey('role'),
  );
}
