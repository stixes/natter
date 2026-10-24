import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/data/conversation_repository.dart';
import 'package:natter/data/key_value_store.dart';
import 'package:natter/domain/chat_message.dart';
import 'package:natter/domain/conversation_summary.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/stream_delta.dart';
import 'package:natter/state/chat_providers.dart';

class RecordedRequest {
  RecordedRequest(this.profile, this.messages);

  final EndpointProfile profile;
  final List<ChatMessage> messages;
}

/// Drives a reply stream by hand so cancel / error / retry / blank-answer
/// tests are deterministic.
class ScriptedChatService implements ChatStreamService {
  final requests = <RecordedRequest>[];
  final _controllers = <StreamController<StreamDelta>>[];

  @override
  Stream<StreamDelta> stream({
    required EndpointProfile profile,
    required List<ChatMessage> messages,
  }) {
    requests.add(RecordedRequest(profile, List.of(messages)));
    final controller = StreamController<StreamDelta>();
    _controllers.add(controller);
    return controller.stream;
  }

  void emit(int attempt, List<StreamDelta> deltas) {
    for (final delta in deltas) {
      _controllers[attempt].add(delta);
    }
  }

  void end(int attempt) {
    _controllers[attempt].close();
  }

  void fail(int attempt, Object error) {
    _controllers[attempt]
      ..addError(error)
      ..close();
  }
}

class SavedTurn {
  const SavedTurn({
    required this.conversationId,
    required this.message,
    this.title,
  });

  final String conversationId;
  final ChatMessage message;
  final String? title;
}

/// A deterministic repository seam for controller and widget tests.
///
/// Set [loadError] or [saveError] to inject a storage failure; set
/// [conversations] and [messages] to simulate saved history.
class FakeConversationRepository implements ConversationRepository {
  FakeConversationRepository({
    List<ConversationSummary>? conversations,
    Map<String, List<ChatMessage>>? messagesByConversation,
    List<ChatMessage>? messages,
  })  : _conversations = List.of(conversations ?? const []),
        _messagesByConversation = {
          for (final entry in (messagesByConversation ?? const {}).entries)
            entry.key: List.of(entry.value),
        },
        _messages = List.of(messages ?? const []);

  final List<ConversationSummary> _conversations;
  final Map<String, List<ChatMessage>> _messagesByConversation;
  final List<ChatMessage> _messages;
  final savedTurns = <SavedTurn>[];
  Object? loadError;
  Object? saveError;
  Object? watchError;
  final _watches = StreamController<List<ConversationSummary>>.broadcast();

  List<ConversationSummary> get _ordered {
    final ordered = List.of(_conversations)
      ..sort((a, b) {
        final byUpdated = b.updatedAt.compareTo(a.updatedAt);
        return byUpdated != 0 ? byUpdated : b.id.compareTo(a.id);
      });
    return ordered;
  }

  @override
  Stream<List<ConversationSummary>> watchConversations() async* {
    if (watchError != null) throw watchError!;
    yield _ordered;
    yield* _watches.stream;
  }

  @override
  Future<ConversationSummary?> loadMostRecent() async {
    if (loadError != null) throw loadError!;
    final ordered = _ordered;
    return ordered.isEmpty ? null : ordered.first;
  }

  @override
  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    if (loadError != null) throw loadError!;
    final preloaded = _messagesByConversation[conversationId];
    return List.of(preloaded ?? _messages);
  }

  @override
  Future<void> saveTurn({
    required String conversationId,
    required ChatMessage message,
    String? title,
    DateTime? at,
  }) async {
    if (saveError != null) throw saveError!;
    savedTurns.add(
      SavedTurn(conversationId: conversationId, message: message, title: title),
    );
    _messages.add(message);
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    final summary = ConversationSummary(
      id: conversationId,
      title: index >= 0 ? _conversations[index].title : (title ?? ''),
      updatedAt: at ?? DateTime.now(),
    );
    if (index >= 0) {
      _conversations[index] = summary;
    } else {
      _conversations.add(summary);
    }
    _watches.add(_ordered);
  }

  @override
  Future<void> close() async {
    if (!_watches.isClosed) {
      await _watches.close();
    }
  }
}

const testProfile = EndpointProfile(
  baseUrl: 'http://127.0.0.1:8080/v1',
  apiKey: 'sk-test-secret-value',
  model: 'qwen3-test',
);

/// A container wired for tests: scripted stream plus inspectable stores.
({ProviderContainer container, ScriptedChatService service, KeyValueStore settings, KeyValueStore secrets, FakeConversationRepository repository})
    createTestContainer({FakeConversationRepository? repository}) {
  final service = ScriptedChatService();
  final settings = InMemoryKeyValueStore();
  final secrets = InMemoryKeyValueStore();
  final repo = repository ?? FakeConversationRepository();
  final container = ProviderContainer(
    overrides: [
      chatStreamServiceProvider.overrideWith((ref) => service),
      settingsStoreProvider.overrideWith((ref) => settings),
      secretStoreProvider.overrideWith((ref) => secrets),
      conversationRepositoryProvider.overrideWith((ref) => repo),
    ],
  );
  // Register repo.close before container.dispose: addTearDown runs in reverse
  // order, and closing the fake's stream while the provider still listens can
  // deadlock on the broadcast controller's close future.
  addTearDown(repo.close);
  addTearDown(container.dispose);
  return (
    container: container,
    service: service,
    settings: settings,
    secrets: secrets,
    repository: repo,
  );
}

/// Lets a test wait for the microtask/stream delivery that follows a manual
/// emit, without a real timer.
Future<void> settle() => Future<void>.delayed(Duration.zero);
