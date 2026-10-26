# message-timestamps Specification

## Purpose

Defines the creation time shown on each committed chat message: how it is
captured and preserved, its 24-hour `HH:MM` format, and how the chat screen
presents it without changing streaming states.

## Requirements

### Requirement: Timestamp on committed messages

Every committed message SHALL display the time it was created: a user turn at
the moment it was sent, an assistant turn at the moment it was committed. The
displayed time SHALL remain unchanged when the conversation is reopened from
history. An empty conversation shows no timestamps.

#### Scenario: User turn shows its send time

- **WHEN** the user sends a message
- **THEN** the user's message bubble displays the time the turn was sent, and
  reopening the conversation later shows the same time

#### Scenario: Assistant turn shows its commit time

- **WHEN** an assistant reply completes and is committed
- **THEN** the assistant's message bubble displays the time the turn was
  committed, and reopening the conversation later shows the same time

#### Scenario: Partial answer committed on cancel

- **WHEN** the user cancels while answer text has already streamed
- **THEN** the committed partial assistant turn displays a timestamp like any
  other committed assistant turn

#### Scenario: Partial answer kept on silence failure

- **WHEN** a silence failure commits answer text that had already streamed
- **THEN** that assistant turn displays a timestamp like any other committed
  assistant turn

#### Scenario: Empty conversation

- **WHEN** the chat screen opens with no committed messages
- **THEN** no timestamp is shown

### Requirement: In-flight replies show no timestamp

An assistant reply that is waiting, thinking, or streaming SHALL NOT display a
timestamp. A timestamp SHALL appear only once its turn is committed. A cancelled
reply with no answer text and a failed request with no committed turn MUST NOT
add a timestamp.

#### Scenario: Waiting or thinking

- **WHEN** a reply is waiting for its first token or showing the `Thinking`
  placeholder
- **THEN** its placeholder shows no timestamp

#### Scenario: Streaming answer text

- **WHEN** answer text is streaming and the assistant turn is not yet committed
- **THEN** the streaming bubble shows no timestamp

#### Scenario: Cancel without answer text

- **WHEN** the user cancels before any answer text arrives
- **THEN** no assistant turn and no timestamp are added

#### Scenario: Failure without a committed turn

- **WHEN** a request fails before any assistant turn is committed
- **THEN** prior messages keep their timestamps and no timestamp is added for
  the failed attempt

### Requirement: Timestamp format

The timestamp SHALL be shown as a 24-hour clock time in `HH:MM` format: two
zero-padded digits for the hour and two for the minute, separated by a colon. It
SHALL NOT include seconds, AM/PM, or a date. The time SHALL be the device's
local time for the message.

#### Scenario: Morning time is zero-padded

- **WHEN** a message's local time is 09:05
- **THEN** its timestamp reads `09:05`

#### Scenario: Afternoon time stays on the 24-hour clock

- **WHEN** a message's local time is 13:07
- **THEN** its timestamp reads `13:07`

#### Scenario: Midnight

- **WHEN** a message's local time is 00:05
- **THEN** its timestamp reads `00:05`

#### Scenario: No seconds, AM/PM, or date

- **WHEN** a message's local time is 23:59:59 on another calendar day
- **THEN** its timestamp reads `23:59` with no seconds, AM/PM, or date

### Requirement: Timestamp placement and emphasis

The timestamp SHALL appear at the lower right of its message bubble, below the
message text, in a smaller font and a lower-emphasis theme color than the
message text. It MUST NOT be a tap target and MUST NOT add a control or change
the bubble's alignment in the transcript.

#### Scenario: Lower right of the bubble

- **WHEN** a committed message bubble is shown
- **THEN** its timestamp sits at the lower right, below the message text, for both
  user and assistant bubbles

#### Scenario: Visually subordinate to the message

- **WHEN** the timestamp is compared with its message text
- **THEN** it uses a smaller font and a lower-emphasis color from the active theme

#### Scenario: Not a control

- **WHEN** the user taps the timestamp
- **THEN** nothing happens and no new control appears

### Requirement: Timestamp contrast and theming

The timestamp SHALL meet WCAG AA contrast against its bubble in light and dark
themes. It SHALL follow the active theme without restarting the app. Per
`openspec/design-ux-guidelines.md`, the time MUST NOT rely on color alone to
carry its meaning.

#### Scenario: Contrast in both themes

- **WHEN** a committed message bubble is rendered in the light theme or the dark
  theme
- **THEN** its timestamp meets WCAG AA contrast against the bubble

#### Scenario: Dark mode

- **WHEN** the system switches between light and dark mode while the chat screen
  is open
- **THEN** the timestamp repaints in the new theme's colors and remains legible

### Requirement: Timestamp text scaling and accessibility

The timestamp SHALL scale with Android font scaling without clipping or
overlapping the message text. It MUST be exposed to accessibility services as
text, so a screen reader announces it after the message text.

#### Scenario: Large text

- **WHEN** Android font scaling is at its largest value
- **THEN** the timestamp remains fully visible without clipping or overlapping the
  message text

#### Scenario: Screen reader

- **WHEN** a screen-reader user moves through a committed message
- **THEN** the message text is announced first and the timestamp is announced as
  text after it
