import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_completions_client.dart';
import '../data/key_value_store.dart';
import '../data/profile_repository.dart';
import '../domain/assistant_draft.dart';
import '../domain/chat_message.dart';
import '../domain/endpoint_profile.dart';
import '../domain/stream_delta.dart';

/// Plain settings location for base URL and model. Not persisted across
/// restarts in this change; the profiles change decides the durable home.
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

final chatStreamServiceProvider = Provider<ChatStreamService>(
  (ref) => ChatCompletionsClient(),
);

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
    this.messages = const [],
    this.draft,
    this.error,
  });

  final List<ChatMessage> messages;

  /// The reply currently streaming; null when nothing is in flight.
  final AssistantDraft? draft;

  /// A surfaced stream failure; null when the last attempt did not fail.
  final String? error;

  bool get isStreaming => draft != null;

  ConversationState copy({
    List<ChatMessage>? messages,
    AssistantDraft? draft,
    String? error,
  }) => ConversationState(
    messages: messages ?? this.messages,
    draft: draft ?? this.draft,
    error: error ?? this.error,
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

  /// Sends [text] as a user turn and streams the reply.
  void send(String text) {
    if (state.isStreaming) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final profile = ref.read(profileProvider);
    final messages = [
      ...state.messages,
      ChatMessage(role: ChatRole.user, content: trimmed),
    ];
    if (!profile.isConfigured) {
      state = ConversationState(
        messages: messages,
        error: 'Set a base URL, API key, and model in Settings first.',
      );
      return;
    }
    _start(profile, messages);
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
    state = ConversationState(
      messages: partial.isEmpty
          ? state.messages
          : [
              ...state.messages,
              ChatMessage(
                role: ChatRole.assistant,
                content: partial,
                reasoning: draft.reasoning,
              ),
            ],
    );
  }

  /// Clears a surfaced error without changing the conversation.
  void dismissError() {
    if (state.error == null) return;
    state = ConversationState(messages: state.messages);
  }

  void _start(EndpointProfile profile, List<ChatMessage> messages) {
    _stop();
    final draft = AssistantDraft();
    state = ConversationState(messages: messages, draft: draft);

    _subscription = _service(profile, messages).listen(
      (delta) {
        if (state.draft != draft) return; // cancelled or already settled
        draft.apply(delta);
        state = ConversationState(messages: messages, draft: draft);
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
    state = ConversationState(
      messages: content.isEmpty
          ? messages
          : [
              ...messages,
              ChatMessage(
                role: ChatRole.assistant,
                content: content,
                reasoning: draft.reasoning,
              ),
            ],
    );
  }

  /// Mid-stream or request failure: drop the partial attempt, keep prior
  /// messages exactly as they were, and surface the failure for retry.
  void _fail(List<ChatMessage> messages, Object error) {
    _subscription = null;
    if (state.draft == null) return; // cancelled, or an error after onDone
    state = ConversationState(
      messages: messages,
      error: error is ChatRequestFailure ? error.message : 'Request failed.',
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
