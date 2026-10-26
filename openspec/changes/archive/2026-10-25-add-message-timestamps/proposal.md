# Proposal

## Why

Messages in the chat screen carry no visible creation time. Reopening a saved
conversation gives no sense of when a turn was sent or answered, and the
transcript reads flatter than the ChatGPT-level bar in AGENTS.md. A small,
quiet timestamp restores temporal context without adding a control or a new
screen.

## What Changes

- Give every committed message its creation time: a user turn at the moment it
  is sent, an assistant turn at the moment it is committed (normal completion,
  cancel with a partial answer, or a silence failure that keeps partial answer
  text). The time is stored with the turn and restored when the conversation is
  reopened.
- Show that time in every committed message bubble as `HH:MM` on a 24-hour
  clock, in a very small font at the bubble's lower right, directly under the
  message text, in a lower-emphasis theme color.
- Keep the label quiet: it is not a tap target, adds no control, and does not
  change bubble alignment or the streaming placeholder. An in-flight draft
  (`Waiting` / `Thinking` / streaming text) shows no time until its turn is
  committed.
- Format the time locally on the device without adding a dependency.

Out of scope: date labels for messages from earlier days (the label stays
`HH:MM` only), relative times such as "2m ago", timestamps in the history
drawer's conversation list, timezone selection (the device's local time is
used), editing or hiding timestamps, and showing a time on the in-flight draft.
No product non-goal in AGENTS.md is touched: this adds no network call, no
telemetry, no account, and no sync.

## User-facing surface and UX impact

One surface changes, visually only (per `openspec/design-ux-guidelines.md`):
**the chat screen's message bubbles**. Each committed bubble gains a small time
label at its lower right. No interaction state changes:

- Empty: no bubbles, so no timestamps.
- Loading and streaming: the `Waiting` / `Thinking` placeholder and the
  streaming draft keep their current look and show no time; the label appears
  only when the turn is committed.
- Error, cancel, retry: committed turns keep their labels; a failed attempt
  with no committed turn adds no label. A partial answer committed by cancel or
  by a silence failure gets a label like any other assistant turn.
- Offline: saved turns remain readable with their labels; the label makes no
  network request.
- Dark mode and large text: the label uses theme tokens and real text, so it
  follows the theme and scales without clipping. It meets the guidelines'
  contrast and accessibility expectations; screen readers read the time as text
  after the message.

## Capabilities

### New Capabilities
- `message-timestamps`: the creation time carried by each committed message,
  its `HH:MM` 24-hour format and local-time semantics, and how the chat screen
  presents it (placement, emphasis, accessibility, and theming) without
  changing streaming states.

### Modified Capabilities
<!-- none: chat-streaming owns request and stream behavior and does not change;
     conversation-history already stores each turn's createdAt, and this change
     only surfaces it. -->

## Impact

- `lib/domain/chat_message.dart`: `ChatMessage` gains a required `createdAt`
  field, set by the controller and restored by the repository.
- `lib/state/chat_providers.dart`: sets `createdAt` on each committed user and
  assistant turn and passes it to the repository so the in-memory turn and the
  stored row share one time.
- `lib/data/conversation_repository.dart`: maps the stored `createdAt` into
  `ChatMessage` when loading turns; the write path already persists it.
- `lib/ui/message_bubble.dart` and `lib/ui/chat_screen.dart`: render the time in
  each committed bubble and pass the message's time in; the draft bubble keeps
  no time.
- A small formatting helper and its unit tests; widget tests for the label's
  text, placement, theme color, and absence on the draft.
- No new dependency, no new permission, no new network destination. No
  `pubspec.yaml` change.
- Changelog: one user-facing line about message timestamps.
