# Proposal

## Why

`openspec/design-ux-guidelines.md` lists "copy affordances" as part of the
polish bar, and the app ships none: to get anything out of a reply the user
must select it by hand, and `flutter_markdown_plus` gives every rendered block
its own selection region, so selecting a whole reply is a per-block drag
(`2026-10-28-render-markdown-replies/validation.md` records that as named
debt). Worse, the per-code-block copy button was named out of scope by
`render-markdown-replies` and its validation file lists it as owed: the
renderer's most useful affordance is the one that never landed. Every
ChatGPT-class client ships per-message copy; a chat client that cannot put
text on the clipboard in one tap reads as unfinished.

## What Changes

- Each committed turn gains one copy control: an icon-only control on the
  turn's footer line, beside the timestamp it already carries. A user turn
  copies exactly what was typed; an assistant turn copies its raw markdown
  source, so pasted text round-trips, including for a reply produced by the
  shipped blank-answer fallback, whose stored text is the reasoning that was
  displayed.
- A rendered fenced code block gains a copy button that copies that block's
  contents alone, without selecting the rest of the reply, and without
  breaking the block's sideways scroll.
- Text selection is unchanged: user turns keep `SelectableText`, rendered
  replies keep their per-block selection and the platform selection toolbar.
  The copy control adds a whole-turn path; it does not replace the partial
  path.
- The in-flight draft gets no copy control. A partial answer committed on
  cancel behaves like any committed turn and gets one.
- **BREAKING** for the acceptance suite's rendering scenario wording: the
  `reply-rendering` "Code blocks stay readable" requirement now carries a copy
  affordance on the block, so the wide, scrollable code block scenario is
  updated rather than left alone.

One deviation from the request this change answers (GitHub issue "Copy and
select text on committed messages"), stated rather than hidden: it prescribes
a long-press action surface. That cannot coexist with the selection this app
already has - `SelectableText`'s own long-press owns the gesture arena over
the text region, so an ancestor long-press never fires there - and the
guidelines forbid long-press as the only path to a common action. So the
whole-turn copy affordance is a visible control, not a menu.

Out of scope: selection across block boundaries (the named
`render-markdown-replies` debt stays named), custom selection toolbar
buttons, select-all, copy-image or copy-an-attachment, sharing a whole
conversation (that is the `conversation-export` destination), wrapping code
blocks instead of scrolling them (a separate proposal already owes that
call), table column sizing, undo/paste-side affordances anywhere else, and
any setting for copying. No AGENTS.md non-goal is touched: no analytics, no
accounts, no cloud, no local inference, no agent or tool UI.

## User-facing surface and UX impact

Per `openspec/design-ux-guidelines.md`, one surface changes: **the chat
screen's committed message bubbles**.

- New control per committed turn: one icon-only copy button in the footer row
  (48x48 dp, screen-reader labelled). The code-block copy button is a second
  control, inside the block.
- Empty: unchanged. Streaming: unchanged - the draft shows no copy control and
  the `Waiting` / `Thinking` placeholder is untouched. Error, cancel, retry,
  offline: unchanged; a failed reply shows no control beyond the Retry already
  offered, and a committed partial answer shows one like any other turn.
- Feedback: the control's icon swaps to a check for a moment after a tap
  (motion explains state, no snackbar); a tap that finds nothing to copy is
  not possible, since the control only appears on turns that have text.
- Dark mode: both controls use scheme tokens only, the same way the bubble's
  code-block tint already does.
- Accessibility: icon-only controls carry labels; the copy result is announced
  for a screen reader. Whole surface stays usable at the largest font scale
  and in both themes. Long-press is not the only path to copy, which is what
  the guidelines require; the platform toolbar keeps the partial-text path.
- Clipboard writes are local: no destination is contacted, nothing is stored
  on the device beyond the clipboard itself.

## Capabilities

### New Capabilities

- `message-copy`: the whole-turn copy affordance - which turns carry a copy
  control, what each role's clipboard text is, the code-block copy button and
  what it copies, feedback, and the rule that copying touches nothing but the
  clipboard.

### Modified Capabilities

- `reply-rendering`: the "Code blocks stay readable" requirement gains the
  copy button on a fenced block, and its wide-block scenario is updated to
  name the button and the scroll it must not disturb; "Rendered replies keep
  text affordances" gains a scenario that pins selection as the partial path,
  untouched by the new whole-turn control.

## Impact

- No new dependency, permission, or network destination: clipboard writes go
  through `flutter/services` `Clipboard` and `flutter_lints`-clean existing
  imports. Nothing is written to storage, no schema change, no change to what
  is sent to the endpoint.
- `lib/ui/message_bubble.dart`: a footer row carrying timestamp plus copy
  control for both roles; a custom `pre`-element builder for the copy button
  on a fenced block (`flutter_markdown_plus`'s builder API replaces the
  package's own scroll-wrapped code text, so the scroll and the block's
  decoration have to be reproduced deliberately).
- `lib/ui/chat_screen.dart`: the committed rows pass their content to the
  copy path, and the draft bubble stays marked as not-committed so it carries
  no control.
- Tests: `test/message_bubble_test.dart` and `test/chat_screen_test.dart`
  gain copy-control cases; `integration_test/accept/` gains a `message-copy`
  file, and `reply_rendering_accept_test.dart`'s fenced-block scenario is
  updated. `integration_test/accept/harness.dart` gains a clipboard reader
  and a copy-control finder.
- Debt this change closes (named in
  `2026-10-28-render-markdown-replies/validation.md`): the copy affordance it
  recorded as out of scope. Debt it leaves named: per-block selection regions,
  code-block scroll discoverability, table column widths.
- Changelog: one user-facing entry about copying a reply, a turn, or a code
  block.
