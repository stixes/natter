// Database schema for local conversation history.
//
// The generated companion `app_database.g.dart` is committed so a fresh
// checkout analyzes without running codegen. After changing a table or an
// index, regenerate it with:
//
//   dart run build_runner build --delete-conflicting-outputs
//
// See design.md "Generated Drift code is committed".

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// A saved conversation. The id is generated synchronously by the controller
/// when the first turn is sent, so writes never wait on an auto-increment.
@TableIndex(name: 'idx_conversations_updated', columns: {#updatedAt})
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One committed turn. An in-flight draft is never written here.
///
/// [reasoning] is stored for later use and is never rendered. [id] breaks
/// timestamp ties when messages land in the same second.
@TableIndex(name: 'idx_messages_conversation', columns: {#conversationId})
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get reasoning => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Conversations, Messages])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'natter'));

  @override
  int get schemaVersion => 1;
}
