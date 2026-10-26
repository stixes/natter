import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/chat_completions_client.dart';
import '../data/conversation_repository.dart';
import '../data/key_value_store.dart';
import '../data/profile_repository.dart';
import '../domain/assistant_draft.dart';
import '../domain/chat_message.dart';
import '../domain/conversation_summary.dart';
import '../domain/endpoint_profile.dart';
import '../domain/stream_delta.dart';

/// Plain settings location for base URL and model. Production overrides this
/// with the durable [SharedPreferencesKeyValueStore]; the in-memory default
/// keeps widget and unit tests off the plugin channel.
final settingsStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

/// Keystore-backed location. The API key only ever reaches this store.
final secretStoreProvider = Provider<KeyValueStore>(
  (ref) => SecureKeyValueStore(),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(
    settings: ref.watch(settingsStoreProvider),
    secrets: ref.watch(secretStoreProvider),
  ),
);

/// The local conversation-history database. Disposed with the provider scope.
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// The storage seam the controller reads and writes committed turns through.
final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => ConversationRepository(ref.watch(databaseProvider)),
);

/// The saved conversations as a reactive list for the history drawer.
///
/// Retry is disabled: a local database read either works or reports a storage
/// failure, and the drawer surfaces that failure as "History unavailable."
/// rather than silently retrying behind a loading state.
final conversationListProvider =
    StreamProvider<List<ConversationSummary>>(
      (ref) => ref.watch(conversationRepositoryProvider).watchConversations(),
      retry: (retryCount, error) => null,
    );

final chatStreamServiceProvider = Provider<ChatStreamService>((ref) {
  final client = ChatCompletionsClient();
  ref.onDispose(client.close);
  return client;
});

/// The single endpoint config, shaped as a one-profile state so the profiles
/// change generalizes it. Chat requests read base URL / key / model from here.
class ProfileController extends Notifier<EndpointProfile> {
  @override
  EndpointProfile build() => const EndpointProfile();

  /// Restores what was stored: URL/model from plain settings, key from secure
  /// storage.
  Future<void> loadStored() async {
    state = await ref.read(profileRepositoryProvider).load();
  }

  Future<void> save(EndpointProfile profile) async {
    state = profile;
    await ref.read(profileRepositoryProvider).save(profile);
  }
}

final profileProvider = NotifierProvider<ProfileController, EndpointProfile>(
  ProfileController.new,
);

/// The in-flight assistant reply plus everything the chat screen needs to
/// know: committed messages, the draft, and any surfaced stream failure.
///
/// The draft is mutable so token delivery stays O(1); each delivery pushes a
/// fresh [ConversationState] so listeners rebuild.
class ConversationState {
  const ConversationState({
    this.conversationId,
    this.messages = const [],
    this.draft,
    this.error,
    this.historyNotice,
  });

  /// The saved conversation this state belongs to; null for a new chat.
  final String? conversationId;

  final List<ChatMessage> messages;

  /// The reply currently streaming; null when nothing is in flight.
  final AssistantDraft? draft;

  /// A surfaced stream failure; null when the last attempt did not fail.
  final String? error;

  /// A surfaced history save/load failure; null when there is none.
  final String? historyNotice;

  bool get isStreaming => draft != null;

  ConversationState copy({
    String? conversationId,
    List<ChatMessage>? messages,
    AssistantDraft? draft,
    String? error,
    String? historyNotice,
  }) => ConversationState(
    conversationId: conversationId ?? this.conversationId,
    messages: messages ?? this.messages,
    draft: draft ?? this.draft,
    error: error ?? this.error,
    historyNotice: historyNotice ?? this.historyNotice,
  );
}

/// Ephemeral conversation: lives only in memory for this session. No
/// persistence in this change; the history change owns storage.
class ConversationController extends Notifier<ConversationState> {
  StreamSubscription<StreamDelta>? _subscription;

  @override
  ConversationState build() {
    ref.onDispose(_stop);
    return const ConversationState();
  }

  ConversationRepository get _repository =>
      ref.read(conversationRepositoryProvider);

  /// Restores the most recent saved conversation, if any.
  ///
  /// A read failure leaves the conversation empty and surfaces a dismissible
  /// [ConversationState.historyNotice] so the screen stays usable.
  Future<void> restoreMostRecent() async {
    try {
      final summary = await _repository.loadMostRecent();
      if (summary == null) return;
      final messages = await _repository.loadMessages(summary.id);
      state = ConversationState(
        conversationId: summary.id,
        messages: messages,
      );
    } catch (_) {
      state = const ConversationState(
        historyNotice: 'History could not be loaded.',
      );
    }
  }

  static int _sequence = 0;
  static const _titleLimit = 48;

  /// Sends [text] as a user turn and streams the reply.
  ///
  /// The user turn is saved before the request starts. A save failure leaves
  /// the turn on screen, surfaces [ConversationState.historyNotice], and still
  /// starts the request so the user gets an answer.
  Future<void> send(String text) async {
    if (state.isStreaming) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final profile = ref.read(profileProvider);
    final userTurn = ChatMessage(
      role: ChatRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    final messages = [...state.messages, userTurn];
    final conversationId = state.conversationId ?? _newConversationId();
    final title = _titleFor(messages);

    // Show the user turn immediately; the storage write happens behind it.
    state = ConversationState(
      conversationId: conversationId,
      messages: messages,
      historyNotice: state.historyNotice,
    );

    try {
      await _repository.saveTurn(
        conversationId: conversationId,
        message: userTurn,
        title: title,
        at: userTurn.createdAt,
      );
    } catch (_) {
      state = state.copy(historyNotice: 'This turn was not saved to history.');
    }

    if (!profile.isConfigured) {
      state = state.copy(
        error: 'Set a base URL, API key, and model in Settings first.',
      );
      return;
    }

    _start(profile, messages);
  }

  String _newConversationId() =>
      'c_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  String? _titleFor(List<ChatMessage> messages) {
    final firstUser = messages.firstWhere(
      (message) => message.role == ChatRole.user,
      orElse: () => messages.first,
    );
    final collapsed = firstUser.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return null;
    return collapsed.length <= _titleLimit
        ? collapsed
        : '${collapsed.substring(0, _titleLimit)}…';
  }

  /// Re-sends the existing conversation. The failed attempt left no assistant
  /// turn behind, so the request ends on the user message that failed.
  void retry() {
    if (state.isStreaming) return;
    if (state.messages.isEmpty) return;
    final profile = ref.read(profileProvider);
    if (!profile.isConfigured) {
      state = state.copy(error: 'Set a base URL, API key, and model first.');
      return;
    }
    _start(profile, state.messages);
  }

  /// Cancels the in-flight stream. Whatever answer text already arrived is
  /// kept; the conversation stays well-formed and sendable.
  void cancel() {
    final draft = state.draft;
    if (draft == null) return;
    _stop();
    final partial = draft.answer;
    final assistant = partial.isEmpty
        ? null
        : ChatMessage(
            role: ChatRole.assistant,
            content: partial,
            reasoning: draft.reasoning,
            createdAt: DateTime.now(),
          );
    final conversationId = state.conversationId;
    state = ConversationState(
      conversationId: conversationId,
      messages: assistant == null
          ? state.messages
          : [...state.messages, assistant],
      historyNotice: state.historyNotice,
    );
    if (assistant != null) {
      _persistAssistant(conversationId, assistant);
    }
  }

  /// Clears the screen for a new conversation without creating a row.
  ///
  /// Any in-flight reply is cancelled with the usual semantics: already-
  /// received answer text stays in the conversation being left. The first
  /// send creates the new conversation.
  void startNewChat() {
    cancel();
    state = ConversationState(historyNotice: state.historyNotice);
  }

  /// Opens a saved conversation, replacing the current one.
  ///
  /// Any in-flight reply is cancelled with the usual semantics: already-
  /// received answer text stays in the conversation being left. The target's
  /// stored turns are then loaded; a load failure leaves the current
  /// conversation usable and surfaces a dismissible history notice.
  Future<void> openConversation(String conversationId) async {
    cancel();
    final current = state;
    try {
      final messages = await _repository.loadMessages(conversationId);
      state = ConversationState(
        conversationId: conversationId,
        messages: messages,
        historyNotice: current.historyNotice,
      );
    } catch (_) {
      state = current.copy(
        historyNotice: 'The selected conversation could not be loaded.',
      );
    }
  }

  /// Clears the history notice without changing the conversation.
  void dismissHistoryNotice() {
    if (state.historyNotice == null) return;
    state = ConversationState(
      conversationId: state.conversationId,
      messages: state.messages,
      draft: state.draft,
      error: state.error,
    );
  }

  /// Clears a surfaced error without changing the conversation.
  void dismissError() {
    if (state.error == null) return;
    state = ConversationState(
      conversationId: state.conversationId,
      messages: state.messages,
      historyNotice: state.historyNotice,
    );
  }

  void _start(EndpointProfile profile, List<ChatMessage> messages) {
    _stop();
    final draft = AssistantDraft();
    state = ConversationState(
      conversationId: state.conversationId,
      messages: messages,
      draft: draft,
      historyNotice: state.historyNotice,
    );

    _subscription = _service(profile, messages).listen(
      (delta) {
        if (state.draft != draft) return; // cancelled or already settled
        draft.apply(delta);
        state = ConversationState(
          conversationId: state.conversationId,
          messages: messages,
          draft: draft,
          historyNotice: state.historyNotice,
        );
      },
      onError: (Object error) => _fail(messages, error),
      onDone: () => _complete(messages, draft),
    );
  }

  Stream<StreamDelta> _service(
    EndpointProfile profile,
    List<ChatMessage> messages,
  ) => ref.read(chatStreamServiceProvider).stream(
    profile: profile,
    messages: messages,
  );

  /// Normal end of stream: commit the answer, applying the blank-answer
  /// fallback when everything landed in reasoning.
  void _complete(List<ChatMessage> messages, AssistantDraft draft) {
    _subscription = null;
    // A cancelled or failed attempt must not commit after the fact.
    if (state.draft != draft) return;
    final content = draft.resolveFinalContent();
    final assistant = content.isEmpty
        ? null
        : ChatMessage(
            role: ChatRole.assistant,
            content: content,
            reasoning: draft.reasoning,
            createdAt: DateTime.now(),
          );
    final conversationId = state.conversationId;
    state = ConversationState(
      conversationId: conversationId,
      messages: assistant == null ? messages : [...messages, assistant],
      historyNotice: state.historyNotice,
    );
    if (assistant != null) {
      _persistAssistant(conversationId, assistant);
    }
  }

  /// Writes one committed assistant turn without making the UI wait on disk.
  ///
  /// A save failure surfaces a dismissible [ConversationState.historyNotice]
  /// and leaves the turn visible in the in-memory conversation.
  Future<void> _persistAssistant(
    String? conversationId,
    ChatMessage message,
  ) async {
    if (conversationId == null) return;
    try {
      await _repository.saveTurn(
        conversationId: conversationId,
        message: message,
        at: message.createdAt,
      );
    } catch (_) {
      state = state.copy(historyNotice: 'This turn was not saved to history.');
    }
  }

  /// Mid-stream or request failure: drop the partial attempt, keep prior
  /// messages exactly as they were, and surface the failure for retry.
  void _fail(List<ChatMessage> messages, Object error) {
    _subscription = null;
    final draft = state.draft;
    if (draft == null) return; // cancelled, or an error after onDone

    if (error is ChatRequestFailure &&
        error.isSilenceFailure &&
        draft.hasAnswerText) {
      // The user watched this text arrive; a silence expiry must not also
      // destroy it. Commit it the way cancel does, then surface the failure.
      final assistant = ChatMessage(
        role: ChatRole.assistant,
        content: draft.answer,
        reasoning: draft.reasoning,
        createdAt: DateTime.now(),
      );
      final conversationId = state.conversationId;
      state = ConversationState(
        conversationId: conversationId,
        messages: [...messages, assistant],
        error: error.message,
        historyNotice: state.historyNotice,
      );
      _persistAssistant(conversationId, assistant);
      return;
    }

    state = ConversationState(
      conversationId: state.conversationId,
      messages: messages,
      error: error is ChatRequestFailure ? error.message : 'Request failed.',
      historyNotice: state.historyNotice,
    );
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}

final conversationProvider =
    NotifierProvider<ConversationController, ConversationState>(
      ConversationController.new,
    );
