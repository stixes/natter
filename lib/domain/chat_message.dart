enum ChatRole { user, assistant }

/// A committed turn in the conversation.
///
/// [reasoning] is captured for the session but never rendered in the answer,
/// and is not replayed to the endpoint (see design.md: store-and-not-replay).
/// It forward-compatibly informs the future nullable `reasoning_content`
/// column in the history change.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoning = '',
  });

  final ChatRole role;
  final String content;
  final String reasoning;

  String get roleWireName => role == ChatRole.user ? 'user' : 'assistant';

  Map<String, String> toWireFormat() => {
    'role': roleWireName,
    'content': content,
  };

  @override
  String toString() => '$roleWireName: $content';
}
