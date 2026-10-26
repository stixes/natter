enum ChatRole { user, assistant }

/// A committed turn in the conversation.
///
/// [reasoning] is captured for the session but never rendered in the answer,
/// and is not replayed to the endpoint (see design.md: store-and-not-replay).
/// It forward-compatibly informs the future nullable `reasoning_content`
/// column in the history change. [createdAt] is when the turn was sent or
/// committed; it stays local metadata and is never sent to the endpoint.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoning = '',
    required this.createdAt,
  });

  final ChatRole role;
  final String content;
  final String reasoning;
  final DateTime createdAt;

  String get roleWireName => role == ChatRole.user ? 'user' : 'assistant';

  Map<String, String> toWireFormat() => {
    'role': roleWireName,
    'content': content,
  };

  @override
  String toString() => '$roleWireName: $content';
}
