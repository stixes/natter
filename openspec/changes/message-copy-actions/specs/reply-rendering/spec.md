# Spec Delta

## MODIFIED Requirements

### Requirement: Code blocks stay readable
A fenced code block in an assistant reply SHALL be shown as monospace text on
a tinted background, a line longer than the bubble SHALL be reachable by
horizontal scrolling rather than wrapped or clipped, and the block SHALL carry
a copy button that does not take that sideways scroll away from the block.

#### Scenario: A long line in a code block
- **WHEN** a reply contains a code line wider than the message bubble
- **THEN** the block still scrolls sideways to reveal the rest of the line and
  no characters are cut off, and the block's copy button is present without
  covering or moving the text

#### Scenario: The copy button leaves the scroll alone
- **WHEN** a code block is wide enough to scroll and the user drags it
  sideways
- **THEN** the block scrolls as it did before the copy button existed, and
  tapping the button copies instead of scrolling

#### Scenario: Light and dark code blocks
- **WHEN** the app runs in either theme
- **THEN** the code block's text, its background, and its copy button follow
  that theme and remain legible

### Requirement: Rendered replies keep text affordances
Formatted assistant text SHALL remain real text: selectable, readable by a
screen reader, and able to grow with the device's font scale without clipping.
Formatting SHALL NOT be the only carrier of a reply's meaning. Adding a
whole-turn copy control SHALL NOT change how selection behaves.

#### Scenario: Selection across formatted text
- **WHEN** the user selects part of a rendered reply that spans several formatted
  lines
- **THEN** the selected text is copied with its characters intact and its markup
  characters absent from the selection are not silently substituted

#### Scenario: Large font scale
- **WHEN** the device font scale is at its largest
- **THEN** a rendered reply stays fully readable inside the chat screen, with no
  clipped lines

#### Scenario: Selection next to a copy control
- **WHEN** the user selects text in a reply that now shows a whole-turn copy
  control
- **THEN** the selection starts, extends, and copies exactly as it did before,
  and the selection toolbar still offers its own copy
