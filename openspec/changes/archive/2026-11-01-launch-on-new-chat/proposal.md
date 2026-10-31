# Proposal

## Why

On a cold start the app reopens the last conversation, so every launch lands
somewhere unexpected: the user must press "New chat" before they can talk, and
the thread they see is whatever the app guessed they were last doing. ChatGPT
opens on a new chat; Natter should match that - a fresh conversation is the
default entry point, and history is something the user reaches for through the
drawer, never something the app assumes.

## What Changes

- **BREAKING** Cold start (first launch, app killed, or process evicted by the OS)
  opens a new, empty chat instead of restoring the most recent conversation.
  This reverses the restore-on-start behavior shipped by `local-conversation-history`.
- Remove the startup restore (`ConversationController.restoreMostRecent` and its
  call in `main()`); history remains fully available through the drawer.
- Backgrounding is unaffected: while the process stays alive, returning to the
  app shows exactly what the user was doing. No state-saving work is added.
- No change to what is stored, what the drawer lists, or how conversations are
  opened and titled.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `conversation-history`: the "Local conversation storage" requirement currently
  promises to restore the most recent conversation when the app starts. It
  changes to promise that a start opens a new chat, with the drawer as the only
  route back to stored conversations. The startup-restore scenarios (restore
  after restart, user turn visible after mid-reply exit) are rewritten around
  the drawer path, and the history list gains a scenario for a backgrounded app
  keeping its conversation. The "Load failure at startup" scenario is softened
  to cover only the empty conversation and the drawer's "History unavailable."
  report, since there is no longer a startup history load into the chat screen.
  Storage, listing, titles, expiry, and drawer behavior are otherwise untouched.

## Impact

- **User-facing surface**: the chat screen at launch. UX impact per
  `openspec/design-ux-guidelines.md`: launch lands on the Empty state (composer
  plus short prompt), one tap shorter than today; no new controls, dark mode and
  accessibility unchanged. The history drawer is unchanged and is the only way
  back to a previous thread.
- **Code**: `lib/main.dart` (drop the `restoreMostRecent()` call),
  `lib/state/chat_providers.dart` (drop `ConversationController.restoreMostRecent`),
  `ConversationRepository.loadMostRecent` may become unused.
- **Tests**: unit tests in `test/chat_screen_test.dart` and
  `test/conversation_controller_test.dart` that drive `restoreMostRecent`
  rework to the drawer-open path; the acceptance suite's relaunch leg in
  `integration_test/accept/conversation_history_accept_test.dart` flips to
  assert relaunch opens a new chat (see tasks).
- No new dependencies, permissions, or network destinations.
- Out of scope: any launch-state persistence or "resume where you left off"
  mechanism, drawer or expiry behavior changes, and any non-goal from AGENTS.md
  (none are touched).
