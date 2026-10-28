# Spec Delta

## Purpose

Defines how an assistant reply's text is presented on the chat screen: the
markdown that renders, how rendering behaves while a reply streams, how code
blocks and tables stay readable, and the rendering rules that keep links inert,
images unfetched, and stored text raw.

## ADDED Requirements

### Requirement: Assistant replies render as markdown
The app SHALL render an assistant reply's text as formatted markdown instead of
literal markup characters. The rendered set covers headings, emphasis, inline
code, bulleted and numbered lists, block quotes, tables, strikethrough, task
lists, horizontal rules, and fenced code blocks.

#### Scenario: Markup becomes structure
- **WHEN** an assistant reply contains a heading, bold text, a bulleted list, and a fenced code block
- **THEN** the heading, bold text, list, and code block are shown formatted and the markup characters are not shown

#### Scenario: Unsupported syntax degrades to text
- **WHEN** a reply uses syntax outside the rendered set, such as inline HTML or a math expression
- **THEN** that content is still shown as readable text and nothing is dropped from the reply

### Requirement: User turns stay verbatim
The app SHALL render the user's own messages as plain text exactly as typed,
with no markdown formatting applied.

#### Scenario: Typed markup is shown as typed
- **WHEN** the user sends a message containing `# Title` or `**bold**`
- **THEN** the bubble shows those characters literally

### Requirement: Live rendering during a stream
The app SHALL render markdown in the in-flight reply as its text arrives, with
no plain-text phase before the reply is committed. Answer text already received
SHALL remain visible and unaltered at every point in the stream.

#### Scenario: First token formats immediately
- **WHEN** the first answer tokens begin a heading and the heading line is not yet complete
- **THEN** the text received so far is shown in the heading style rather than as literal characters

#### Scenario: An incomplete construct mid-stream
- **WHEN** a code fence or table is only partially received
- **THEN** the text received so far stays visible and readable, and the construct resolves as the rest of the reply arrives

#### Scenario: Placeholder states are unchanged by rendering
- **WHEN** a reply has produced no answer text yet
- **THEN** the `Waiting` or `Thinking` placeholder is shown exactly as before, and rendering begins only with the first answer text

### Requirement: Code blocks stay readable
A fenced code block in an assistant reply SHALL be shown as monospace text on a
tinted background, and a line longer than the bubble SHALL be reachable by
horizontal scrolling rather than wrapped or clipped.

#### Scenario: A long line in a code block
- **WHEN** a reply contains a code line wider than the message bubble
- **THEN** the block scrolls sideways to reveal the rest of the line and no characters are cut off

#### Scenario: Light and dark code blocks
- **WHEN** the app runs in either theme
- **THEN** the code block's text and background follow that theme and remain legible

### Requirement: Tables stay readable
A table in an assistant reply SHALL be shown as a table whose columns fit the
available width, with its text remaining legible rather than clipped.

#### Scenario: A wide table
- **WHEN** a reply contains a table with more columns than the bubble can show at full width
- **THEN** the columns compress or scroll so that every cell's text remains reachable

### Requirement: Links are styled but inert
The app SHALL style a markdown link as a link and SHALL NOT navigate, launch an
external app, or make any network request when the user taps it.

#### Scenario: A link tap does nothing
- **WHEN** the user taps a link in an assistant reply
- **THEN** nothing opens, no destination is contacted, and the reply is unchanged

#### Scenario: Link text is still available
- **WHEN** a reply contains a markdown link
- **THEN** the link's text is visible and selectable like surrounding text

### Requirement: Remote images are never fetched
The app SHALL NOT load an image referenced by an assistant reply. It SHALL show
that image's alternative text, or a marker naming it as an image when no
alternative text is given, and MUST NOT contact the referenced address.

#### Scenario: A reply references a remote image
- **WHEN** a reply contains a markdown image with alternative text
- **THEN** the alternative text is shown and no request is made to the image address

#### Scenario: A remote image without alternative text
- **WHEN** a reply contains a markdown image with no alternative text
- **THEN** a marker naming it as an image is shown in its place

### Requirement: Rendering is display-only
Rendering markdown SHALL NOT change what is stored, what is sent to the
configured endpoint, or what a reopened conversation contains. Stored turns
SHALL keep their original markdown text and SHALL render again on reopen.

#### Scenario: Reopen a conversation
- **WHEN** the user reopens a saved conversation whose replies contain markdown
- **THEN** those replies render formatted, from the same stored text as before

#### Scenario: The endpoint sees the stored text
- **WHEN** a follow-up request is sent in a conversation containing rendered
  markdown
- **THEN** the conversation sent to the endpoint carries the original markdown
  text, not a rendered or reformatted version

### Requirement: Rendered replies keep text affordances
Formatted assistant text SHALL remain real text: selectable, readable by a
screen reader, and able to grow with the device's font scale without clipping.
Formatting SHALL NOT be the only carrier of a reply's meaning.

#### Scenario: Selection across formatted text
- **WHEN** the user selects part of a rendered reply that spans several formatted
  lines
- **THEN** the selected text is copied with its characters intact and its markup
  characters absent from the selection are not silently substituted

#### Scenario: Large font scale
- **WHEN** the device font scale is at its largest
- **THEN** a rendered reply stays fully readable inside the chat screen, with no
  clipped lines
