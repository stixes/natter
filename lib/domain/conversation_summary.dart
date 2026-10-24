/// A saved conversation as shown in the history list.
///
/// Kept in the domain layer so the controller and widget tests never depend on
/// Drift's generated row types.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
}
