# Design

## Context

See proposal.md - Why. Current state: `main()` runs startup housekeeping (load
profile and system prompt, delete expired chats) and then calls
`ConversationController.restoreMostRecent()`, which loads the newest saved
conversation into `ConversationState` before `runApp` ([lib/main.dart](../../lib/main.dart),
[lib/state/chat_providers.dart](../../lib/state/chat_providers.dart)). The chat
screen's state is a single in-memory `ConversationState` under an
`UncontrolledProviderScope`; nothing persists UI position. The history drawer
already offers "New chat" and a list ([lib/ui/chat_screen.dart](../../lib/ui/chat_screen.dart)),
and the Empty state it renders already satisfies the guidelines' Empty
requirements.

## UX and interaction

Per `openspec/design-ux-guidelines.md`:

- **States**: launch lands on the chat screen's existing Empty state -
  composer plus the current short prompt. That state is already implemented for
  "New chat" from the drawer, so no new state work; verify it renders on cold
  start. Loading/streaming, error, and cancel states are unchanged. The
  background-restore case (process alive) keeps whatever state was on screen,
  including a visible in-flight reply - that behavior already exists and gains
  a spec scenario rather than code.
- **Motion**: none added; no change.
- **Accessibility**: no change - the launched screen is the same widget tree
  the New-chat path already renders; re-verify existing semantics (drawer,
  composer labels) still hold.
- **Copy**: no new copy. The startup history-notice string ("History could not
  be loaded.") loses its startup producer and is only worth removing if dead;
  drawer keeps "History unavailable."
- **Dark mode**: not affected; the empty state already themes (verify on
  emulator in both brightnesses).

## Decisions

1. **Delete the startup restore rather than gate it behind a setting.**
   Alternatives considered: a "resume last conversation" toggle, or restoring
   only when the drawer… - either adds the kind of option this product refuses
   to carry (AGENTS.md: compete on subtraction). One fixed, ChatGPT-matching
   behavior is cheaper and self-documenting.
2. **Keep `ConversationRepository.loadMostRecent`.** It is part of the storage
   repository's contract and is covered by
   `test/conversation_repository_test.dart`; only its sole non-test caller
   (`restoreMostRecent`) goes away. Deleting it would shrink a tested storage
   API for no gain.
3. **Do nothing for background/foreground.** Android keeps the activity (and
   the provider container) alive for a merely-backgrounded app, and Flutter
   recreates in-process state on resume; the in-memory `ConversationState`
   already survives that. When the OS evicts the process, relaunch re-runs
   `main()`, which now lands on a new chat - exactly the split the request
   asks for. A composer-draft persistence to cover the evicted-mid-typing case
   is out of scope (it would be a new state-saving mechanism).
4. **Acceptance suite flips rather than forks.** The existing relaunch leg in
   `integration_test/accept/conversation_history_accept_test.dart` asserts the
   opposite of the new contract; it becomes the regression test for "relaunch
   opens a new chat" (same drawer, same harness, `startNewChat`-style pump to
   assert emptiness). The true process-kill round stays a manual round recorded
   in `validation.md`, as the suite comment already states.

## Risks / Trade-offs

- [User loses an in-progress half-typed reply after OS eviction] → accepted:
  committed turns remain one drawer tap away; mitigating further needs composer
  persistence, deliberately out of scope.
- [Behavior looks like history is ignored at launch] → the drawer still lists
  everything and expiry still runs in `main()` before anything reads history;
  acceptance leg for drawer-open stays green, proving storage is untouched.
- [Removing `restoreMostRecent` strands its unit tests] → those tests in
  `test/chat_screen_test.dart` and `test/conversation_controller_test.dart`
  are rewritten to the drawer-open path (`openConversation`), preserving their
  history coverage under the surviving route.

## Migration Plan

No data migration: storage format, expiry, and drawer behavior are untouched;
existing conversations simply stop auto-opening. Rollback = revert the commit;
no state or schema is involved.

## Open Questions

None.
