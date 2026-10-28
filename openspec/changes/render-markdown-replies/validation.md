# Validation

## Automated checks

Run in the devcontainer against Flutter 3.29.3 / Dart 3.7.2.

- `flutter analyze` - no issues.
- `flutter test` - 171 tests pass.

Coverage added by this change:

- `test/message_bubble_test.dart` - a rendered assistant reply (heading, bold,
  list, fenced block) shows structure with no `#`, `**`, or backticks; headings,
  emphasis, and code carry style; a table renders as rows and a blockquote as a
  quoted block; a user turn with the same text stays verbatim; a link is drawn
  as a link and a tap pushes no route, crashes nothing, and leaves the text
  selectable; an image reference shows alt text, an empty-alt image shows a
  marker, and `find.byType(Image)` finds nothing in either case; a code line
  wider than the bubble sits inside a horizontal scroll viewport whose
  `maxScrollExtent` is positive, starts with its tail past the bubble edge, and
  brings the tail inside once scrolled; a rendered reply survives
  `TextScaler.linear(2.0)`, including a heading, a list, a table, and a long
  code line on a 360 dp surface; a very large reply still scrolls inside the
  transcript.
- `test/chat_screen_test.dart` - streamed markdown renders formatted rather
  than as markup; a streamed heading is a heading mid-stream; an open code fence
  mid-stream keeps the text received so far; tokens arriving inside a render
  window appear when the window closes, unchanged; the streaming, cancel,
  retry, and reasoning cases still pass untouched.
- `test/message_bubble_contrast_test.dart` - rendered reply pairs in light and
  dark (see the substitution recorded in task 2.4).
- `test/support/test_support.dart` - `renderedSpans` / `renderedBlocks` read
  what is drawn (rich text runs and selectable text) instead of what is stored,
  shared by the two UI test files.
- `integration_test/accept/reply_rendering_accept_test.dart` - five on-device
  scenarios: `reply-rendering / Assistant replies render as markdown`,
  `reply-rendering / User turns stay verbatim`, `reply-rendering / Live
  rendering during a stream`, and `reply-rendering / Reopening a chat renders
  the same way`. Each rendered assertion is paired with a stored-turn
  assertion, so the screen shows structure while storage keeps whole markdown.
- `integration_test/accept/harness.dart` - `renderedMessageTexts` /
  `renderedTextContains` beside the existing helpers; `assistantBubbleTexts`
  still reads `MessageBubble.content`, which is why the three pre-existing
  acceptance files needed no edit.

## Acceptance gate (task 4.3)

`scripts/accept.sh` on the emulator on `<dev-box>` (Android 16, API 36): 12
scenarios across four files, 0 failures, gate exit 0. No pre-existing scenario
needed an edit - `chat_streaming`, `conversation_history`, and
`message_timestamps` pass unchanged. Their reason for passing is confirmed, not
assumed: the new scenarios assert that the raw markdown (`'# Acceptance
heading'`, `'**bold**'`, `'```text\nhalf-written('`) is still what
`MessageBubble.content` carries while the rendered text carries none of it,
which is the same property `assistantBubbleTexts` depends on.

One scenario landed late and earned its place: the reopen case initially
asserted against the wrong conversation, because a launch restores the last
chat rather than opening a new one. The scenario now opens its own chat before
the exchange, which is what `conversation_history` already does.

## On-device look round (task 3.1)

Ran on the emulator on `<dev-box>` (Android 16, API 36, serial `<dev-box>:5555`)
from the devcontainer's adb client, in light mode and then dark mode
(`adb shell cmd uimode night yes|no`; the app follows the system brightness,
confirmed in-process by `PlatformDispatcher.platformBrightness`).

Capture method, because the obvious one fails here: `adb screencap` on this
emulator returns a stale launcher frame even while the app holds window focus.
The pixels came from inside the app instead - a disposable integration test that
drives the exchange, rasterises the largest `RenderRepaintBoundary` in the tree,
writes it to the app's own cache directory, and holds the process open long
enough for `adb exec-out run-as dev.natter.app cat code_cache/<name>.png` to
pull it (integration test teardown uninstalls the app, which wipes those files).
Nothing from that probe is committed; its frames framed the app approximately,
so the judgements below are about typography, spacing, and colour rather than
exact pixel edges.

The reply drove every construct the task names: an H1, bold and italic text,
inline code, a strikethrough, a bulleted list with a nested item, a numbered
list, a task list (open and closed), a two-line blockquote, a five-column
table, a fenced Python block with a line wider than the bubble, a horizontal
rule, a link, and a remote image reference. What the frames showed, in both
themes:

1. Markup characters are gone everywhere: no `#`, `**`, `*`, `` ` ``, `~~`,
   `>`, `|`, `---`, or fence ticks on screen. Bullets, numbers, and task
   checkboxes render as their own marks; the closed task shows a filled check.
2. Heading, body, inline code, quote, table, and code contrast read cleanly in
   both themes, matching the pairs the contrast test measures. The code block
   keeps a visible edge in dark mode, where its `surfaceContainerLowest` tint
   alone would not be enough.
3. The table stays legible but its column widths do not read acceptably on a
   phone: the library gives every column the same flexible width, so a
   five-column table breaks words mid-character - `Regi on`, `Cach e`,
   `Not es`, `41m s`, `shor t`, `lo nger note goe`. Recorded as named debt
   below, not fixed silently.
4. The wide code line is clipped at the bubble edge and scrolls sideways under
   a swipe, measured on the device: the block's own horizontal viewport reported
   `axis = horizontal`, `pixels = 0`, `maxScrollExtent = 277`, and a leftward
   swipe followed by a rightward one moved it and brought it back. The same
   property is pinned in CI by the widget test listed above, because driving a
   swipe from a screenshot harness proves less than the viewport does.
5. A link is underlined in the primary colour, and tapping it opens nothing; the
   image reference shows its alt text only, never a fetched image.
6. Live rendering during the stream is right. Mid-stream frames show an
   unclosed `**bold that has not closed**` already drawn bold, a table that has
   received its header and one row drawn as a table (including the trailing
   empty cell), and an unterminated ` ```python ` fence drawn as a code block
   with no fence characters. Nothing flashed raw markdown, at the scripted
   endpoint's 250 ms chunk gap. The 100 ms coalescing window from design.md
   stayed as set; nothing in the frames argued for lowering it.
7. A reopened conversation renders the same way as a fresh one - first asserted
   on the device, then landed as the fourth acceptance scenario so it stays
   asserted.

Exceptions and debt recorded here, deliberately not fixed inside this change:

- **Table column widths** (3.1): equal flexible columns break words on a phone.
  Fixing it means a column-width policy for the style sheet, which is its own
  decision. Named for a follow-up proposal; the five-column table is the case
  that shows it.
- **Code block scroll discoverability** (3.1): a clipped code line gives no
  resting affordance - the package's scrollbar thumb fades out, so the only hint
  is that a word is cut off mid-glyph. Wrapping long lines instead of scrolling
  is the ChatGPT-app behaviour and may be the better default for chat. Whether
  to wrap or to keep scrolling and make the scroll visible is a proposal, not a
  drive-by.
- **Streaming smoothness at real token cadence** (3.1, closed by 5.1): a
  scripted endpoint at a fixed 250 ms gap cannot show jank from a real model's
  uneven arrival, so the on-device frames at that time showed correct content,
  not correct feel. The live round closed the observation - see the cadence
  record under task 5.1. What that round could not do is *measure*: nothing on
  this surface records frame timings, so the claim rests on sampled draft growth
  and a mid-stream frame rather than a dropped-frame count.
- **Whole-reply selection** (3.2): the library gives every block its own
  selectable region, so a drag from a heading into the following paragraph
  selects within one block only. Each block is individually selectable and
  copyable, which is what the spec asks for; selection across block boundaries
  is a separate decision.

## Accessibility round (task 3.2)

Same device, same reply. Two readings, because the in-process tree and the
Android accessibility surface answer different questions.

1. The Flutter semantics tree, walked in-process while the reply was on screen:
   nodes appear in document order, which is the visual order - heading text,
   emphasis paragraph, each list item, each table cell row by row, the code
   block, then the closing paragraph. Each block is its own node and exposes
   text-selection state, so a screen reader can reach and select reply text.
   Flagged as exceptions: the heading carries no header flag, list items carry
   no list/item structure, and the table is a run of loose cells rather than a
   table with row and column context. The AppBar's own title is the only node in
   the window carrying a header flag.
2. With TalkBack bound (enabled through
   `settings put secure enabled_accessibility_services`, first-run notification
   prompt dismissed), an accessibility-tree dump taken by a separate service
   showed the same order and the same flat roles: every block and every cell an
   ordinary view, no heading or list role, code text readable as text, and the
   reply's own blocks marked clickable because the bubble itself is a tap target
   for copy.
3. A consequence of the inert-link decision, worth naming: the library always
   attaches a tap recognizer to a link, so the accessibility surface announces a
   rendered link as a link and offers an action that does nothing. On screen that
   reads as an inert styled word; through a screen reader it reads as an
   activatable link that fails. `tappable-links` inherits this.

Font scale at the largest setting was checked on this surface by widget tests
(2.0 on a 360 dp surface, heading, list, table, and long code line, no overflow
exception and no clipped line) rather than by changing the emulator's font
scale; the emulator's scale was left alone because the acceptance suite runs on
the same device and expects its own metrics.

## Live endpoint round (task 5.1)

Ran on the emulator on `<dev-box>` against llama-swap on `<llama-swap-host>`,
values through `--dart-define` only: the base URL of the HTTPS front
(`https://<tls-front-host>:8443/v1`), an empty API key (that front admits
traffic by tailnet membership and asks no key), and a small fast MoE chat model
referred to here as `<model>`. Nothing real is committed. Two full rounds, light
then dark, plus a frame taken mid-stream in a third light round.

The prompt asked for a table, a very long code line, a mixed list (bullets,
nesting, numbers, tasks), inline emphasis, a quote, a link, and a remote image.
The model reproduced the block almost verbatim, which makes the stored versus
rendered comparison exact rather than approximate.

**Reachability, because the direct path failed.** An app socket from the
emulator to `https://<tls-front-host>:8443` was refused: the device-side capture
shows SYN then immediate RST. The emulator is not a tailnet peer and the front
only carries tailnet traffic, while the dev container is a peer and reaches it
(`curl` to `/v1/models` returns 200). So the round ran through
`adb reverse tcp:18443` into a plaintext-in / TLS-out relay living in `/tmp` of
the dev container, and the configured base URL became `http://127.0.0.1:18443/v1`
with the relay doing TLS 1.3 to the front. Consequence, stated plainly: the app
leg of that hop was loopback cleartext, so **the app's own TLS handshake is still
unobserved on Android**, and `add-streaming-spine`'s open item about device-side
TLS stays open. What this round adds to that item is a sharper diagnosis: the
front is not merely unresolvable from a non-peer device, it refuses such traffic
outright, so a round that wants TLS from this emulator needs either a tailnet
route for it or a front that listens off-tailnet.

**What rendered.** Everything the prompt asked for, in both themes: heading,
bold, italic, strikethrough, inline code, bulleted list with a nested item,
numbered list, task list (open and closed), two-line blockquote, five-column
table, fenced code block with a line wider than the bubble, horizontal rule,
link, and a remote image reference. Marker counts, stored versus drawn: `**` 2 to
0, backticks 8 to 0, `|` 30 to 0, `](` 2 to 0, `![` 1 to 0, `---` 6 to 0, and `#`
3 to 1 - the surviving `#` is a comment inside the code block, where it belongs.
Nothing degraded to plain text. The heading, list, quote, table, and code shapes
match the frames from the 3.1 round; the table, the clipped code line, and the
alt-text-only image behave exactly as recorded there.

**Real token cadence**, which is the half the scripted round could not show.
Draft content sampled every 150 ms in the light round: 0, 57, 167, 297, 422, 756,
840 characters - first token inside ~290 ms, the whole ~850-character reply
delivered in 1.83 s (about 460 chars/s, roughly 120 tok/s for a 4B-active MoE
through the front). That is 8-12 parse-and-layout passes per reply under the
100 ms coalescing window, 110-330 characters per pass. Growth appeared at every
sample once the stream started; the largest sample-to-sample gap with no growth
was 406 ms and sits before the first token, i.e. endpoint latency rather than a
rendering stall. A frame captured mid-stream (draft ~320 characters in) shows the
table already drawn as a table with a partially received row - header, one row,
trailing empty cell - the heading already a heading, emphasis already styled, and
no markup characters anywhere in the bubble. The 100 ms window again needed no
change; at this rate a window swallows 10-30 tokens and no frame showed paint
lagging arrival. The honest limit is the one named in the debt list above: no
frame-timing instrumentation exists on this surface, so "smooth" here means
monotonic sampled growth plus a structurally correct mid-stream render, not a
dropped-frame count.

**No destination beyond the configured base URL**, observed three ways:

1. `ss -tunap` polled every 2 s on the device for the whole round: the app uid
   held exactly one outbound socket at every poll, an ephemeral loopback port to
   `127.0.0.1:18443`, which is the forwarded stand-in for the configured base
   URL. Its only other entries were the VM-service listener the test harness
   dials. No other socket ever belonged to the app.
2. The relay logs every accepted connection and its upstream peer: one connection
   per round, each to the front's tailnet address over TLS 1.3, and nothing else
   for the whole session.
3. In-process at the end of each round: `find.byType(Image)` finds nothing and no
   `NetworkImage`-backed widget exists, so the `![diagram](https://example.com/diagram.png)` present in the stored reply drew its alt text and resolved
   nothing; the device-side capture holds no DNS query at all (`udp port 53`
   filter returns empty).

Newly visible on real model output, added to the debt list:

- **Table widths bite again**: five columns, words broken mid-syllable - `Regi/on`,
  `Cach/e`, `Verd/ict`, `eu-/wes/t`, `war/m`, `kee/p`. Same debt as 3.1, now with
  a real model's table as the exhibit.
- **An inline code span holding a hyphen splits across a line break and draws as
  two separate chips** - `sub-` at the end of one line, `optimal` at the start of
  the next, each with its own background. Cosmetic and minor, but it is a shape
  the hermetic fixtures do not contain, and it reads as a typo rather than a code
  span.
- The code block's hairline outline in dark mode reads brighter than the design
  guidelines' calm bar wants. Noted, not changed: the same decoration is what
  gives the block its edge in dark and it passes the contrast test.

Frames sit in the git-ignored build directory (`build/l-1-upper.png`,
`build/l-mid.png`, `build/d-1-upper.png`), not in the commit. The probe that
drove them (`integration_test/live_markdown_round_test.dart`) and the relay live
outside the tree and are removed once this round is recorded, so nothing
committed references them.
