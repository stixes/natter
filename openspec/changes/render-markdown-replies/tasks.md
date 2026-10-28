# Tasks

Rendering is display-only, so no task adds a request or changes the SSE path;
the one task that closes a network-shaped hole is 2.5, which proves the app
refuses to fetch an image named in reply text. The live-endpoint round lands in
5.1: markdown variety from a real model is what this change has to survive, and
the hermetic suite only replays what a scripted endpoint sends. The change modifies `chat-streaming`, which the acceptance suite covers,
so group 4 lands the suite growth; the existing `chat_streaming` scenarios need
no edit because their helpers read `MessageBubble.content`, which stays raw
text (checked in 4.3).

## 1. Dependency

- [x] 1.1 Add `flutter_markdown_plus: 1.0.7` to `dependencies` in
  `pubspec.yaml` with a comment in the style of the existing drift pin: exact
  pin because 1.0.8+ require `markdown ^7.3.1`, which needs Dart `^3.9.0`
  while the dev image is Flutter 3.29.3 / Dart 3.7.2, and 1.0.7 is the last
  release that resolves. Run `flutter pub get` in the devcontainer and verify
  `pubspec.lock` records `flutter_markdown_plus 1.0.7` with `markdown 7.3.0`,
  that no platform-channel plugin appears in the diff, and that
  `flutter analyze && flutter test` still pass before any UI work begins.

## 2. Rendering an assistant reply

- [x] 2.1 In `lib/ui/message_bubble.dart`, render an assistant turn through
  `MarkdownBody` (`selectable: true`, `softLineBreak: true`, the default
  GitHub-flavored extension set, and no `onTapLink`), behind one private
  renderer helper that builds the style sheet from
  `MarkdownStyleSheet.fromTheme(theme)` and overrides only `p`/body to
  `textTheme.bodyLarge`, `codeblockDecoration` to a
  `colorScheme.surfaceContainerLowest` box with a small radius, and the link
  style to `colorScheme.primary` underlined. Keep user turns on the existing
  `SelectableText`, and keep the bubble's padding, colour, max width,
  placeholder, and timestamp logic untouched. States implemented: committed
  assistant bubble rendered, user bubble verbatim, empty content renders
  nothing. Add cases to `test/message_bubble_test.dart` (setup copied from
  `test/chat_screen_test.dart`) covering: a reply with a heading, bold text, a
  list, and a fenced code block shows formatted output with no `#`, `**`, or
  backticks on screen; a user bubble with the same text shows it literally; a
  table and a blockquote render as structure. Run
  `flutter test test/message_bubble_test.dart`.
- [x] 2.2 Replace the tests that pin plain text rather than change behaviour:
  the `markdown arrives as literal plain text` case in `test/chat_screen_test.dart`
  becomes an assertion that the streamed markdown renders formatted with its
  markup characters absent, and the `children.first, isA<SelectableText>()`
  assertion in `test/message_bubble_test.dart` reads the bubble's rendered text
  instead of the widget type. Add a shared rendered-text reader to
  `test/support/test_support.dart` so both files reuse one helper. Verify
  `flutter test test/chat_screen_test.dart test/message_bubble_test.dart`
  passes and that the streaming, cancel, and reasoning cases still pass
  untouched.
- [x] 2.3 Give `_DraftBubble` in `lib/ui/chat_screen.dart` the coalesced live
  render from design.md: hold the newest draft text and forward it to the
  markdown path on a leading-edge plus trailing-edge throttle of about 100 ms,
  forwarding the final text immediately on completion, cancel, or failure. Add
  streaming cases in `test/chat_screen_test.dart` that pump past the interval
  and verify: a heading begun by the first tokens shows in heading style rather
  than as `#`; an open code fence mid-stream keeps the text received so far
  visible and resolves when the fence closes; text received during a tick is
  never lost or altered; and the committed reply reads as one whole turn. Run
  `flutter test test/chat_screen_test.dart`.
- [x] 2.4 Extend `test/message_bubble_contrast_test.dart` with the rendered
  reply: compute code text against `surfaceContainerLowest`, table border and
  text against the assistant bubble colour, and link colour against the same
  bubble, in light and dark. Verify every pair clears WCAG AA; if a pair fails,
  move to the design's documented fallback (the bubble's on-container token at
  full opacity) and note the substitution in this task, as the timestamp change
  did. Run `flutter test test/message_bubble_contrast_test.dart`.

  Substitution recorded: the structural lines (code block edge, table rules,
  quote bar, rule) do not use `outlineVariant` - it reads about 1.3:1 against
  the assistant bubble in both themes, far under even the 3:1 non-text floor -
  and not the heavier ink the design's fallback names, which makes a table grid
  look stamped. They use `onSurfaceVariant`, the bubble-side on-container token
  at full opacity: 7.2:1 light, 7.0:1 dark. The code block keeps its
  `surfaceContainerLowest` tint, but the tint alone measures about 1.3:1
  against the bubble, so the edge line above is what makes the block's extent
  perceivable; the same line also covers `horizontalRuleDecoration`. Measured
  pairs, light / dark: reply text on the bubble 13.2 / 9.7, code text on its
  fill 17.1 / 12.3, link text on the bubble 5.0 / 4.9, structure lines against
  the bubble 7.2 / 7.0 and against the code fill 7.9 / 10.0.
- [x] 2.5 Pass an `imageBuilder` in the renderer helper that returns
  `Text(alt)` when alternative text exists and a short marker naming it as an
  image when it does not, and never a network image. Verify with a widget test
  in `test/message_bubble_test.dart` that a reply containing
  `![diagram](https://example.invalid/x.png)` shows `diagram`, shows a marker
  for the same image with no alt text, and that `find.byType(Image)` finds
  nothing in either case. Example hosts stay as documentation addresses.
- [x] 2.6 Verify links are inert with a widget test that taps a rendered link
  in an assistant bubble and asserts no route is pushed, no crash occurs, and
  the reply text is unchanged; and that the link's text remains selectable.
  Run `flutter test test/message_bubble_test.dart`.
- [x] 2.7 Add a large-text and a narrow-surface case to
  `test/message_bubble_test.dart`, following the existing 2.0-scale bubble
  pattern: a rendered reply with a heading, a list, a table, and a long code
  line renders on a 360 dp surface at `TextScaler.linear(2.0)` with no overflow
  exception and no clipped lines. Run
  `flutter test test/message_bubble_test.dart`.

## 3. On-device look

- [x] 3.1 On the emulator on `<dev-box>` (or `<device>` as a fallback), drive a
  reply containing a heading, bold and italic text, inline code, a bulleted and
  a numbered list, a block quote, a task list, a five-column table, a fenced
  code block with a line wider than the bubble, a strikethrough, a horizontal
  rule, a link, and a remote image reference. Verify in light then dark mode:
  markup characters are gone, the code block scrolls sideways without cutting
  characters, the table stays legible, the code background reads against the
  assistant bubble in both themes, the link is underlined and a tap does
  nothing, the image shows alt text only, and a reopened conversation renders
  the same way. Watch the stream itself for jank or visibly chunky arrival,
  and lower the 2.1/2.3 throttle interval if it shows either. Check against
  `openspec/design-ux-guidelines.md` and record any deliberate exception in
  this task, including whether the default table column widths read acceptably
  or land as named debt.

  Ran light then dark on the emulator on `<dev-box>`, every named construct in
  one reply; the full record is in `validation.md`. Markup characters gone
  everywhere; code background, table, quote, link, and alt text read cleanly in
  both themes; the link is underlined and a tap does nothing; the image shows alt
  text only; a reopened conversation renders the same way; the wide code line
  clips at the bubble edge and a swipe scrolls it (`pixels 0`, `maxScrollExtent
  277` on the block's own horizontal viewport). Mid-stream the live render holds
  up: unclosed emphasis is already bold, a part-received table is already a
  table, an open fence is a code block with no fence characters. The 100 ms window
  was not lowered - nothing in the frames argued for it. Named debt, not fixed
  here: **default table column widths do not read acceptably** - every column
  gets the same flexible width, so a five-column table breaks words mid-character
  on a phone (`Regi on`, `41m s`, `shor t`); a clipped code line carries no
  resting scroll affordance, so wrapping long lines is a proposal rather than a
  drive-by; and streaming smoothness at real token cadence is still owed by 5.1,
  which a 250 ms scripted gap cannot answer.
- [x] 3.2 On the same device, with TalkBack on, read a rendered multi-block
  reply and verify the reading order follows the visual order, headings are
  announced as headings, list items are announced as items, code text is
  readable, and long-press selection still selects across the reply. Verify at
  the largest font scale that nothing clips. Record any exception here rather
  than opening a silent follow-up.

  Exceptions recorded here, none fixed silently (full record in `validation.md`).
  Reading order passes: the Flutter semantics tree and an accessibility-service
  dump with TalkBack bound both list blocks in document order, which is the
  visual order, table cells row by row. Code text is readable as text, and every
  block exposes selection state, so reply text is reachable and selectable. What
  fails is structure, not reach: the library sets no header flag on a rendered
  heading, no list or list-item flag on bullets and steps, and no row or column
  context on table cells, so TalkBack reads a multi-block reply as a run of loose
  text blocks - the window's only header node is the AppBar title. Two further
  findings: each block is its own selection region, so a drag from a heading into
  the next paragraph selects inside one block only, and because the library
  always attaches a tap recognizer to a link, an inert link is announced as a
  link with an action that does nothing - `tappable-links` inherits that. The
  largest-font-scale check landed as the 2.0-scale / 360 dp widget tests rather
  than a change to the emulator's scale, which the acceptance suite shares.

## 4. Acceptance suite

- [x] 4.1 Add `integration_test/accept/reply_rendering_accept_test.dart`,
  reusing `integration_test/accept/harness.dart` and its scripted endpoint, with
  scenarios that name the capability and requirement they confirm:
  `reply-rendering / Assistant replies render as markdown` (a scripted reply
  carrying heading, bold, and fenced code arrives formatted, with the markup
  characters absent from the rendered text) and
  `reply-rendering / User turns stay verbatim` (the same text sent by the user
  is shown literally). Add the rendered-text helper the scenarios need to
  `harness.dart` without disturbing `assistantBubbleTexts`, which keeps reading
  `MessageBubble.content`. Verify with
  `flutter test integration_test/accept/reply_rendering_accept_test.dart -d <device>`.
- [x] 4.2 Add a shallow on-device acceptance scenario for live rendering:
  `reply-rendering / Live rendering during a stream` scripts a multi-chunk
  reply that opens a code fence, and asserts the text received so far stays
  visible mid-stream and the committed reply renders as one formatted block.
  Verify with
  `flutter test integration_test/accept/reply_rendering_accept_test.dart -d <device>`.
- [x] 4.3 Run the whole gate, `scripts/accept.sh`, and verify it exits 0 with
  the existing `chat-streaming` scenarios unchanged, then confirm they still
  pass for the right reason: `assistantBubbleTexts` still sees raw text. Note
  in this task whether any existing scenario needed an edit, and if so which.

  Ran with `NATTER_ACCEPT_DEVICE` set to the emulator on `<dev-box>` (Android
  16): 12 scenarios, 0 failures, gate exit 0. No existing scenario needed an
  edit - `chat-streaming`, `conversation-history`, and `message-timestamps` all
  pass unchanged. Their reason for passing is confirmed rather than assumed: the
  new scenarios assert the raw markdown is still what `MessageBubble.content`
  carries (`'# Acceptance heading'`, `'**bold**'`, and
  `'```text\nhalf-written('` all present in stored text) while the rendered text
  carries none of it, which is the same property `assistantBubbleTexts` depends
  on. `harness.dart` gained `renderedMessageTexts` / `renderedTextContains`
  beside the existing helpers; `assistantBubbleTexts` is untouched. The fourth
  scenario (3.1's reopen check, landed as a suite scenario) is what grew the gate
  from 11 to 12; it initially asserted against the wrong conversation because a
  launch restores the last chat, so it now opens its own chat first, as
  `conversation-history` already does.

## 5. Live endpoint

- [x] 5.1 Run an on-device round against a live endpoint supplied through
  `--dart-define` (base URL, key, and model from the git-ignored local notes;
  nothing real committed), sending prompts that ask for a table, a long code
  function, a mixed list, and inline emphasis. Record the round in
  `validation.md` under this change: which markdown shapes rendered, which
  degraded to text, whether streaming stayed smooth, and the named debt for
  table widths if 3.1 left any. Confirm no destination beyond the configured
  base URL is contacted, and state in `validation.md` how that was observed.

  Run twice on the emulator on `<dev-box>` - light and dark - against
  llama-swap on `<llama-swap-host>` through its HTTPS front, values in
  `--dart-define` only, plus a mid-stream frame on a third round. Every shape
  rendered; nothing degraded to text (drawn marker counts: `**` 0, backticks 0,
  `|` 0, `](` 0, `![` 0, `---` 0, and the one surviving `#` is a code comment).
  Real cadence, the half the scripted endpoint could not show: ~850 characters in
  1.83 s (~120 tok/s), first token in ~290 ms, 8-12 coalesced render passes per
  reply at 110-330 characters each, growth at every 150 ms sample once streaming
  started, and a mid-stream frame where a half-received table row is already
  drawn as a table. The 100 ms window again needed no change. The emulator could
  not reach the front directly - the capture shows SYN then RST, because it is
  not a tailnet peer - so the round ran through `adb reverse` into a local
  plaintext-in / TLS-out relay, which leaves the app's own TLS handshake
  unobserved on Android and keeps `add-streaming-spine`'s device-TLS item open;
  named as such in `validation.md`. No destination beyond the configured base
  URL: one app socket at every `ss` poll, pointed at the forwarded stand-in for
  that URL; one relay connection per round, to the front only; no image widgets,
  no `NetworkImage`, and no DNS query anywhere in the device capture. Two new
  debts named from real output, alongside the table widths 3.1 left: an inline
  code span holding a hyphen splits into two chips across a line break, and the
  dark-mode code block outline reads brighter than the calm bar wants.

## 6. Integration and copy

- [x] 6.1 Run `flutter analyze && flutter test` in the devcontainer; verify
  both pass, and that `pubspec.yaml` gained exactly one dependency line plus its
  comment.

  `flutter analyze` reports no issues; `flutter test` passes 171 tests. The
  pubspec diff is one dependency line plus its pin comment, and `pubspec.lock`
  adds `flutter_markdown_plus 1.0.7` with `markdown 7.3.0` - no plugin, no
  platform channel, no new permission.
- [x] 6.2 Add a `## render-markdown-replies` entry to `CHANGELOG.md` in
  user-facing words (replies are formatted, code blocks scroll sideways, links
  are shown but do not open yet, images are named but not downloaded),
  following the existing entry format and leading with a one-line summary.
  Verify the entry sits at the top and holds no commit-speak or host names.

## Workflow follow-up

- Run the publishable scan on every commit: every blob in
  `git rev-list --all`, then the same scan over the pushed tree.
- `openspec validate render-markdown-replies --strict`, then archive so
  `openspec/specs/reply-rendering/` is created and `chat-streaming`
  swaps `Streaming chat screen` for `Streaming reply delivery`.
- Separate proposals this change deliberately leaves undone: `tappable-links`
  (adds `url_launcher` and the Android intent query), a code-block copy
  affordance, and syntax highlighting. The on-device rounds named three more:
  table column widths that suit a phone, code line wrapping or a visible scroll
  affordance, and selection that spans blocks instead of stopping at one. The
  live-endpoint round (5.1) landed, and the debts it named are recorded beside
  it. What it left open is not rendering: the app's own TLS handshake is still
  unobserved on Android, because this emulator cannot reach the HTTPS front and
  the round reached it through a local relay. The next change that touches the
  network path owes that round, and `add-streaming-spine` already carries the
  same open item.
