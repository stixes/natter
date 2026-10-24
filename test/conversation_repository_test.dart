import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/app_database.dart';
import 'package:natter/data/conversation_repository.dart';
import 'package:natter/domain/chat_message.dart';

void main() {
  group('ConversationRepository', () {
    late AppDatabase database;
    late ConversationRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = ConversationRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('saves a first user turn with the title and one message', () async {
      await repository.saveTurn(
        conversationId: 'conversation-1',
        title: 'Hello there',
        message: const ChatMessage(
          role: ChatRole.user,
          content: 'Hello there',
        ),
      );

      final conversations = await database.select(database.conversations).get();
      expect(conversations, hasLength(1));
      expect(conversations.single.id, 'conversation-1');
      expect(conversations.single.title, 'Hello there');
      expect(conversations.single.createdAt, conversations.single.updatedAt);

      final messages = await database.select(database.messages).get();
      expect(messages, hasLength(1));
      expect(messages.single.conversationId, 'conversation-1');
      expect(messages.single.role, 'user');
      expect(messages.single.content, 'Hello there');
      expect(messages.single.reasoning, isNull);
    });

    test('an empty history has no conversations', () async {
      expect(await repository.loadMostRecent(), isNull);
      expect(await repository.watchConversations().first, isEmpty);
      expect(await repository.loadMessages('missing'), isEmpty);
    });

    test('lists conversations newest first and bumps the updated one',
        () async {
      await repository.saveTurn(
        conversationId: 'a',
        title: 'Conversation A',
        message: const ChatMessage(role: ChatRole.user, content: 'first'),
        at: DateTime(2024, 1, 1, 12),
      );
      await repository.saveTurn(
        conversationId: 'b',
        title: 'Conversation B',
        message: const ChatMessage(role: ChatRole.user, content: 'second'),
        at: DateTime(2024, 1, 2, 12),
      );

      var conversations = await repository.watchConversations().first;
      expect(conversations.map((c) => c.id).toList(), ['b', 'a']);
      expect((await repository.loadMostRecent())?.id, 'b');

      // A later turn on A bumps it above B and leaves its title alone.
      await repository.saveTurn(
        conversationId: 'a',
        message: const ChatMessage(role: ChatRole.assistant, content: 'reply'),
        at: DateTime(2024, 1, 3, 12),
      );

      conversations = await repository.watchConversations().first;
      expect(conversations.map((c) => c.id).toList(), ['a', 'b']);
      expect((await repository.loadMostRecent())?.id, 'a');
      expect(conversations.first.title, 'Conversation A');
    });

    test('orders messages by creation time then id', () async {
      await repository.saveTurn(
        conversationId: 'c',
        title: 'Conversation C',
        message: const ChatMessage(role: ChatRole.user, content: 'first'),
        at: DateTime(2024, 1, 1, 12),
      );
      await repository.saveTurn(
        conversationId: 'c',
        message: const ChatMessage(role: ChatRole.assistant, content: 'second'),
        at: DateTime(2024, 1, 2, 12),
      );
      await repository.saveTurn(
        conversationId: 'c',
        message: const ChatMessage(role: ChatRole.user, content: 'third'),
        at: DateTime(2024, 1, 3, 12),
      );

      final messages = await repository.loadMessages('c');
      expect(messages.map((m) => m.content).toList(), [
        'first',
        'second',
        'third',
      ]);
    });

    test('breaks a creation-time tie by message id', () async {
      final sameMoment = DateTime(2024, 1, 1, 12);
      await repository.saveTurn(
        conversationId: 'd',
        title: 'Conversation D',
        message: const ChatMessage(role: ChatRole.user, content: 'one'),
        at: sameMoment,
      );
      await repository.saveTurn(
        conversationId: 'd',
        message: const ChatMessage(role: ChatRole.user, content: 'two'),
        at: sameMoment,
      );

      final messages = await repository.loadMessages('d');
      expect(messages.map((m) => m.content).toList(), ['one', 'two']);
    });

    test('round-trips reasoning from the nullable column', () async {
      await repository.saveTurn(
        conversationId: 'e',
        title: 'Conversation E',
        message: const ChatMessage(role: ChatRole.user, content: 'question'),
      );
      await repository.saveTurn(
        conversationId: 'e',
        message: const ChatMessage(
          role: ChatRole.assistant,
          content: 'answer',
          reasoning: 'hidden chain of thought',
        ),
      );

      final messages = await repository.loadMessages('e');
      expect(messages, hasLength(2));
      expect(messages[0].reasoning, isEmpty);
      expect(messages[1].reasoning, 'hidden chain of thought');

      final rows = await database.select(database.messages).get();
      expect(rows[0].reasoning, isNull);
      expect(rows[1].reasoning, 'hidden chain of thought');
    });

    test('a user-only turn leaves no assistant message', () async {
      await repository.saveTurn(
        conversationId: 'f',
        title: 'Conversation F',
        message: const ChatMessage(role: ChatRole.user, content: 'only turn'),
      );

      final messages = await repository.loadMessages('f');
      expect(messages, hasLength(1));
      expect(messages.single.role, ChatRole.user);
      expect(messages.single.content, 'only turn');
    });

    test('a save after close surfaces an exception instead of a silent no-op',
        () async {
      // Open the database first so close() has a live connection to close.
      await repository.loadMostRecent();
      await repository.close();

      await expectLater(
        repository.saveTurn(
          conversationId: 'closed',
          title: 'Closed',
          message: const ChatMessage(role: ChatRole.user, content: 'hello'),
        ),
        throwsA(anything),
      );
    });
  });
}
