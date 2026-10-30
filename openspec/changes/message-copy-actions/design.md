# Design

## Context

See `proposal.md` - Why and What. Constraints that shape the approach:

- User turns are `SelectableText` (`lib/ui/message_bubble.dart:101`); rendered
  replies are `MarkdownBody(selectable: true)`, and the package builds each
  block as its own `SelectableText.rich`
  (`flutter_markdown_plus-1.0.7/lib/src/builder.dart:980`). A long-press on the
  text region is therefore already owned by selection, which is why the
  whole-turn affordance is a control rather than a long-press menu.
- The turn's footer already exists: the timestamp `Text` sits at the end of the
  bubble's `Column` (`lib/ui/message_bubble.dart:110-118`), and the
  `message-timestamps` capability keeps its requirement intact, so the copy
  control rides in that footer rather than replacing it.
- The draft bubble reuses the same bubble widget with a placeholder label
  (`lib/ui/chat_screen.dart:383`), so committed vs in-flight is a property the
  bubble has to be told, not inferred.
- Code blocks are built inside the package: a `pre` block's text is wrapped in
  a horizontal `Scrollbar` + `SingleChildScrollView` and then decorated with
  `codeblockDecoration` (`builder.dart:344-357, 470-476`). The scroll wrapper
  is private, so taking over the block means reproducing it.
- Clipboard writes come from `package:flutter/services.dart`, already available;
  no new dependency (see proposal - Impact).

## Goals / Non-Goals

**Goals:**

- One whole-turn copy control per committed turn, both roles, and one copy
  button per rendered fenced code block.
- The code block keeps exactly the behaviour `reply-rendering` pins today:
  sideways scroll, theme-following tint, selectable monospace text.
- Copy feedback stays in the control that made the copy.

**Non-Goals:**

- No selection across block boundaries (the named
  `render-markdown-replies` debt stays named), no custom selection toolbar, no
  select-all.
- No change to what is stored, sent, or rendered; no new setting; no new
  surface for bulk copying (that is the `conversation-export` destination).
- No change to the `Waiting` / `Thinking` placeholder, cancel, retry, or error
  surfaces.

## Decisions

**1. The whole-turn control lives in the footer row, always visible.** A
`Row` holding the existing timestamp `Text` plus one `IconButton`
(`Icons.content_copy`, 48x48 through the default `IconButton` sizing), inside
the bubble's existing `Column`, so placement is where the timestamp already
sits. Chosen over: a long-press menu (cannot coexist with selection over text,
and the guidelines forbid long-press as the only path); a hover/reveal
affordance (Android has no hover, and reveal-on-tap hides a common action); a
bubble-wide overlay (would cover text and steal taps). Always visible rather
than revealed, because on a touch surface a hidden control is an invisible one.

**2. The bubble is told whether it is committed.** `MessageBubble` grows a
`copyText` parameter: a committed turn passes its text, `_DraftBubble` passes
null, and a null `copyText` means no control and no code-block button. Chosen
over a `bool committed` flag, because the text to copy is what the control
needs anyway, and the null case makes the absence of the affordance explicit.
Alternative considered: reading the draft state from `placeholderLabel
!= null` - rejected, because the draft bubble shows the placeholder only while
waiting, not once text has begun arriving, which is exactly the in-flight state
that must carry no control.

**3. Code blocks are taken over by a `pre`-element builder.** A
`MarkdownElementBuilder` registered under the `pre` key in `_ReplyMarkdown`'s
`builders` map, with `visitText` building the block: a `SelectableText.rich`
over a `TextSpan(style: sheet.code, text: text.text)` (what the package's own
delegate produces, `widget.dart:424-429`, trailing newline stripped), wrapped
in the `Scrollbar` + horizontal `SingleChildScrollView` with
`codeblockPadding`, with the copy button above that scroll view inside a
`Column`. `visitElementAfterWithContext` returns null so the package's own
`Container(decoration: codeblockDecoration)` still draws the tinted box and the
`pre` block stays a block element. The builder is constructed with the same
style sheet `_ReplyMarkdown` passes, so code text, box, and button all stay on
theme tokens.
Chosen over: registering a `code` (inline) builder, which is the wrong
element; painting the button over the block in a `Stack`, which covers code
text and fights the sideways scroll, against the spec scenario; wrapping
`MarkdownBody` in a widget that finds block bounds after layout, which is
fragile and needs no help from the block; patching the package, out of the
question.
Trade-off, named: the package's own scroll wrapper (`_ScrollControllerBuilder`)
is private, so the scroll and its `Scrollbar` are reproduced here, one
controller per block. If the wrap-versus-scroll decision ever lands, this
builder is where that change goes.

**4. The copy button sits above the block's text, not over it.** A small row
inside the tinted box, before the scroll view. It never overlaps code text, and
the scroll view keeps the box's whole width, so the drag region is untouched.
Alternative: an overlay pinned to the block's top-right, cheaper vertically
but it covers the first code line and steals taps from the scroll.

**5. Feedback is the control's own icon swap.** On tap, the icon becomes
`Icons.check` for about 1.2 s, on a `Timer` held by the control's state and
cancelled on dispose - the same self-owned-timer pattern as
`AnimatedPlaceholder` (`lib/ui/message_bubble.dart:26-52`). The control's
semantic label swaps to match, and the swap is announced through a live-region
semantics node so a screen reader hears the copy happened. Chosen over a
`SnackBar`: a snackbar on every copy is a blocking-ish surface over the
transcript, and the guidelines ask for motion that explains state, not noise.
A tooltip-only change is not announced reliably, so it is not the channel.

**6. Copy text is whatever the turn holds, not what the screen drew.** A
committed assistant turn copies `ChatMessage.content`; a user turn copies the
typed string. The blank-answer fallback already resolves into `content` at
commit time (`lib/domain/assistant_draft.dart:48` `resolveFinalContent()`), so
a fallback reply copies the text that was displayed with no special case. The
code-block button copies the `pre` text node's characters, including line
breaks and indentation, with the same trailing-newline strip the package
applies, so a pasted block does not end on a blank line.

**7. Clipboard reads in tests go through the platform channel.** The
acceptance harness gains one helper that calls `Clipboard.getData` (the real
channel on the emulator, no shell-out) and one finder for the copy control by
icon plus its semantic label. Asserting the clipboard, not just the icon swap,
is what makes the scenario meaningful.

## UX and interaction

Per `openspec/design-ux-guidelines.md`.

- States: committed user and assistant turns show the footer control; an
  in-flight draft shows none, including for a code block mid-stream; a partial
  answer committed on cancel shows one; a failed reply shows none beyond
  Retry. An empty conversation shows no controls. Copy has no loading state of
  its own - the write is instant.
- Motion: icon swap to `Icons.check` and back, no fade or scale. No new
  animation timer beyond the control's own, which stops on dispose. Nothing
  about streaming, auto-scroll, or the placeholder changes.
- Accessibility: icon-only controls carry labels (`Copy message` for a turn,
  `Copy code block` for a block); the result is announced through a live
  region; targets are 48x48 dp; text scaling must not clip the footer row;
  long-press stays as the selection path and is not the only path to copy.
  TalkBack round in the on-device task.
- Copy (strings): tooltips on the controls are the label text, no snackbar
  copy. No new prose beyond those labels.
- Dark mode: the control uses `colorScheme` tokens (`onSurfaceVariant` ink on
  the assistant bubble, the bubble's own ink on a user turn); the code-block
  button inherits the block's tokens. Both themes are covered by the existing
  contrast test pattern (`test/message_bubble_contrast_test.dart`) extended to
  the new pairs - no widget hard-caps a colour.
- Keyboard/focus: the copy control joins the existing focus order after the
  composer; no new focus trap.

## Risks / Trade-offs

- Reproducing the package's code-block scroll wrapper means the block's
  scrollbar discoverability debt (`render-markdown-replies/validation.md`) is
  ours to keep rather than inherit. If a reproduced scroll and a scroll the
  package produced drift apart in feel, that is the debt re-tested by the
  updated acceptance scenario, not something new.
- The custom `pre` builder runs on every draft render tick (the coalesced
  100 ms path), so a block that appears mid-stream can flash a button that
  must not be there. Mitigated by decision 2: the draft's markdown path passes
  `copyText: null`, and a streaming case in the unit tests pins it.
- `visitText` hands the block's text node, whose characters may differ from
  what the fenced source contained (the package strips a trailing newline and
  the parser trims fence edges). Mitigated by copying the same string the block
  renders, never the fenced source, plus an on-device paste-back check for a
  block with leading indentation.
- A platform selection toolbar over a block can sit on top of the block's copy
  button. It costs nothing to accept: the toolbar's own Copy is the partial
  path and does the same job for the selected range. Named, not fixed.
- Control rows add vertical height to every committed turn and every code
  block. Accepted as the price of an always-visible affordance; the timestamp
  row already exists, so a turn grows by one row's worth of height, not two.
- The device clipboard is shared with the rest of Android, and Android caps
  clipboard size for some content types. Accepted: a long reply that the
  platform refuses to hold is the platform's call, and the app writes nothing
  to compensate. Named in tasks as an observed case, not handled.

## Open Questions

- Whether the footer control should also appear on a turn the user has not yet
  scrolled to see (no layout change needed either way) - deferred, does not
  change specs or tasks.
