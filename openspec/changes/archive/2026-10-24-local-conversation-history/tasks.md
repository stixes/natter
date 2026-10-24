# Tasks

## 1. Dependencies and database scaffold

- [x] 1.1 Add `drift 2.29.0`, `drift_flutter 0.2.7`, and dev dependencies `drift_dev 2.29.0` and `build_runner 2.7.1` to `pubspec.yaml`, then run `flutter pub get`; verify the lock file resolves under Flutter 3.29.3 / Dart 3.7.2 and that no added package or transitive dependency requires a newer Dart SDK. The design's original 2.31.0/0.2.8/2.15.0 pins cannot resolve because Flutter 3.29.3's `integration_test` pins `test_api 0.7.4`, forcing `analyzer <8.0.0` while `drift_dev 2.31.0` needs `analyzer >=8.1.0`; the 2.29.0 line and `build_runner 2.7.1` are the last releases compatible with that bound.
- [x] 1.2 Define the conversation and message tables in a new `lib/data/app_database.dart` with schema version 1, the message foreign key and the two indexes; run `dart run build_runner build --delete-conflicting-outputs`; verify the generated file exists, `flutter analyze` passes, and the generated file is committed with the schema.
- [x] 1.3 Add a database test that opens `NativeDatabase.memory()` and verifies the two tables and indexes exist; verify `flutter test` passes, and if the devcontainer lacks `libsqlite3`, add the system package to `.devcontainer/Dockerfile` and document the rebuild.

## 2. Repository and persistence behavior

- [x] 2.1 Implement `ConversationRepository.saveTurn` over `AppDatabase` so one transaction upserts the conversation with its title and appends the message, bumping `updatedAt`; verify a repository test saves a first user turn and finds one conversation with the expected title and one message.
- [x] 2.2 Implement `watchConversations`, `loadMostRecent`, `loadMessages`, and `close`; verify repository tests cover newest-first ordering, message order by creation time then id, reasoning round-tripping from the nullable column, an empty history, and a user-only turn that leaves no assistant message.
- [x] 2.3 Add a repository test that closes the database and then attempts a save, verifying the failure surfaces as an exception the controller can catch rather than a silent no-op.

## 3. Controller integration

- [x] 3.1 Add the repository to `ConversationController`, expose the database and repository through Riverpod with `ref.onDispose(db.close)`, and call `restoreMostRecent()` from `main` before `runApp`; verify controller tests with a fake repository load a saved conversation, and a load failure starts empty with a `historyNotice`.
- [x] 3.2 Persist the user turn on send before the request starts, catch a save failure into `historyNotice`, and still run the request; verify controller tests for a successful save, a failed save that still streams a reply, and an in-flight draft that never reaches the repository.
- [x] 3.3 Persist the assistant turn on normal end and on cancel-with-answer-text, and persist nothing when cancel arrives before any answer text; verify controller tests for each branch, including a failed assistant save that keeps the reply visible.
- [x] 3.4 Add `conversationId` to the controller state, derive the title from the first user message by trimming, collapsing whitespace, and truncating to 48 characters, and implement `startNewChat`; verify tests that a title is set once, a long title is shortened, no title request is made to the stream service, and New chat clears the screen without inserting a row.
- [x] 3.5 Implement `openConversation(id)` with the existing cancel semantics: stop an in-flight reply, keep any answer text as the assistant turn in the conversation being left, then load the target; verify tests for switching mid-stream, switching when no answer text arrived, and a load failure that leaves the current conversation usable with a `historyNotice`.

## 4. Chat screen history UI

- [x] 4.1 Add the history drawer to `ChatScreen`: a New chat action, a reactive conversation list ordered newest first, and a selection action that closes the drawer and calls `openConversation`; verify widget tests for newest-first ordering, the empty-history state, New chat preserving earlier conversations, and selection loading the target's messages.
- [x] 4.2 Render a restored conversation in order and keep the list scrolled to the bottom; verify a widget test restores a conversation with multiple turns and shows them in order.
- [x] 4.3 Add a dismissible `historyNotice` banner without Retry and a "History unavailable." state in the drawer when the conversation stream errors; verify widget tests for a save-failure banner, a load-failure banner, and a drawer error state.
- [x] 4.4 Add the user-facing changelog entry under a new heading in `CHANGELOG.md`; verify the wording reads as behavior (conversations survive closing the app, reopen from history, and stay on the device) rather than implementation.

## 5. Android backup policy

- [x] 5.1 Set `android:allowBackup="false"` in `android/app/src/main/AndroidManifest.xml`; verify by building a debug APK and inspecting the merged manifest for `allowBackup="false"`, or by checking the installed package's backup setting on `<device>`.

## 6. Integration and on-device confirmation

- [x] 6.1 Run `flutter analyze && flutter test` in the devcontainer and verify both pass with the generated Drift code present.
- [x] 6.2 On `<device>`, send a few turns against a live endpoint, force-stop and relaunch the app, confirm the conversation is restored in order, create a second conversation and switch back and forth to confirm newest-first listing and instant switching; record the round in `validation.md` under this change.

## Workflow follow-up

- Run the publishable scan on the commit (placeholders only, no hostnames or devices).
- Archive this change after review so `conversation-history` becomes project truth and the ephemeral-conversation requirement leaves `chat-streaming`.
- Land `persist-endpoint-config` first if following the recommended order; it is independent of the history data layer but keeps settings durable while history lands.
