# Tasks

## 1. Startup behavior

- [x] 1.1 In `lib/main.dart`, drop the `restoreMostRecent()` call so every cold start lands on a new chat; keep profile/system-prompt loads and the expiry cleanup exactly as they are (expiry must still run before anything reads history). Check: `flutter analyze` clean, and grep confirms no call site left: `grep -rn restoreMostRecent lib` returns nothing.
- [x] 1.2 In `lib/state/chat_providers.dart`, delete `ConversationController.restoreMostRecent` (its `ConversationState(historyNotice: 'History could not be loaded.')` branch goes with it); keep `ConversationRepository.loadMostRecent` per design decision 2, and keep the other `historyNotice` strings that still have producers (save failures, `openConversation` failures). Check: `flutter analyze` reports no unused-code finding, `flutter test` green together with group 2's rewrites.

## 2. Tests: unit + acceptance

- [x] 2.1 Rewrite the `restoreMostRecent`-drumping tests in `test/chat_screen_test.dart` (~lines 893-983) onto the surviving routes: one startup-contract test asserting a fresh launch with saved history opens an empty chat showing `Say something.` (empty state) with no `History could not be loaded.` notice; one test that the same launch's drawer lists the stored conversation and `openConversation` loads its turns in order, reusing the existing drawer pumps. Check: `flutter test test/chat_screen_test.dart` green.
- [x] 2.2 In `test/conversation_controller_test.dart` (~511-527), replace the `restoreMostRecent` cases with a startup-contract case (fresh controller over a populated repository yields `ConversationState` with null `conversationId` and empty `messages`) and keep mid-reply-exit storage coverage via `t.repository.loadMostRecent`/`loadMessages` as in the existing expiry tests (~738-751); add the "Backgrounded app keeps its conversation" case as a controller-level test that state is untouched across an unbackground cycle (no controller API involved: assert `ConversationState` unchanged after a background/resume pump following the existing `chat_screen_test` pumps). Check: `flutter test test/conversation_controller_test.dart` green.
- [x] 2.3 Acceptance suite (`conversation-history` is covered; the scenario to update): flip the relaunch leg of `integration_test/accept/conversation_history_accept_test.dart` so after the in-process relaunch the chat screen is empty (`Say something.`) instead of showing the newest chat, and the drawer leg still proves the stored conversations open with their turns - covering the delta's "Conversation restored after a restart" scenario; update the file's scenario-map comment to match. Check: run the suite on the emulator on `<dev-box>` via `scripts/accept.sh` and read its verdict.

## 3. On-device round (no network-path change)

- [x] 3.1 On the emulator on `<dev-box>`: send turns, force-stop the app (`adb shell am force-stop dev.natter.app`), reopen, and observe a new empty chat with `Say something.`, the drawer listing the earlier conversation, and background-then-return showing the in-progress conversation unchanged; also one look in dark mode. This replaces the true process-kill manual round the accept-test header names. Check: record the round in `validation.md` under this change, naming the previously-recorded round it supersedes if any.

## 4. Wrap-up

- [x] 4.1 Add a `CHANGELOG.md` entry in user-facing wording (app opens on a new chat; previous chats open from the history list). Check: entry reads as behavior, not commit-speak.
- [ ] 4.2 Publishable-hygiene scan per AGENTS.md (every blob in `git rev-list --all`, then the pushed tree) and confirm the CI verdict on the pushed commit (`gh run list --branch <branch> --limit 1`). Check: scan clean; verdict green or a recorded reason.

## Workflow follow-up

- Archive with `/opsx-archive` so `openspec/specs/conversation-history/spec.md` reflects the delta.
- Record the definition-of-done checks (acceptance green, validation.md, CI verdict) before archiving.
