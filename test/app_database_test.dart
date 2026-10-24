import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/app_database.dart';

void main() {
  group('AppDatabase schema', () {
    late AppDatabase database;

    setUp(() {
      // An in-memory database keeps the schema test off the device file
      // system and the path_provider plugin channel.
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('creates the conversation and message tables with their indexes',
        () async {
      final rows = await database.customSelect(
        "SELECT type, name FROM sqlite_master "
        "WHERE type IN ('table', 'index') AND name NOT LIKE 'sqlite_%' "
        'ORDER BY type, name',
      ).get();

      final tables = rows
          .where((row) => row.read<String>('type') == 'table')
          .map((row) => row.read<String>('name'))
          .toSet();
      final indexes = rows
          .where((row) => row.read<String>('type') == 'index')
          .map((row) => row.read<String>('name'))
          .toSet();

      expect(tables, containsAll(['conversations', 'messages']));
      expect(
        indexes,
        containsAll([
          'idx_conversations_updated',
          'idx_messages_conversation',
        ]),
      );
    });
  });
}
