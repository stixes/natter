# Validation record: message-copy-actions

## Unit and widget rounds (devcontainer)

- `flutter analyze` - clean, "No issues found!".
- `flutter test` - green: 226 tests, including 22 new ones for this change
  (`test/message_bubble_test.dart` copy-control and code-block groups,
  `test/chat_screen_test.dart` streaming/fallback/cancel/fail cases,
  `test/message_bubble_contrast_test.dart` the control's ink pair in both
  themes).

## Deviations from the task text

- Task 1.4 asked for the clipboard capture to follow the `test_support.dart`
  pattern for saved turns. It went into a new
  `test/support/fake_clipboard.dart` instead: the clipboard needs a
  `SystemChannels.platform` substitute of its own, not the recording repository,
  and it reads text back through `Clipboard.getData` so no test reaches into the
  mock. It also counts writes (`writes`) so a test can prove a tapped control
  writes again rather than only swapping its icon.
- Task 2.1's builder needed `md.Text`, which `flutter_markdown_plus` does not
  re-export, so `markdown: 7.3.0` is now a direct dependency in `pubspec.yaml`
  for that one import; the package resolves to the same 7.3.0 release the
  renderer already pinned. `pubspec.lock` records the move.
- The horizontal scroll of a `pre` block is reproduced by `_CodeBlockScroll`, a
  small stateful widget holding one controller per block, rather than inline in
  the builder's returned widget - the package's private
  `_ScrollControllerBuilder` is a `StateMachine`-like `StatefulWidget` for the
  same reason.
- The unit pin for "the sideways drag region is not narrowed by the button" is
  expressed as a rect assertion (the button's top edge is at or above the code
  text's top edge, and the button's rect does not intersect the block's
  `SelectableText`), because the test that owns reachability drives the scroll
  position directly, as the existing sideways-scroll test already does.
- The acceptance scenario for the sideways scroll drives the scroll position
  rather than a swipe: a synthetic drag at the block's centre is swallowed by
  the selectable text inside it, so the scenario asserts the extent is there and
  the tail follows the position. A real swipe belongs to the on-device look.
- The copy control's screen-reader label rides on the `Semantics` node rather
  than on the `IconButton`'s tooltip. The on-device round found the difference:
  with the tooltip alone, the Android accessibility tree carried an empty
  `content-desc` for the copy controls; with the label on the node it carries
  `Copy message` and `Copy code block`. The node also carries `button: true`.

## Acceptance gate (`scripts/accept.sh`, emulator on `<dev-box>`)

- Round 1, before this change's scenarios were written: the existing suite was
  green with the harness additions in place (`reply_rendering_accept_test.dart`
  alone, 4 scenarios, exit 0) - the baseline task 3.1 asks for.
- Round 2, whole suite through the gate: 21 scenarios across six files, every
  file reporting a verdict rather than a skip, exit 0. The five
  `message-copy` scenarios and the updated `reply-rendering / Assistant replies
  render as markdown` scenario are among them.

## On-device look (task 2.4, emulator on `<dev-box>`)

Transcript with a bolded line, inline code, a short block carrying an indented
line, and a wide block whose tail is clipped by a sideways scroll, in both
themes. What the screens showed:

- A block's button sits inside the tinted box, above the code, and never on top
  of it. The box keeps its full width, so the sideways region is untouched: the
  wide line's tail sits at the bubble edge and the scroll brings it in.
- The footer row holds the timestamp and the control inline on both bubble
  colours, in both themes, not clipped, and legible on the theme's own tokens.
- The control's target in the Android tree is 126x126 px, which on that device's
  density is 48x48 dp - the bar the guidelines ask for.
- The labels reach the accessibility tree: `content-desc` reads `Copy message`
  and `Copy code block`. That came out of the label fix above; the tree before
  it was silent about both controls.

Left as named debt rather than fixed inside this change:

- **The announcement and the confirmation state on device.** adb taps do not
  reach the app while an integration-test run holds it, so TalkBack could not be
  driven to hear `Copied` and no screen showed the check-mark state. What pins
  them instead: the unit case that asserts a live-region `Semantics` labelled
  `Copied`, the case that asserts the icon swaps and clears on its own timer,
  and the acceptance scenario that finds the check icon on the device after a
  copy. Owed by this change; the manual pass is the thing that stays open.
- **The device's own largest font scale.** The emulator applies
  `font_scale`/`secure font_scale` to a fresh process only after a reboot, so
  the scaled screens never changed between 1.0 and the attempts at 1.3 and 2.0.
  What pins the bar instead is the unit case at a 3.0 `textScaler`: control
  present, target at least 48 dp wide, no layout exception. Owed by this change.
- **The label gap the round found elsewhere.** The app's other icon-only
  controls - Settings, Send, Cancel - carry their name in a tooltip and nothing
  else, and their `content-desc` in the tree is empty, exactly as the copy
  controls did. Fixing those is a separate change; this one only names the debt.
- **The paste-back of an indented block into an editor.** What pins it instead
  is the acceptance read-back of a block through the real platform channel:
  `first_block():\n    return 1` with its four-space indent intact and no
  trailing line.
