# Proposal

## Why

Assistant replies arrive as markdown from nearly every model behind an
OpenAI-compatible endpoint, and Natter currently prints the markup literally:
`# Heading`, `**bold**`, and fenced code blocks reach the screen as syntax
characters. That is the single most visible gap between this app and the
ChatGPT-level bar AGENTS.md sets, and it makes multi-line code unreadable.

## What Changes

- Assistant replies render as markdown: headings, emphasis, inline code, links
  (styled, not tappable in this change), bullet and numbered lists, block
  quotes, GFM tables, strikethrough, task-list checkboxes, horizontal rules,
  and fenced code blocks.
- The in-flight draft renders markdown live while tokens arrive, so the answer
  never re-lays-out when the stream ends. Rendering is the bubble's own
  rebuild of its current text; no token-level parsing state is carried.
- Fenced code blocks render in a monospace block on a tinted background and
  scroll horizontally rather than wrapping or clipping. This is the renderer's
  default: no syntax highlighting and no per-block copy button in this change.
- User messages keep their current plain-text rendering. What the user typed is
  shown exactly as typed.
- Markdown in a stored turn is rendered when the conversation is reopened, with
  no change to what is written to the database: the raw text stays the stored
  form, so history, expiry, and any later search or export still see the
  original markup.
- Remote images referenced inside markdown are never fetched. The alt text is
  shown instead. Rendering an `<img>` as a network image would make the app
  contact a destination the user never configured, which the network rules in
  AGENTS.md do not allow.
- **BREAKING** for tests, not for stored data: the shipped `chat-streaming`
  requirement that says the reply "SHALL be rendered as plain text", and its
  `Answer shown as plain text` scenario, are removed. Unit and integration
  tests that assert literal markdown syntax on screen are replaced by tests
  that assert rendered structure.

Out of scope: tappable links (a separate proposal, because opening a link needs
a new dependency and an Android intent query), code-block copy buttons, syntax
highlighting, LaTeX and math rendering, image display, table column sizing
beyond the renderer's default, rendering markdown in user messages, rendering
markdown in the history drawer's titles, any change to what is stored or sent,
and any setting for rendering. No product non-goal in AGENTS.md is touched: no
account, no telemetry, no cloud sync, no local inference, no agent or tool UI.

## User-facing surface and UX impact

One surface changes, visually and structurally (per
`openspec/design-ux-guidelines.md`): **the chat screen's message bubbles for
assistant turns**. No new control, no new screen, no new gesture.

- Empty: unchanged, no bubbles.
- Loading and streaming: the `Waiting` / `Thinking` placeholder is unchanged
  and appears before any answer text. Once answer tokens begin, the draft
  renders as markdown from the first token, so an opening `#` grows into a
  heading rather than showing `#`. An unterminated fence or a partial table
  mid-stream renders as the parser sees it at that moment and settles when the
  text completes; that is the accepted cost of live rendering, and it is a
  reason to re-render the draft on a coalesced tick rather than per token.
- Error, cancel, retry, offline: unchanged in behavior. A committed partial
  answer renders as markdown like any other reply.
- Dark mode: heading, code, quote, and table colours come from the active
  scheme, so both themes are covered by the same rules; the code block's
  tinted background is a scheme token, not a fixed grey.
- Accessibility: rendered markdown stays real text, so Android font scaling,
  screen readers, and long-press selection keep working. Headings are announced
  as headings; list structure is preserved in the semantics tree. Contrast for
  code and table text is checked against WCAG AA in both themes.

## Capabilities

### New Capabilities

- `reply-rendering`: how an assistant reply's text is presented on screen: the
  markdown subset that renders, live rendering during a stream, code block and
  table presentation, inert links, never-fetched images, plain text for user
  turns, and the rule that rendering is display-only over stored raw text.

### Modified Capabilities

- `chat-streaming`: the `Streaming chat screen` requirement is removed, taking
  its `Answer shown as plain text` scenario with it, and `Streaming reply
  delivery` is added carrying the same request and incremental-rendering
  contract minus the plain-text claim. OpenSpec applies a scenario removal only
  through a requirement removal, hence the pair. Placeholder states, reasoning
  capture, blank-answer fallback, cancellation, retry, and the silence bounds
  are untouched; rendering moves to `reply-rendering`.

## Impact

- New dependency: `flutter_markdown_plus` exact-pinned to `1.0.7`, because it
  is the maintained successor to Google's discontinued `flutter_markdown`, is
  pure Dart with no platform channel or permission, and 1.0.8+ require
  `markdown ^7.3.1`, which needs Dart `^3.9.0` while the dev image is pinned to
  Flutter 3.29.3 / Dart 3.7.2. That is the same pinning reason already recorded
  for drift in `pubspec.yaml`.
- `lib/ui/message_bubble.dart`: assistant bubbles switch from `SelectableText`
  to the markdown widget (selectable), keep plain text for user turns, and
  configure the renderer: GFM extension set, no link tap handler, an image
  builder that renders alt text without fetching, and a style sheet built from
  theme tokens.
- `lib/ui/chat_screen.dart`: the draft bubble passes its streamed text through
  the same markdown path, with rebuild coalescing.
- Tests to replace, not keep: `test/chat_screen_test.dart`
  (`markdown arrives as literal plain text`), `test/message_bubble_test.dart`
  (asserts a `SelectableText` child), and the `SelectableText` reader in
  `integration_test/streaming_spine_test.dart`.
- `integration_test/accept/chat_streaming_accept_test.dart` keeps passing
  unchanged: its helpers read `MessageBubble.content`, which still holds raw
  text. The suite gains a scenario for rendered markdown, which it must, since
  the change alters covered user-visible behavior.
- No new permission, no new network destination, no schema change, no change to
  `toWireFormat()`, no change to stored content.
- Changelog: one user-facing entry about replies being formatted.
- Follow-up named, not built here: a `tappable-links` proposal that adds
  `url_launcher`, the Android intent query, and the link affordance.
