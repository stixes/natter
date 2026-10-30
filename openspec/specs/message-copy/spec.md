# message-copy Specification

## Purpose

Defines how a chat turn's text is put on the clipboard: the copy control on
each committed turn, what each role's clipboard text is, the copy button on a
rendered code block, the feedback that confirms a copy, and the rule that
copying changes nothing but the clipboard.

## Requirements

### Requirement: A committed turn carries a copy control
Every committed turn on the chat screen, user or assistant, SHALL show a copy
control that does not require the text to be selected first. An in-flight
reply shows no copy control. A long-press MUST NOT be the only path to this
action, as `openspec/design-ux-guidelines.md` requires.

#### Scenario: Tap to copy a committed reply
- **WHEN** the user taps the copy control on a committed assistant reply
- **THEN** that reply's text is placed on the clipboard and no selection step
  is required first

#### Scenario: An in-flight reply offers nothing
- **WHEN** a reply is still streaming, or is showing only the `Waiting` or
  `Thinking` placeholder
- **THEN** no copy control is shown for that reply, and the placeholder and
  transcript are unchanged

#### Scenario: A partial answer committed on cancel
- **WHEN** the user cancels a stream that has already produced answer text,
  and that partial answer is committed
- **THEN** the committed partial turn shows a copy control like any other
  committed turn

#### Scenario: A failed reply
- **WHEN** a reply fails and the failure is surfaced with Retry
- **THEN** no copy control is offered for the failed turn beyond the Retry
  affordance the failure already shows

### Requirement: What each role copies
An assistant turn SHALL copy the text as it was received, with its markup
characters intact, so a paste round-trips the same markdown the endpoint
produced. A user turn SHALL copy exactly the text that was typed.

#### Scenario: A rendered reply copies its source
- **WHEN** the user copies an assistant reply that is drawn with headings,
  emphasis, and a code block
- **THEN** the clipboard holds that reply's markdown source, not the rendered
  characters alone and not a reformatted version

#### Scenario: A user turn copies verbatim
- **WHEN** the user copies their own turn, including one containing markup
  characters or a line break
- **THEN** the clipboard holds exactly what was typed

#### Scenario: A blank-answer fallback reply
- **WHEN** the user copies a reply whose displayed text came from the
  blank-answer fallback, where reasoning was shown as the answer
- **THEN** the clipboard holds the text that was displayed

### Requirement: A rendered code block carries a copy button
Each fenced code block in an assistant reply SHALL carry a copy button that
places that block's text on the clipboard, on its own, without the surrounding
reply's text.

#### Scenario: Copy one block from a mixed reply
- **WHEN** a reply contains prose, a code block, and another code block, and
  the user taps the button on the first block
- **THEN** the clipboard holds the first block's contents only, with neither
  the prose nor the other block

#### Scenario: The block's text is copied intact
- **WHEN** a code block is copied
- **THEN** the clipboard holds the block's characters exactly, including its
  line breaks, indentation, and any characters the rendering draws as syntax
  markers

### Requirement: A copy confirms itself without blocking the conversation
A copy SHALL be confirmed by a state change on the control that made it, and
SHALL NOT open a surface the user must dismiss. Repeating a copy leaves the
clipboard holding the same text.

#### Scenario: The control shows the copy landed
- **WHEN** a copy succeeds
- **THEN** the control that was tapped changes to show the copy happened, and
  no dialog, sheet, or other blocking surface appears

#### Scenario: Screen readers hear the result
- **WHEN** a copy is made with an accessibility service active
- **THEN** the control's label names its action before the tap and the result
  of the tap is announced

### Requirement: Copying leaves the conversation untouched
A copy SHALL write the clipboard and nothing else: no network request, no
change to stored history, no change to what the next request sends.

#### Scenario: A copy makes no request
- **WHEN** any copy control or code block button is tapped
- **THEN** no request is made to any destination, and no new destination
  appears

#### Scenario: History and the next request are unchanged
- **WHEN** the user copies from a conversation and then sends a follow-up, or
  reopens that conversation from history
- **THEN** the stored turns and the conversation sent to the endpoint are
  exactly as they were before the copy

### Requirement: Copy controls meet the platform affordance bar
Every copy control SHALL be at least 48x48 dp, carry a screen-reader label,
stay legible in both themes, and remain reachable and readable at the
device's largest font scale, per `openspec/design-ux-guidelines.md`.

#### Scenario: A copy control under text scaling and both themes
- **WHEN** the device font scale is at its largest and the app runs in either
  theme
- **THEN** every copy control is visible, not clipped, legible on its theme's
  tokens, and large enough to hit

#### Scenario: Selection stays as the partial path
- **WHEN** the user selects part of a reply and copies through the platform
  selection toolbar
- **THEN** selection works as it did before this change, and the whole-turn
  copy control does not replace or disable it
