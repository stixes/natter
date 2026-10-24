import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/assistant_draft.dart';
import '../domain/chat_message.dart';
import '../domain/endpoint_profile.dart';
import '../state/chat_providers.dart';
import 'message_bubble.dart';
import 'settings_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    ref.read(conversationProvider.notifier).send(text);
    _input.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(conversationProvider);
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(conversationProvider.notifier);
    final theme = Theme.of(context);

    final messages = conversation.messages;
    final draft = conversation.draft;
    final rowCount = messages.length + (draft == null ? 0 : 1);

    _scrollToBottom();

    return Scaffold(
      drawer: const _HistoryDrawer(),
      appBar: AppBar(
        title: const Text('Natter'),
        actions: [
          IconButton(
            tooltip: 'Endpoint',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: rowCount == 0
                  ? _EmptyState(profile: profile)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: rowCount,
                      itemBuilder: (context, index) {
                        if (index < messages.length) {
                          final message = messages[index];
                          return MessageBubble(
                            content: message.content,
                            isMine: message.role == ChatRole.user,
                          );
                        }
                        return _DraftBubble(draft: draft!);
                      },
                    ),
            ),
            if (conversation.error != null)
              _ErrorBanner(
                message: conversation.error!,
                onRetry: notifier.retry,
                onDismiss: notifier.dismissError,
              ),
            if (conversation.historyNotice != null)
              _HistoryNoticeBanner(
                message: conversation.historyNotice!,
                onDismiss: notifier.dismissHistoryNotice,
              ),
            _Composer(
              controller: _input,
              isStreaming: conversation.isStreaming,
              canSend: profile.isConfigured,
              onSend: _send,
              onCancel: notifier.cancel,
            ),
            if (!profile.isConfigured)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'No endpoint configured. Open Settings to set a base URL '
                  'and model.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.disabledColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDrawer extends ConsumerWidget {
  const _HistoryDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListProvider);
    final notifier = ref.read(conversationProvider.notifier);
    // Riverpod retries a failing stream automatically, so the state can be
    // AsyncLoading with an error attached. Treat any error as unavailable.
    final unavailable = conversations.hasError;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('New chat'),
              onTap: () {
                Navigator.of(context).pop();
                notifier.startNewChat();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: unavailable
                  ? const Center(child: Text('History unavailable.'))
                  : conversations.when(
                      data: (items) {
                        if (items.isEmpty) {
                          return const Center(
                            child: Text('No conversations yet.'),
                          );
                        }
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final summary = items[index];
                            return ListTile(
                              title: Text(summary.title),
                              onTap: () {
                                Navigator.of(context).pop();
                                notifier.openConversation(summary.id);
                              },
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: Text('Loading...'),
                      ),
                      error: (error, stack) => const Center(
                        child: Text('History unavailable.'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.profile});

  final EndpointProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 40,
              color: theme.disabledColor,
            ),
            const SizedBox(height: 12),
            Text(
              profile.isConfigured
                  ? 'Say something.'
                  : 'Point Natter at an OpenAI-compatible endpoint.',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The in-flight reply: placeholder while waiting or thinking, streamed plain
/// text once answer tokens arrive.
class _DraftBubble extends StatelessWidget {
  const _DraftBubble({required this.draft});

  final AssistantDraft draft;

  @override
  Widget build(BuildContext context) {
    final label = switch (draft.phase) {
      AssistantPhase.thinking => 'Thinking',
      AssistantPhase.waiting => 'Waiting',
      AssistantPhase.answering => null,
    };
    return MessageBubble(
      content: draft.visibleText,
      isMine: false,
      placeholderLabel: label,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// A storage failure warning: no Retry, because retrying a save would re-send
/// the conversation. The turn stays visible; the notice only reports.
class _HistoryNoticeBanner extends StatelessWidget {
  const _HistoryNoticeBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onTertiaryContainer),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isStreaming,
    required this.canSend,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Message',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (isStreaming)
            IconButton(
              tooltip: 'Stop',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: onCancel,
            )
          else
            IconButton(
              tooltip: 'Send',
              icon: const Icon(Icons.arrow_upward),
              onPressed: canSend ? onSend : null,
            ),
        ],
      ),
    );
  }
}
