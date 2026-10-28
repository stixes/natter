# Design

## Context

See proposal.md - Why. The state this change runs against:

- `MessageBubble` (`lib/ui/message_bubble.dart`) renders `content` in one
  `SelectableText` for both roles, plus the `AnimatedPlaceholder` and the
  optional `HH:MM` `Text`. `ChatScreen` feeds committed turns and the
  in-flight `_DraftBubble` through the same widget.
- `AssistantDraft` (`lib/domain/assistant_draft.dart`) holds the accumulated
  answer text; `lib/state/chat_providers.dart` publishes a new
  `ConversationState` per SSE delta, so a draft bubble already rebuilds on
  every delta. Nothing token-level or markdown-aware exists in the domain or
  state layers, and this change keeps it that way.
- The database stores reply text exactly as received
  (`lib/data/app_database.dart`, `ConversationRepository.saveTurn`), and
  `ChatMessage.toWireFormat()` sends that same text back to the endpoint. Both
  stay untouched, which is what makes rendering display-only.
- Tests currently pin plain text: `test/chat_screen_test.dart` asserts literal
  `# Title\n**bold** and \`code\`` on screen, `test/message_bubble_test.dart`
  asserts the bubble's first child is a `SelectableText`, and
  `integration_test/streaming_spine_test.dart` reads message bodies through
  `find.byType(SelectableText)`. The acceptance harness reads
  `MessageBubble.content` (`assistantBubbleTexts`), which stays raw text, so
  the gate keeps passing without edits to its helpers.
- `pubspec.yaml` is deliberately minimal and already carries exact pins with
  recorded reasons (drift 2.29.0, shared_preferences 2.5.3, build_runner 2.7.1)
  because the dev image is pinned to Flutter 3.29.3 / Dart 3.7.2.

Facts about the renderer chosen below, verified against version 1.0.7's
sources, that shape the decisions:

- The default extension set is GitHub-flavored, so tables, task lists,
  strikethrough, and autolinks parse without extra setup.
- A `pre` block is already wrapped in a horizontal `Scrollbar` +
  `SingleChildScrollView`; its background comes from
  `MarkdownStyleSheet.codeblockDecoration`, whose theme default is `cardColor`.
- `selectable: true` renders selectable text per block instead of `Text`.
- A markdown link installs a `TapGestureRecognizer` whose `onTap` calls
  `onTapLink` only when one was supplied; with none supplied the tap does
  nothing.
- The default image handling calls `Image.network` for a remote `src`, and
  `imageBuilder` is the hook that replaces it.
- With the default `softLineBreak: false`, a single newline inside a paragraph
  is collapsed into a space.

## Goals / Non-Goals

**Goals:**

- Render assistant text as markdown without changing what is stored, sent, or
  the streaming state machine.
- Keep the answer smooth while it streams: no re-layout pop at commit, no
  per-token parse storm.
- Keep every existing text affordance working: selection, font scaling, screen
  reader flow, timestamps, light and dark themes.
- Keep the app's network surface exactly as it is today, including refusing to
  fetch images that reply text points at.

**Non-Goals:**

- No link launching, no code copy button, no syntax highlighting, no math, no
  image display, no rendering in user turns or history titles.
- No change to the wire contract, database schema, secure storage, or settings.
- No rendering settings, and no per-conversation or per-endpoint configuration.
- No golden-image tests; the visual bar is checked on the emulator.

## Decisions

**`flutter_markdown_plus` exact-pinned to `1.0.7`.**

It is the maintained community successor to Google's discontinued
`flutter_markdown`, MIT, pure Dart with no platform channel and no permission,
and its only transitive additions are `markdown` (dart-lang), `meta`, and
`path`. The pin is not preference: 1.0.8 and later require `markdown ^7.3.1`,
which declares `sdk: ^3.9.0`, while the dev image is Dart 3.7.2; 1.0.7 depends
on `markdown ^7.3.0`, which resolves to 7.3.0 (`sdk: ^3.2.0`) on this SDK. The
pubspec comment records that reason in the same style as the existing drift
pin, and `pubspec.lock` is committed. Alternatives, all rejected on the pinned
SDK or on package weight: `prism_markdown` needs Dart `^3.9.0`; `gpt_markdown`
1.3+ needs Flutter 3.35+ and drags LaTeX and SVG dependencies, and the older
1.1.x/1.2.x lines pull `flutter_math_fork`, which pulls `flutter_svg` and
`provider`; `markdown_widget` pulls `url_launcher`, `visibility_detector`,
`scroll_to_index`, `highlight`, and `flutter_highlight` (itself stuck below
Dart 3.0). Hand-rolling a renderer over `markdown` alone keeps the dependency
list smallest but re-implements tables, selection, list bullets, blockquotes,
and code blocks, which is exactly the polish the design guidelines refuse to
excuse. Writing our own is not worth the surface area here.

**`MarkdownBody`, not the scrolling `Markdown` widget.**

The chat transcript's `ListView` already owns vertical scrolling; a nested
vertical scroll container inside a bubble would fight it. `MarkdownBody` lays
its blocks out in a plain column, and the code block's own scroller is
horizontal only, so the axes do not collide.

**One bubble widget that branches on role.**

`MessageBubble` keeps taking raw `content` and keeps its padding, colour,
max width, placeholder, and timestamp logic. Assistant bubbles build
`MarkdownBody(data: content, selectable: true, ...)`; user bubbles keep
`SelectableText`. What the user typed stays verbatim without a second widget
that duplicates the bubble. Alternatives rejected: stripping markup before
display (destroys the round trip with storage and the wire format, and the
user would never see the original); a separate `MarkdownBubble` (two places to
keep in sync for colour, padding, and the time label); a `renderMarkdown` flag
threaded from the call site (the role already carries the decision, so the
flag is a way to get it wrong).

**A single style sheet built from `MarkdownStyleSheet.fromTheme`, with only
the tokens that fail on device overridden.**

The theme-derived sheet already maps headings to `textTheme` steps
(`h1` to `headlineSmall` and down), sizes body text from the theme, and pulls
list bullets, blockquote colour, table border, and the horizontal rule from
theme tokens, which keeps dark mode correct for free and matches the
guidelines' "no hard-coded colours". Override exactly three things:
`p`/`body` to `textTheme.bodyLarge` so plain paragraphs keep today's type,
`codeblockDecoration` to `colorScheme.surfaceContainerLowest` with a small
radius because the default `cardColor` sits badly inside an assistant bubble
colored `surfaceContainerHighest`, and the link style to
`colorScheme.primary` with an underline. Any further size or padding tuning
(heading padding, table cell padding) is decided from the emulator look, not
in advance, and recorded in the task that checks it.

**`softLineBreak: true`.**

Models emit single newlines for visual line breaks far more often than they
emit the two trailing spaces CommonMark requires, and collapsing them would
run a reply's lines together, which reads as a bug. Keeping the soft break
preserves the model's line structure while real paragraph breaks still separate
blocks. The default is the CommonMark-purist behaviour; for chat replies it is
the wrong default.

**Links stay inert: no `onTapLink` at all.**

With no handler installed, the package's link recognizer is a no-op, so the
affordance is styled and the tap is harmless. The follow-up proposal named in
proposal.md adds `url_launcher` plus the Android intent query and the tap
behaviour in one place, where the new dependency and permission surface can be
weighed on their own. Deliberate interim exception to the design guidelines: a
link looks tappable and is not. Mitigations: keep the underline so it reads as
a link in transcripts saved before the follow-up lands, and do not describe
links as interactive anywhere in app copy.

**Images never load: always pass an `imageBuilder`.**

The builder returns `Text(alt)` when alt text exists, otherwise a short marker
naming it as an image, and never touches the network. This is not polish, it is
the network rule: reply text is untrusted input from a third-party model, and
the default handler would make the app request an arbitrary address the user
never configured. There is no "leave it alone" option because the default is
the fetching one.

**Live rendering, coalesced in the draft bubble only.**

`_DraftBubble` holds the newest draft text and forwards it to `MessageBubble`
on a leading-edge plus trailing-edge throttle of about 100 ms, and forwards the
final text immediately when the stream ends, is cancelled, or fails. So the
first token renders at once, at most about ten markdown parses and layouts
happen per second mid-stream, and the committed reply is exactly the text that
arrived. Alternatives rejected: re-parsing on every delta (a full-document
parse and a rich-text layout per token, quadratic in reply length and the
usual source of streaming jank, against the guidelines' "streaming must not
fight the user"); plain text while streaming with markdown at commit (one
visible re-layout pop per reply, and the user watches markup characters they
already know are formatting). The throttle lives in the widget, so
`AssistantDraft`, the controller, and the SSE client stay markdown-ignorant.
If the on-device check shows the throttle makes text arrive in visibly chunky
steps, lower the interval before considering any deeper change.

**Assistant markdown is asserted through rendered structure, not string
equality.**

Widget tests assert the widget shape the renderer produces (a heading style, a
selectable block set, a horizontal scroller around code text) plus the
absence of markup characters in the visible text. Reading bodies through
`find.byType(SelectableText)` in `test/message_bubble_test.dart` and
`integration_test/streaming_spine_test.dart` is replaced by a helper that
collects rendered text from the bubble, so the harnesses stop encoding the
plain-text implementation. The acceptance harness keeps reading
`MessageBubble.content`, which stays raw.

## UX and interaction

Per `openspec/design-ux-guidelines.md`:

- **States**: empty, error, cancel, retry, offline, and the placeholder
  behaviour are unchanged; the change touches only how answer text is drawn.
  `Waiting` and `Thinking` still appear before any answer text and are
  unchanged. Streaming answers render as markdown from the first token, with
  partial constructs resolving as the text completes. A committed partial
  answer, a retry reply, a reopened conversation, and the blank-answer fallback
  that displays reasoning all render through the same markdown path. User
  bubbles stay verbatim.
- **Motion**: no new animation; the only motion is the existing placeholder
  timer, untouched. Streaming keeps appending without a layout pop; the
  coalesced render changes the answer's appearance at most ten times a second,
  which must not move the transcript or resize the composer. Auto-scroll stays
  governed by today's "at the bottom" rule. Reduced motion needs nothing
  special because nothing animates; state this row as not applicable beyond
  "no new motion".
- **Accessibility**: rendered text remains real text, so TalkBack reads
  headings, list items, and code as structure rather than as markup noise, and
  Android font scaling grows it without clipping. Long-press selection keeps
  working through `selectable: true`, and the timestamp stays a separate plain
  label. Code text, table borders, blockquote text, and link colour must clear
  WCAG AA in both themes; the code block background is a scheme token, never a
  fixed grey. The one accessibility risk to verify on device is that the
  per-block selectable regions do not break TalkBack's reading order across a
  multi-block reply.
- **Copy**: no new visible copy. A reply that points at an image shows its alt
  text, or a plain marker naming it as an image, and that marker is the only
  new string: it says what is missing without inventing a control. Error and
  empty-state copy is untouched.
- **Dark mode**: the style sheet comes from the active theme, so headings,
  blockquotes, tables, rules, and links follow light or dark without
  hard-coded colours. The two things to inspect in both themes on the emulator
  on `<dev-box>` (or `<device>` as fallback) are the code block's background
  against the assistant bubble, and link colour against the bubble.

## Risks / Trade-offs

- [The pin goes stale] → 1.0.7 is the last release resolvable on Dart 3.7.2.
  The pubspec comment states why, and the line is revisited the same way drift
  is when the dev image's Flutter moves. Accepted.
- [A community fork is a maintenance bet] → MIT, pure Dart, three transitive
  packages, no platform channel, no permission, pinned in `pubspec.lock`, and
  reached through one widget file, so a swap later touches one place. Accepted.
- [Re-parsing markdown while streaming costs frames] → the draft renders
  through a ~100 ms leading/trailing throttle instead of per delta, and the
  on-device round watches for jank and chunky text arrival. If it still
  stutters on a long reply, profile in DevTools before changing the approach.
- [Partial markdown mid-stream renders oddly] → an open fence or half a table
  renders as the parser sees it and settles as the text completes; the spec
  requires only that received text stays visible and unaltered. Accepted as the
  cost of live rendering, which the alternative (plain text then markdown)
  trades for a per-reply re-layout pop.
- [Inert links look interactive] → Real but temporary; the named follow-up
  proposal makes them work. Under the underline stays, and nothing in app copy
  promises a tap does anything. Accepted.
- [A wide table becomes unreadable at the default flex column width] → Check a
  five-column table on the emulator; if the columns squeeze too far, a later
  change sets `tableColumnWidth` or scrolls the table sideways. Recorded as
  possible debt in `validation.md`, not expanded here.
- [Raw HTML, footnotes, or other unparsed syntax shows as text] → The
  degrade-to-text scenario covers it, and a test asserts nothing is dropped.
  Accepted; the rendered set is a defined subset, not "all of CommonMark".
- [Test readers break when `SelectableText` stops being the bubble's body] →
  Expected and named in tasks: the two widget tests and one integration
  harness helper move to a rendered-text reader rather than the old widget
  type. The acceptance harness needs no change because it reads the raw
  `content` field.
- [Reply markup can make a bubble very tall] → Long code blocks already
  scroll sideways and the transcript scrolls vertically; no height cap is
  added, since capping would hide answer text.

## Migration Plan

No database change and no settings change: stored text stays raw markdown, so
nothing migrates and `schemaVersion` stays where it is. Ship in a normal
build. Rollback reverts the commit; stored replies keep their markdown text and
simply render literally again under the older build, so no history is lost and
no user action is needed.

## Open Questions

- The exact heading, paragraph, and table-cell padding inside a bubble, and
  whether heading sizes need one step down from the theme mapping. Pure visual
  tuning, answered by the emulator look and recorded in that task.
- Whether the code block gains a copy affordance at all, and whether syntax
  highlighting earns a highlighter dependency. Both need their own proposals.
