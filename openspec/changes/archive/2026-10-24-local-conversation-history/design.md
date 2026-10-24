# Design

## Context

See proposal.md - Why. The relevant current state:

- `ConversationController` (lib/state/chat_providers.dart) keeps committed messages, the
  in-flight `AssistantDraft`, and a stream error in one in-memory `ConversationState`. It
  commits an assistant turn on normal end or cancel-with-answer-text and drops partials on
  failure. `ChatScreen` renders `state.messages` plus the draft in a `ListView`, and owns the
  composer and the existing error banner.
- `ChatMessage` already carries `reasoning`; its comment anticipates a nullable
  `reasoning_content` column in "the history change" and says reasoning is never rendered.
- The chat screen has no navigation beyond a settings button. There is no conversation id
  in state and no history list.
- AGENTS names Drift (SQLite) as the history home. No database or persistence dependency
  exists yet. The dev image is Flutter 3.29.3 / Dart 3.7.2.
- Flutter 3.29.3's `integration_test` pins `test_api 0.7.4`, which forces the resolver onto
  `test 1.25.15` and `analyzer <8.0.0`. That analyzer bound rules out the Drift 2.30+ line.
- The Android manifest sets no backup policy, so Auto Backup defaults to on.
- The streaming client and SSE parsing are unaffected. The history change must not touch
  the request path or the hand-parsed SSE.

## Goals / Non-Goals

**Goals:**

- Committed turns survive process death and device restarts without leaving the device.
- Restoring and switching conversations is fast enough to feel instant on a phone.
- A failed history write never hides or destroys the conversation currently on screen.
- The storage layer stays behind a repository seam so the controller and widget tests do
  not depend on Drift directly.
- Schema and codegen are set up so later history features (search, export, delete) can be
  added without rewriting the data layer.

**Non-Goals:**

- No search, export, delete, rename, or message editing in this change.
- No cloud sync, account, or backup of history. Auto Backup is disabled, not reconfigured.
- No background streaming: switching away stops the reply instead of moving it to a
  background worker.
- No pagination of very large conversations; load the selected conversation whole.
- No cross-device migration or import.
- No change to the streaming client, SSE parsing, or request headers.

## Decisions

**Use Drift over SQLite, pinned to a Dart 3.7.2-compatible set.**
Drift is the history store AGENTS names, and SQLite gives ordered reads, transactions, and a
future path to search without inventing a storage format. The dev image's Flutter 3.29.3
`integration_test` pins `test_api 0.7.4`, which forces `analyzer <8.0.0`; that rules out the
Drift 2.30+ line, whose `drift_dev` needs `analyzer >=8.1.0`. Resolution therefore pins
`drift 2.29.0`, `drift_dev 2.29.0`, `drift_flutter 0.2.7`, and `build_runner 2.7.1`. The 2.29
line stays on `sqlite3 ^2.6.0` and analyzer 7.x, and `build_runner 2.7.1` is the last release
whose transitive `source_gen` supports Dart 3.7.2. If resolution selects a transitive release
that needs a newer SDK, pin the last compatible release explicitly.
Alternatives: `shared_preferences` JSON (no ordered queries or transactions, and a growing
blob), raw `sqlite3` (manual SQL and no type safety), and Hive/Isar (another dependency and
not the AGENTS-named home). Drift's generated code is the app's first codegen; it stays in
the history data layer, and the streaming path remains hand-parsed SSE.

**Schema: two tables, client-generated conversation ids, auto-increment message ids.**
`conversations` holds `id` (text), `title` (text), `createdAt`, `updatedAt`.
`messages` holds an auto-increment `id`, `conversationId` (FK to conversations with cascade
delete), `role` (text or enum), `content`, nullable `reasoning`, and `createdAt`. A text
conversation id is generated synchronously when a chat starts, so the controller can put it
in state and route writes without waiting for an auto-increment value. Message ids provide a
stable tie-breaker when timestamps collide. Index `messages.conversationId` and
`conversations.updatedAt`; query messages by `createdAt` then `id`, and conversations by
`updatedAt` descending then `id` descending. Reasoning uses the nullable column the
`ChatMessage` comment already anticipates and is never rendered. Alternative: auto-increment
conversation ids; rejected because the id would be unknown until the first write completes,
delaying the stream start or forcing a temporary null id in state.

**Create conversations lazily on the first send.**
A New chat action clears the screen without inserting a row. The first user message creates
the conversation and its title in one transaction. This keeps empty "New chat" rows out of
the history list and means every listed conversation has content. Alternative: create an
empty row on New chat; rejected because empty rows accumulate and need cleanup.

**Persist the user turn before the request starts; persist the assistant turn when it is
committed.**
For the first send, upsert the conversation and insert the user message in a transaction and
await it before calling the endpoint. For later sends, insert the user message and bump
`updatedAt` in a transaction. If the write fails, set a history warning and still start the
request: the user asked for an answer, and the spec keeps the conversation usable. On normal
end, cancel-with-answer-text, or a timeout path that commits already-streamed text, insert
the assistant turn after updating in-memory state so the UI never waits on disk. An
in-flight draft is never written. A mid-reply process death therefore keeps the user turn and
drops the incomplete assistant turn. Alternative: write every streamed token; rejected
because it multiplies I/O for no user-visible benefit and still cannot guarantee the last
token before a kill.

**Restore at startup in `main`, not through an async provider.**
`main` already awaits `profileProvider.notifier.loadStored()`. It will also open the database
and call `conversationProvider.notifier.restoreMostRecent()` before `runApp`, so the first
frame already has the restored conversation. Alternative: an `AsyncNotifier` with a loading
screen; rejected because it adds a spinner to every launch and a state type change for a
single read that is fast on a local database.

**One controller owns the current conversation; switching is a controlled cancel.**
`ConversationState` gains `conversationId` and `historyNotice`. `openConversation(id)` and
`startNewChat()` first cancel any in-flight stream using the existing cancel semantics
(keep answer text as the assistant turn; commit nothing if no answer text arrived), then load
the target or clear. Alternative: keep streaming in the background while the user browses
history; rejected for this slice because it needs a per-conversation controller or a stream
registry, and the product's "instant switching" bar is met by a fast cancel plus local read.

**Titles are local and derived once.**
The controller derives the title from the first user message: trim, collapse whitespace,
truncate to 48 characters with an ellipsis when longer. The title is written with the
conversation row and never recomputed on later messages. No extra request. Alternative: an
AI title request; rejected as a network destination and a scope increase the proposal
excludes. Alternative: no title, just a preview; rejected because the spec asks for a title
and a preview would need a separate query.

**Surface storage failures in a slim, non-retryable banner.**
The existing `error` field remains the retryable stream failure. A new `historyNotice` field
carries save/load failures and renders as a dismissible banner without Retry. A stream Retry
would be wrong for a storage failure because it would re-send the conversation. If the
drawer's conversation stream errors, the drawer shows "History unavailable." instead of an
empty list. Alternative: a SnackBar; rejected because a transient toast can be missed while
the user is reading, and the point is to tell them history was not saved. Alternative: reuse
the error banner with a nullable Retry; rejected because the two failures have different
recovery semantics and the extra boolean would blur them.

**Disable Android Auto Backup for the whole app.**
Set `android:allowBackup="false"` in the main manifest. The app has no cloud story, and the
database is the most sensitive thing it will store. Alternative: a backup rules file that
excludes only the database; rejected because settings would still leave the device and the
product's "no cloud" posture is simpler to honor as a whole-app opt-out. The cost is that
OS backup and device migration no longer carry Natter data; a user who migrates devices
starts fresh. That is the explicit user action the product principle requires.

**Generated Drift code is committed.**
The verification gate is `flutter analyze && flutter test`, so a fresh checkout must analyze
without running codegen. Commit the generated `.g.dart`; run `dart run build_runner build
--delete-conflicting-outputs` only when the schema changes. Alternative: run build_runner as
part of verification; rejected because it slows the gate and makes analysis depend on a code
generator being installed and working.

**Repository seam for tests.**
`ConversationRepository` exposes `watchConversations()`, `loadMostRecent()`,
`loadMessages(id)`, `saveTurn(...)`, and `close()`. Unit tests use `NativeDatabase.memory()`
and the real repository. Controller and widget tests use a fake repository so storage
failures and loading delays are deterministic. Alternative: test the controller against the
real database; rejected because failure injection becomes awkward and tests get slower.

## Risks / Trade-offs

- **Startup loads the whole most recent conversation.** A very long conversation could delay
  the first frame. Mitigation: local SQLite reads are fast; measure on the device round. If
  it is slow, a later change adds pagination without changing the schema or the controller's
  public behavior.
- **The first user turn waits on a database write before the request starts.** That adds a
  few milliseconds to first-token latency. Mitigation: one transaction with two inserts on a
  local file; the device round measures the perceived delay. Alternative: fire-and-forget
  the write; rejected because a kill during the reply would lose the user's message.
- **A storage write failure leaves the conversation in memory only.** The user is warned, but
  the turn is lost on exit. Mitigation: the warning is explicit and non-retryable; a later
  change can add a retry or a "copy conversation" escape hatch. The alternative of blocking
  the chat until storage works would make the app unusable for a disk-full device.
- **Switching away cancels the reply.** A user who browses history mid-answer loses the rest
  of that answer. Mitigation: the already-received text is kept and the spec calls this out;
  background streaming is a named non-goal for a later change.
- **Android tests need a host `libsqlite3` for `NativeDatabase.memory()`.** The devcontainer
  base image may or may not provide it. Mitigation: verify during implementation; if absent,
  add the system package to the devcontainer Dockerfile and document the rebuild. This is a
  dev-environment change, not a product dependency.
- **Exact dependency pins slow future upgrades.** Drift and its analyzer stack move with the
  Dart SDK. Mitigation: the pins are deliberate and documented; a Flutter upgrade is the
  moment to bump them, as already accepted for `flutter_secure_storage`. The analyzer bound
  also comes from `integration_test`'s `test_api` pin, so a Flutter upgrade unblocks Drift
  2.30+ as well. The transitive `sqlite3_flutter_libs` plugin must also build against
  compileSdk 35; verify during implementation and pin the last compatible release if it does
  not.
- **`allowBackup="false"` removes OS backup of settings too.** A user who loses or replaces a
  device starts with no endpoint configuration. Mitigation: this is consistent with the
  local-only product stance; the settings screen is quick to refill. A later change could
  add an explicit export/import flow, which the product's "exportable" history goal already
  anticipates.
- **Drift's generated file and codegen are new to the repo.** A schema change without
  rerunning codegen breaks analysis. Mitigation: commit generated code and name the codegen
  command in the change's tasks and in the database file's header comment.

## Migration Plan

No prior persisted conversation exists. The database opens at schema version 1 and creates
its tables on first launch. If the database file is corrupt or cannot be opened, the app
starts with an empty conversation and a history warning; there is no destructive repair in
this change. Rolling back means removing the database dependency and the drawer; the file
remains on the device but is unread by the app. A later change can add a schema migration
when the tables change.

## Open Questions

None. The switch-mid-stream behavior, title derivation, and backup policy are decided above;
search, export, and delete are named out of scope in the proposal.
