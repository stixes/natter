# Tasks

No task touches the network path, so no live-endpoint round or `validation.md`
is owed; the on-device look below is recorded in the task note instead.

## 1. Timestamp formatting

- [x] 1.1 Create `lib/ui/message_time.dart` with
  `String formatMessageTime(DateTime time)`, which calls `time.toLocal()` and
  returns two zero-padded digits for the hour and minute separated by a colon.
  Verify unit tests in a new `test/message_time_test.dart` (following the
  pure-function style in `test/stream_delta_test.dart`) cover 00:05, 09:05,
  13:07, and 23:59, and run `flutter test test/message_time_test.dart`.

## 2. Domain model and persistence

- [x] 2.1 Add `required DateTime createdAt` to `ChatMessage` in
  `lib/domain/chat_message.dart`, keep `toWireFormat()` returning only role and
  content, and update every construction site in `lib/` and `test/` with an
  explicit time, dropping `const` where a `DateTime` argument appears. Verify
  `flutter analyze` passes and no `ChatMessage` call site is left without a time.
- [x] 2.2 Map `row.createdAt` into the `ChatMessage` built by
  `ConversationRepository.loadMessages`, keeping the existing `createdAt`/`id`
  ordering. Add or extend a case in `test/conversation_repository_test.dart`
  that saves a turn with a known time (the same instant as both the message's
  `createdAt` and `saveTurn`'s `at`) and asserts `loadMessages` returns that
  time. Verify `flutter test test/conversation_repository_test.dart` passes.
- [x] 2.3 Stamp each committed turn in `ConversationController` in
  `lib/state/chat_providers.dart`: create the user turn in `send` with
  `createdAt: DateTime.now()` and pass `at: userTurn.createdAt` to `saveTurn`;
  stamp assistant turns in normal completion, cancel with answer text, and
  silence failure with answer text, and pass `at: message.createdAt` from
  `_persistAssistant`. Add or extend cases in
  `test/conversation_controller_test.dart` that assert the in-memory turn and
  the stored row share the same time for the user path and at least one
  assistant path. Verify `flutter test test/conversation_controller_test.dart`
  passes.

## 3. Chat screen label

- [x] 3.1 Extend `MessageBubble` in `lib/ui/message_bubble.dart` with an optional
  `DateTime? createdAt`; when present, render `formatMessageTime(createdAt)` as
  the last child of the bubble's `Column`, as a plain `Text` (not
  `SelectableText`), with `theme.textTheme.labelSmall` and
  `theme.colorScheme.onSurfaceVariant`, and set the Column's cross-axis
  alignment to `end` so the label sits at the trailing edge. Pass
  `message.createdAt` for committed bubbles in `lib/ui/chat_screen.dart` and
  leave `_DraftBubble` without one. States implemented: committed user and
  assistant bubbles show the time; empty, waiting, thinking, and streaming
  states show none. Add widget tests in a new `test/message_bubble_test.dart`
  (following the widget-test setup in `test/chat_screen_test.dart`) for a
  committed bubble showing `HH:MM`, a draft bubble showing no time, the time's
  style using the `onSurfaceVariant` token, and the time appearing after the
  message text in widget order; run `flutter test test/message_bubble_test.dart`.
- [x] 3.2 Add a large-text case to `test/message_bubble_test.dart`: pump a
  committed bubble with `MediaQuery(textScaler: TextScaler.linear(2.0))` on a
  360 dp-wide surface; verify no overflow exception and the time stays visible.
  Run `flutter test test/message_bubble_test.dart`.
- [x] 3.3 On the emulator on `<dev-box>` (or `<device>` as a fallback), open the
  chat screen in light then dark mode and verify: an empty conversation shows no
  timestamps; a committed user turn and a committed assistant turn each show a
  small `HH:MM` label at the lower right; a streaming reply shows no label until
  it commits; cancelling with partial text commits a labelled turn; a failed
  request leaves prior labels intact; and the largest font scale leaves the
  label fully visible. Check against `openspec/design-ux-guidelines.md`, check
  the label's contrast in both themes, and note any exception in this task.

  Done: ran `integration_test/timestamp_visibility_test.dart` on the connected
  device against the mock SSE endpoint in light and dark modes. All checks
  passed. Deliberate exception: `onSurfaceVariant` measured 2.59:1 against the
  light user bubble (below WCAG AA), so the label uses each bubble's
  on-container token at full opacity - the design's documented fallback -
  measured 7.26:1 dark and 13.25:1 light by
  `test/message_bubble_contrast_test.dart`.
- [x] 3.4 Add a `## add-message-timestamps` entry to `CHANGELOG.md` in
  user-facing words (each message shows the time it was sent or answered, as a
  quiet `HH:MM` label that follows light and dark mode); follow the format of
  the existing `## add-app-icon` entry. Verify the entry sits at the top and
  contains no commit-speak or host names.

## 4. Integration

- [x] 4.1 Run `flutter analyze && flutter test` in the devcontainer; verify both
  pass.

## Workflow follow-up

- Run the publishable scan on the commit (placeholders only, no hostnames or
  devices).
- `openspec validate add-message-timestamps --strict`, then archive so
  `openspec/specs/message-timestamps/` is created.
- Separate follow-up worth proposing: date labels for messages from earlier
  days, only if the `HH:MM` label alone reads ambiguously in review.
