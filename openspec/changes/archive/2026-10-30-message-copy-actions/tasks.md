# Tasks

No task here touches the network path: copying writes only the clipboard, and
no request, storage, or schema behavior changes, so no live-endpoint round is
owed under the network rule. What is owed instead is the visual round the UI
rule asks for (a change that adds controls) and a TalkBack pass, recorded in
`validation.md` alongside the accessibility observations.

The spec delta touches `reply-rendering`, which the acceptance suite covers, so
group 3 updates the existing `reply_rendering_accept_test.dart` fenced-block
scenario and adds scenarios for the new `message-copy` capability. The
rendering scenarios that exist today were written against a block with no
button, so 4.2 is the scenario the modified requirement names.

## 1. The whole-turn copy control

- [x] 1.1 In `lib/ui/message_bubble.dart`, give `MessageBubble` a `copyText`
  parameter per design.md decision 2, and put a `Row` of the existing timestamp
  `Text` plus an `IconButton(Icons.content_copy, tooltip: 'Copy message',
  iconSize: 24, onPressed: ... writing `copyText` through
  `Clipboard.setData`)` inside the existing `Column`, keeping the bubble's
  padding, colour, max width, and placeholder logic untouched. States
  implemented: committed user turn shows the control, committed assistant turn
  shows the control, `copyText: null` shows no control at all. Verify: add
  cases to `test/message_bubble_test.dart` (setup copied from
  `test/chat_screen_test.dart`) that a user bubble and an assistant bubble both
  carry exactly one copy control, and a bubble with `copyText: null` carries
  none; run `flutter test test/message_bubble_test.dart`.
- [x] 1.2 Wire the committed/in-flight split in `lib/ui/chat_screen.dart`:
  committed rows pass `message.content` (which already carries the blank-answer
  fallback text, per `lib/domain/assistant_draft.dart:48`), and `_DraftBubble`
  at `lib/ui/chat_screen.dart:383` passes `null`. States implemented: an
  in-flight reply that has begun producing text shows no control, a committed
  partial answer committed on cancel shows one, a failed reply shows none beyond
  the existing Retry affordance. Verify: streaming cases in
  `test/chat_screen_test.dart` using the `ScriptedChatService` pattern already
  there, plus `flutter test test/chat_screen_test.dart`.
- [x] 1.3 Add the copy confirmation per design.md decision 5: a private
  stateful control whose icon swaps `Icons.content_copy` -> `Icons.check` for
  about 1200 ms on a `Timer` it owns and cancels on `dispose`, following
  `AnimatedPlaceholder`'s self-owned-timer pattern in the same file; keep the
  tooltip/semantic label in step with the icon and mark the announcement with a
  live-region `Semantics`. Verify: `test/message_bubble_test.dart` cases that
  the icon swaps after a tap and back after the interval (advance time with
  `tester.pump`), that a second tap writes the clipboard again, and that
  `SemanticsBinding.instance` semantics carry a labelled button; run
  `flutter test test/message_bubble_test.dart`.
- [x] 1.4 Pin what each role puts on the clipboard, by capturing
  `Clipboard.setData` calls through a `SystemChannels.platform` mock handler in
  the unit tests (the pattern `test/support/test_support.dart` already uses for
  saved turns). Cases: an assistant reply with headings, emphasis, and a fenced
  block lands its raw markdown source; a user turn with markup and a line break
  lands exactly what was typed; a blank-answer fallback reply lands the
  reasoning text that was displayed. Verify:
  `flutter test test/message_bubble_test.dart test/chat_screen_test.dart`.
- [x] 1.5 Extend `test/message_bubble_contrast_test.dart` with the copy
  control's ink pair on each bubble colour, in both themes, computed the same
  way as the existing timestamp pair. Verify:
  `flutter test test/message_bubble_contrast_test.dart` reports AA for the new
  pairs.

## 2. The copy button on a rendered code block

- [x] 2.1 Build the `pre`-element builder per design.md decision 3 and register
  it in `_ReplyMarkdown`'s `builders` map: `isBlockElement() => true`,
  `visitText` returns a `Column` holding the button row plus the code text in a
  `SelectableText.rich` over `TextSpan(style: sheet.code, ...)` inside the
  horizontal `Scrollbar` + `SingleChildScrollView` with `codeblockPadding`
  (reproducing `flutter_markdown_plus`'s private `_ScrollControllerBuilder`,
  `builder.dart:344-357`), and `visitElementAfterWithContext` returns null so
  the package's own `codeblockDecoration` box stays. Verify: cases in
  `test/message_bubble_test.dart` that a fenced block still renders one
  horizontally scrolling block whose text is selectable and legible - i.e. the
  rendered block is unchanged from before the builder existed - and that a
  non-code reply carries no block-level control; run
  `flutter test test/message_bubble_test.dart`.
- [x] 2.2 Give the block its copy button (`Copy code block` label, 48x48 target
  above the scroll view, inside the tinted box) copying that block's text node
  characters with the same trailing-newline strip the package applies
  (`widget.dart:424-429`). Verify: cases asserting through the
  `Clipboard.setData` capture that a reply with prose plus two fenced blocks
  lands only the tapped block's contents, with indentation and line breaks
  intact and no trailing blank line, and that each block carries its own button;
  run `flutter test test/message_bubble_test.dart`.
- [x] 2.3 Suppress the block button for the draft: the draft's markdown path
  carries `copyText: null` per decision 2, so no block builder button appears on
  an in-flight reply. Verify: a streaming case in `test/chat_screen_test.dart`
  that pumps a fenced block past the 100 ms coalescing interval and asserts no
  copy control appears mid-stream, then appears when the reply commits; run
  `flutter test test/chat_screen_test.dart`.
- [x] 2.4 On-device look for the new controls on the emulator on `<dev-box>`
  (`<device>` as fallback): a reply with prose, a short block, and a wide block,
  in both themes, checking that the block's copy button never covers code text,
  that the block still drags sideways, that the footer row is not clipped at the
  largest font scale, and that a TalkBack pass reads each control's label and
  announces the copy. Record what the round showed, plus the clipboard
  paste-back for an indented block, in `validation.md` under this change;
  record any failure as named debt rather than fixing it inside this change.
  - Both themes held: a block's button never covers the code, the wide block
  keeps its full-width sideways scroll, the footer row sits inline. The labels
  only reached the Android tree after a label fix (tooltip alone leaves
  `content-desc` empty) - see `validation.md`. The TalkBack announcement, the
  device's own largest font scale, and the editor paste-back are named debt.

## 3. Acceptance suite

- [x] 3.1 Add the suite plumbing group 3 needs to `integration_test/accept/harness.dart`:
  a `clipboardText()` reader that reads the device clipboard back through the
  real platform channel (`Clipboard.getData` with the text-format constant from
  `Clipboard`, whose import `harness.dart` already carries), and a
  `copyControls()` finder keyed on `Icons.content_copy` plus the semantic label,
  documented in the file's comment block the way the existing readers are.
  Verify: an existing acceptance file still passes unchanged
  (`flutter test integration_test/accept -d "$device"` on the target device)
  before any new scenario is written.
  - `clipboardText()`, `copyControls()`, `codeBlockCopyButtons()`,
  `copyConfirmations()` and `tapCopy()` landed in `harness.dart`; the existing
  suite passed unchanged (4 scenarios, exit 0) before the new file existed.
- [x] 3.2 Add `integration_test/accept/message_copy_accept_test.dart` carrying
  the `message-copy` scenarios: tap the footer control on a committed assistant
  reply and read its raw markdown back off the clipboard; tap it on a user turn
  and read the typed text back verbatim; tap a code block's button and read
  that block alone back; an in-flight reply shows no control; a copy leaves the
  conversation identical for a follow-up request and a reopen. Script the
  endpoint through `harness.dart` like the other files, and give the file its
  own scenario-map comment in the style of
  `reply_rendering_accept_test.dart`. Verify:
  that one file passes on the emulator
  (`flutter test integration_test/accept/message_copy_accept_test.dart -d
  "$device"`), then the whole suite through `scripts/accept.sh`.
  - Five scenarios, all green on the emulator. Each scenario opens on
  `startNewChat()` after `launchApp()`, because the app restores the last
  conversation and stale controls would otherwise count themselves in.
- [x] 3.3 Update the existing `reply-rendering / Assistant replies render as
  markdown` scenario in `integration_test/accept/reply_rendering_accept_test.dart`
  so the fenced block also asserts the block's copy button is present and the
  block's sideways scroll still reaches the clipped characters - the scenario
  the modified `Code blocks stay readable` requirement names. Verify: that file
  passes on the device and the markup-absence assertions still hold.
  - The scenario now finds the block's button and drives the sideways scroll to
  its extent; the markup-absence assertions still hold.
- [x] 3.4 Run the gate: `scripts/accept.sh` on the emulator on `<dev-box>`
  (or `<device>` as fallback) with `NATTER_ACCEPT_DEVICE` set, and confirm every
  scenario file reported a verdict rather than a skip.
  - 21 scenarios across six files, every file verdicted, exit 0.

## 4. Close-out

- [x] 4.1 Add the `CHANGELOG.md` entry in user-facing wording (copy a reply, a
  turn, or a single code block), and check the surface against
  `openspec/design-ux-guidelines.md` per the apply guidance, noting any
  deliberate exception in this change's record. Verify: the entry names the two
  controls, no commit-speak.
  - The entry names the turn control and the per-block button. The one surface
  deviation to weigh: the guidelines' keyboard/emoji bar is untouched, this
  change adds no text input, and the guidelines' no-long-press-as-only-path rule
  is what the visible controls satisfy.
- [x] 4.2 Run `flutter analyze && flutter test` in the devcontainer, then read
  - `flutter analyze`: no issues. `flutter test`: 226 green, 22 of them this
  change's. CI verdict read on the pushed `main` commit: run 41025247852,
  completed success, 11m49s, both the `checks` job and the `accept` job green
  on its throwaway emulator - so the acceptance suite, this change's scenarios
  included, passed in a clean device environment too.
  the pushed commit's CI verdict with `gh run list --branch <branch> --limit 1`
  and record it. Verify: analyze clean, tests green, a CI verdict named rather
  than assumed.
- [x] 4.3 Run the publishable scan over commits and the published tree as
  - 785 blobs across 52 commits scanned, then the pushed tree. Hits all benign:
  the generic word "tailnet", `<dev-box>` and friends as placeholders, the
  fixture key `sk-test-secret-value`, loopback `127.0.0.1` (the acceptance
  endpoint the suite serves for itself). No hostname, no device, no live key.
  This change's artifacts and `validation.md` carry placeholders only.
  - One finding outside this change: an earlier commit *message* (9fb5a3f,
  "Keep hosting references generic...") names a LAN address in prose about the
  move to RFC 5737 space. AGENTS prescribes rewriting the leak out of history
  rather than layering over it; that needs a force-push, so it was surfaced for
  an owner's yes rather than done here.
  AGENTS.md prescribes (`git rev-list --all` blob scan, then the pushed tree),
  and confirm this change's artifacts and `validation.md` carry only placeholder
  hosts and RFC 5737 addresses. Verify: both scans clean with no follow-up
  commit needed.

## Workflow follow-up

- Archive the change with `/opsx-archive` once the review requirements are met,
  so `openspec/specs/message-copy/` exists and `reply-rendering` reflects the
  copy affordance.
- Re-check the debt list this change closes: the copy affordance recorded as
  out of scope in `2026-10-28-render-markdown-replies/validation.md`, and the
  per-block selection, code-block scroll discoverability, and table column
  width debt left named.
