import 'package:drift/drift.dart';

import '../domain/chat_message.dart';
import '../domain/conversation_summary.dart';
import 'app_database.dart';

/// Reads and writes committed conversation turns in [AppDatabase].
///
/// The controller owns the in-memory conversation; this repository owns the
/// on-device storage seam. An in-flight draft is never written here.
class ConversationRepository {
  ConversationRepository(this._database);

  final AppDatabase _database;

  /// Saves one committed turn.
  ///
  /// A single transaction upserts the conversation and appends [message]. When
  /// the conversation row is first created, [title] is written with it; later
  /// turns bump `updatedAt` and leave the title alone. [at] makes ordering
  /// deterministic in tests; production callers leave it null and use now.
  Future<void> saveTurn({
    required String conversationId,
    required ChatMessage message,
    String? title,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    await _database.transaction(() async {
      final existing = await (_database.select(_database.conversations)
            ..where((row) => row.id.equals(conversationId)))
          .getSingleOrNull();
      if (existing == null) {
        await _database.into(_database.conversations).insert(
          ConversationsCompanion.insert(
            id: conversationId,
            title: title ?? '',
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        await (_database.update(_database.conversations)
              ..where((row) => row.id.equals(conversationId)))
            .write(ConversationsCompanion(updatedAt: Value(now)));
      }
      await _database.into(_database.messages).insert(
        MessagesCompanion.insert(
          conversationId: conversationId,
          role: message.roleWireName,
          content: message.content,
          reasoning: Value(
            message.reasoning.isEmpty ? null : message.reasoning,
          ),
          createdAt: now,
        ),
      );
    });
  }

  /// Saved conversations newest first, updating as the database changes.
  Stream<List<ConversationSummary>> watchConversations() {
    final query = _database.select(_database.conversations)
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(_summaryOf).toList(growable: false),
    );
  }

  /// Permanently deletes conversations whose last update is older than [cutoff].
  ///
  /// Messages are removed first because the generated database does not enable
  /// foreign-key cascade. The whole deletion runs in one transaction so a
  /// failure leaves the database unchanged. Returns the number of conversations
  /// deleted.
  Future<int> deleteExpiredBefore(DateTime cutoff) async {
    return _database.transaction(() async {
      final expired = await (_database.select(_database.conversations)
            ..where((row) => row.updatedAt.isSmallerThanValue(cutoff)))
          .get();
      if (expired.isEmpty) return 0;
      final ids = expired.map((conversation) => conversation.id).toList();
      await (_database.delete(_database.messages)
            ..where((row) => row.conversationId.isIn(ids)))
          .go();
      return (_database.delete(_database.conversations)
            ..where((row) => row.id.isIn(ids)))
          .go();
    });
  }

  /// The most recently updated conversation, or null when history is empty.
  Future<ConversationSummary?> loadMostRecent() async {
    final row = await (_database.select(_database.conversations)
          ..orderBy([
            (row) => OrderingTerm.desc(row.updatedAt),
            (row) => OrderingTerm.desc(row.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _summaryOf(row);
  }

  /// Committed turns for [conversationId], oldest first.
  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    final rows = await (_database.select(_database.messages)
          ..where((row) => row.conversationId.equals(conversationId))
          ..orderBy([
            (row) => OrderingTerm.asc(row.createdAt),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
    return rows
        .map(
          (row) => ChatMessage(
            role: row.role == ChatRole.assistant.name
                ? ChatRole.assistant
                : ChatRole.user,
            content: row.content,
            reasoning: row.reasoning ?? '',
            createdAt: row.createdAt,
          ),
        )
        .toList(growable: false);
  }

  /// Closes the underlying database.
  Future<void> close() => _database.close();

  ConversationSummary _summaryOf(Conversation row) => ConversationSummary(
    id: row.id,
    title: row.title,
    updatedAt: row.updatedAt,
  );
}
