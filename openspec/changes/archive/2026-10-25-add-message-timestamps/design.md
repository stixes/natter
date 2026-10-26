# Design

## Context

See proposal.md - Why. The relevant current state:

- `ChatMessage` (`lib/domain/chat_message.dart`) carries `role`, `content`, and
  `reasoning`; it has no creation time. `toWireFormat()` sends only role and
  content, so the endpoint contract is unaffected.
- `ConversationState.messages` holds committed turns. `AssistantDraft` holds the
  in-flight reply; a draft is committed only on normal completion, cancel with
  answer text, or a silence failure with answer text. An empty or failed draft
  leaves no assistant turn.
- Drift's `Messages` table already has a `createdAt` column
  (`lib/data/app_database.dart`). `ConversationRepository.saveTurn` writes
  `at ?? DateTime.now()` into it; `loadMessages` orders by `createdAt` and `id`
  but drops the value when mapping rows to `ChatMessage`. No schema change or
  migration is needed.
- `MessageBubble` (`lib/ui/message_bubble.dart`) renders `content` and an
  optional `placeholderLabel` in a `Column` with `CrossAxisAlignment.start`.
  `ChatScreen` renders committed `ChatMessage`s through `MessageBubble` and the
  in-flight `AssistantDraft` through `_DraftBubble`.
- The app themes from a seed and widgets read scheme tokens. `pubspec.yaml`
  deliberately has no `intl` or date-formatting package. The database schema
  version is 1.

## Goals / Non-Goals

**Goals:**

- Capture each committed turn's creation time once and use the same value in
  memory and storage.
- Format `HH:MM` on the 24-hour clock with a pure, dependency-free helper.
- Present a quiet, accessible label that does not change streaming states,
  bubble alignment, or the endpoint request.

**Non-Goals:**

- No date, relative time, timezone picker, history-list timestamps, or
  edit/hide affordance.
- No new dependency and no schema migration.
- No network-path change and no `validation.md` round.
- No golden-image tests.

## Decisions

**`ChatMessage` carries a required `createdAt`.**

Add `required DateTime createdAt` to the constructor. A message without a time
is not representable, so the UI never needs a "missing time" branch. The
controller stamps a user turn when `send` runs and an assistant turn when it is
committed; the repository restores the stored time on read. `DateTime` has no
const constructor, so existing `const ChatMessage(...)` call sites drop `const`;
the class stays immutable and its fields stay final. Alternatives: a nullable
field with a hidden label when absent (weaker invariant, silent gaps); a
separate in-memory time map (parallel state that can drift). Both rejected.

**The controller stamps the turn and the repository persists the same instant.**

`saveTurn` already accepts an optional `at` and writes it to both the
conversation and message rows. The controller creates the `ChatMessage` with
`createdAt: DateTime.now()` and passes `at: message.createdAt`, so the row and
the in-memory turn agree. The three commit paths - normal completion, cancel
with answer text, and silence failure with answer text - each stamp the
assistant turn at commit time. `saveTurn`'s default stays `DateTime.now()` for
direct callers; tests that call it without `at` set the message's time
explicitly and pass a matching `at` when they assert row time. Alternative: let
the repository assign the time and return it to the controller (rejected: the
bubble must show its time before the asynchronous write completes, so the
controller needs the value synchronously).

**The timestamp stays local metadata and never reaches the endpoint.**

`ChatMessage.toWireFormat()` continues to return only role and content. The
timestamp is stored in the local database and formatted on the device; it is not
logged, sent, or used to order the request. This keeps the "BYO endpoint only"
and "history stays on the device" principles intact.

**Formatting is a pure function, not a package.**

`String formatMessageTime(DateTime time)` in `lib/ui/message_time.dart` reads
the local components of `time.toLocal()` and returns two zero-padded digits for
the hour and minute separated by a colon. `.toLocal()` makes the label the
device's current local time regardless of how the stored instant was
materialized. Unit tests cover 00:05, 09:05, 13:07, and 23:59. Alternatives: add
`intl` and use `DateFormat('HH:mm')` (a package for five characters, against the
subtraction principle); format inline in the widget (harder to unit-test). Both
rejected. If a future change needs locale-aware dates, that is when `intl` earns
its place.

**The bubble takes an optional time; the draft passes none.**

`MessageBubble` gains `DateTime? createdAt`. Committed bubbles in `ChatScreen`
pass `message.createdAt`; `_DraftBubble` passes nothing, so waiting, thinking,
and streaming drafts show no time. The time is a final child of the bubble's
`Column`, rendered as a plain `Text` (not `SelectableText`) so the message text
stays the only selectable part. The Column's cross-axis alignment becomes `end`,
so the time sits at the trailing edge while the text block's internal lines stay
left-aligned. Alternatives: a separate `TimestampedBubble` widget (duplicates
the bubble for a five-character label); absolute positioning with a `Stack`
(overlap and padding complexity). Both rejected. A short message narrower than
its time may show a small gap on the leading edge; that is acceptable for a
five-character label and avoids a second layout path. The bubble's outer
left/right alignment in the transcript is unchanged; only the time's trailing
position inside the bubble uses the Column's end alignment.

**The label uses secondary-text theme tokens.**

Style the time with `theme.textTheme.labelSmall` and
`theme.colorScheme.onSurfaceVariant`. The smaller size and the secondary token
make it subordinate to the message's `bodyLarge` text, and the token switches
with light and dark themes without hard-coded colours. The time is meaningful
text, so `disabledColor` is not used (it is for disabled controls and may not
meet contrast). If the on-device check finds `onSurfaceVariant` below WCAG AA
against either bubble colour in either theme, fall back to the bubble's
on-container token at full opacity and keep size and placement as the
lower-emphasis signals. Alternatives: reduced alpha on the text colour (contrast
risk); a fixed grey (breaks dark mode). Both rejected.

**Accessibility: real text, no extra label.**

The time is a plain `Text` in the semantics tree; it is not excluded and gets no
custom semantics label. Screen readers read the message text and then the time
in visual order. It adds no tap target, so the 48 dp rule does not apply. The
time's meaning does not rely on colour; the text itself carries it.

## UX and interaction

Per `openspec/design-ux-guidelines.md`:

- **States**: committed bubbles show the time; empty conversations show none.
  Waiting, `Thinking`, and streaming drafts show none until the turn is
  committed. Cancelled replies with no answer text and failed requests with no
  committed turn add none. A partial answer committed by cancel or by a silence
  failure gets a time like any other assistant turn. Prior turns keep their
  times through error, cancel, retry, and offline.
- **Motion**: none. The label is static; no animation or timer, so reduced-motion
  settings need nothing. This row does not apply beyond "no motion".
- **Accessibility**: real text in the semantics tree; AA contrast in both themes;
  scales with Android font scaling without clipping; no tap target and no new
  control; screen readers read the time after the message text. The label is not
  the only carrier of any meaning.
- **Copy**: the visible label is only `HH:MM`, with no "Sent", "AM/PM", seconds,
  or date. The format is the copy; there is no sentence to translate.
- **Dark mode**: `onSurfaceVariant` and `labelSmall` come from the active scheme;
  no hard-coded colours. The label repaints on a light/dark switch without
  restarting the app. The on-device look checks both themes.

## Risks / Trade-offs

- [A required `createdAt` breaks every `ChatMessage` construction site] → The
  compiler finds them; update fixtures mechanically, dropping `const` where a
  `DateTime` argument appears, and add the time at each controller commit path.
  An optional field would weaken the invariant and add a missing-time branch.
  Accepted.
- [In-memory time and stored row time can diverge] → The controller stamps once
  and passes the same instant to `saveTurn`; tests assert the saved row and the
  in-memory turn carry the same time.
- [Low-emphasis colour can fall below AA on a bubble colour] → Use
  `onSurfaceVariant`; check light and dark on the emulator. If it fails, use the
  bubble's on-container token and rely on size and placement for emphasis.
- [A timezone change can shift the displayed time of stored messages] → The
  database stores an instant; the label renders it in the device's current local
  time. Preserving the original wall-clock time would need a stored offset and
  is out of scope. Accepted for a local, single-device app.
- [The time on a very short message can widen the bubble's leading gap] → The
  time is a trailing line in the same Column; a five-character label creates at
  most a small gap. A second layout path for short messages would add complexity
  for little gain. Accepted.

## Migration Plan

No database migration: `Messages.createdAt` already exists and `schemaVersion`
stays 1. Ship in a normal build. Rollback reverts the commit; stored times remain
in the database and are simply not shown, so there is no data loss. No user
action is required.
