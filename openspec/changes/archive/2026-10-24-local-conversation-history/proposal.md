# Proposal

## Why

Natter loses every conversation when the app closes. The shipped streaming slice was
deliberately ephemeral to prove the chat path, but "history is sacred" is the product's
second principle: without local history, a chat client cannot be someone's daily driver.
This change replaces the ephemeral-conversation limitation with durable, on-device
history and gives the chat screen a way to move between saved conversations.

## What Changes

- Store conversations and their committed turns in a local SQLite database on the device.
  A user turn is saved when it is sent; an assistant turn is saved when it is committed
  (normal end, cancel with answer text, or a timeout that keeps already-streamed text). An
  in-flight reply draft is never stored.
- Restore the most recent conversation when the app starts. No flash of an empty screen.
- Add a history drawer to the chat screen: saved conversations newest first, tap to open,
  and a New chat action. Starting a new chat leaves earlier conversations stored.
- Title a conversation from its first user message, shortened for the list. No extra
  network request and no AI titling.
- Stop the in-flight reply when the user switches conversations or starts a new chat, and
  keep the answer text already received in the conversation being left.
- Disable Android Auto Backup for app data so conversation history does not leave the
  device through the OS backup service.
- If a history write or read fails, keep the current conversation usable and tell the user
  the turn or conversation was not saved or could not be loaded.

Out of scope: search, export, delete or rename, cloud sync or backup of history, AI-generated
titles, background streaming while the user switches conversations, multiple profiles,
message editing or branching, and history import. This change advances the "history is
sacred" principle and reinforces the no-cloud-sync non-goal; it touches no other product
non-goal.

## Capabilities

### New Capabilities
- `conversation-history`: durable local storage of conversations and turns, the history
  list and switching, conversation titles, on-device backup policy, and storage failure
  behavior.

### Modified Capabilities
- `chat-streaming`: removes the ephemeral-conversation requirement. The conversation is no
  longer memory-only; history owns persistence and restoration.

## Impact

- `pubspec.yaml`: adds `drift` and `drift_flutter` for the local database and its Android
  SQLite connection. Dev dependencies add `drift_dev` and `build_runner` for Drift's table
  code generation. Versions are pinned to releases compatible with the dev image's Flutter
  3.29.3 / Dart 3.7.2. This is the first code generation in the app; it stays confined to
  the history data layer and the streaming path remains hand-parsed SSE.
- New data layer: an `AppDatabase` with conversation and message tables, plus a
  `ConversationRepository` that reads and writes turns. The database lives in the app's
  documents directory and is closed on app disposal. Reasoning is stored in a nullable
  column, matching the forward-looking note in `ChatMessage`, but is never rendered.
- `lib/state/chat_providers.dart`: the conversation controller gains a repository, a
  conversation id, restore and open operations, and persistence at commit points. Drafts
  remain ephemeral. The conversation list is exposed as a reactive provider for the drawer.
- `lib/ui/chat_screen.dart`: adds the drawer, New chat action, conversation selection, and a
  history warning surface. The message list and composer keep their existing behavior.
- `android/app/src/main/AndroidManifest.xml`: sets `android:allowBackup="false"`.
- Tests: repository tests over an in-memory database, controller tests with a fake
  repository, widget tests for the drawer and restore path, and a manifest check for the
  backup setting. An on-device round confirms persistence across a force-stop.
- No new permissions. The only network destination remains the configured endpoint; history
  operations never contact the network.
- Changelog: a user-facing entry saying conversations now survive closing the app and can be
  reopened from a history list, and that history stays on the device.
