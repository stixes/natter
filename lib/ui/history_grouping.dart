import '../domain/conversation_summary.dart';

/// The four recency buckets shown in the history drawer.
enum HistorySection { today, yesterday, thisWeek, older }

/// A partitioned view of the conversation history.
class GroupedHistory {
  const GroupedHistory({
    this.today = const [],
    this.yesterday = const [],
    this.thisWeek = const [],
    this.older = const [],
  });

  final List<ConversationSummary> today;
  final List<ConversationSummary> yesterday;
  final List<ConversationSummary> thisWeek;
  final List<ConversationSummary> older;

  bool get isEmpty =>
      today.isEmpty && yesterday.isEmpty && thisWeek.isEmpty && older.isEmpty;
}

/// Partitions [conversations] into Today, Yesterday, This week, and Older.
///
/// [now] is injected so tests can fix the clock. Dates are compared in local
/// time. The week starts on Monday; the app uses the device locale, and this
/// helper keeps the boundary stable for the drawer.
GroupedHistory groupConversations(
  List<ConversationSummary> conversations,
  DateTime now,
) {
  final today = <ConversationSummary>[];
  final yesterday = <ConversationSummary>[];
  final thisWeek = <ConversationSummary>[];
  final older = <ConversationSummary>[];

  final localNow = now.toLocal();
  final todayDate = DateTime(localNow.year, localNow.month, localNow.day);
  final yesterdayDate = todayDate.subtract(const Duration(days: 1));
  final startOfWeek = todayDate.subtract(Duration(days: localNow.weekday - 1));

  for (final conversation in conversations) {
    final updated = conversation.updatedAt.toLocal();
    final updatedDate = DateTime(updated.year, updated.month, updated.day);

    if (updatedDate == todayDate) {
      today.add(conversation);
    } else if (updatedDate == yesterdayDate) {
      yesterday.add(conversation);
    } else if (updatedDate.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
        updatedDate.isBefore(todayDate)) {
      thisWeek.add(conversation);
    } else {
      older.add(conversation);
    }
  }

  return GroupedHistory(
    today: today,
    yesterday: yesterday,
    thisWeek: thisWeek,
    older: older,
  );
}
