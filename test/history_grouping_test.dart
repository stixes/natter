import 'package:flutter_test/flutter_test.dart';
import 'package:natter/domain/conversation_summary.dart';
import 'package:natter/ui/history_grouping.dart';

void main() {
  group('groupConversations', () {
    final monday = DateTime(2024, 5, 6, 12); // Monday, May 6, 2024
    final wednesday = DateTime(2024, 5, 8, 12); // Wednesday, May 8, 2024

    ConversationSummary summary(String id, DateTime updatedAt) =>
        ConversationSummary(id: id, title: id, updatedAt: updatedAt);

    test('empty list returns empty groups', () {
      final result = groupConversations([], monday);
      expect(result.isEmpty, isTrue);
    });

    test('today, yesterday, this week, and older buckets', () {
      final result = groupConversations([
        summary('today', DateTime(2024, 5, 8, 8)),
        summary('yesterday', DateTime(2024, 5, 7, 8)),
        summary('thisWeek', DateTime(2024, 5, 6, 8)),
        summary('older', DateTime(2024, 5, 4, 8)),
      ], wednesday);

      expect(result.today.map((c) => c.id), ['today']);
      expect(result.yesterday.map((c) => c.id), ['yesterday']);
      expect(result.thisWeek.map((c) => c.id), ['thisWeek']);
      expect(result.older.map((c) => c.id), ['older']);
    });

    test('yesterday overlaps previous week when today is Monday', () {
      final result = groupConversations([
        summary('yesterday', DateTime(2024, 5, 5, 8)), // Sunday
      ], monday);

      expect(result.yesterday.map((c) => c.id), ['yesterday']);
      expect(result.thisWeek, isEmpty);
    });

    test('conversations with identical timestamps keep newest first', () {
      final result = groupConversations([
        summary('a', DateTime(2024, 5, 8, 12)),
        summary('b', DateTime(2024, 5, 8, 12)),
      ], wednesday);

      expect(result.today.map((c) => c.id), ['a', 'b']);
    });

    test('start of week boundary is included in this week', () {
      final result = groupConversations([
        summary('monday', DateTime(2024, 5, 6, 8)),
      ], wednesday);

      expect(result.thisWeek.map((c) => c.id), ['monday']);
    });

    test('empty section stays empty when no conversation falls into it', () {
      final result = groupConversations([
        summary('today', DateTime(2024, 5, 8, 8)),
      ], wednesday);

      expect(result.today.map((c) => c.id), ['today']);
      expect(result.yesterday, isEmpty);
      expect(result.thisWeek, isEmpty);
      expect(result.older, isEmpty);
    });
  });
}
