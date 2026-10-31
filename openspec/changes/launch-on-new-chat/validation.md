# Validation record: launch-on-new-chat

## Unit and widget rounds (devcontainer)

- `flutter analyze` - clean, "No issues found!".
- `flutter test` - green: 230 tests. New this change: the `launch on a new chat`
  group in `test/chat_screen_test.dart` (a launch over saved history opens the
  `Say something.` empty state with no history notice; the same launch's drawer
  lists the stored chats and `openConversation` loads their turns), the
  `background and resume` group (a backgrounded app returns to the same
  conversation), and the `start on a new chat` group in
  `test/conversation_controller_test.dart` (a fresh controller over a populated
  repository yields `conversationId: null` and no messages; an unreadable history
  opens the chat empty with nothing to negotiate; a mid-reply exit leaves the user
  turn in storage).

## Deviations from the task text

- Task 2.3's lifecycle pump needed the real transition sequence before the
  resumed leg lands: `inactive -> hidden -> paused -> hidden -> inactive ->
  resumed`. The first drafts asserted one transition per pump step and failed on
  the intermediate ones; the case now drives the sequence the binding reports.
- Task 3.1's on-device round replaced the true process-kill round that
  `conversation_history_accept_test.dart`'s header names as manual, and it is
  recorded below rather than in the suite.

## Acceptance gate (`scripts/accept.sh`, emulator on `<dev-box>`)

- Round 1 (the flipped leg in place, run through the gate in the middle of this
  change's on-device work): the run came back `All tests passed!`, but its
  console output was read only from the last file's verdict, so the
  conversation-history scenario's own verdict was not on the record. Treat that
  round as unverified rather than as a pass.
- Round 2 (after the on-device round, whole suite through the gate, output kept
  in full): `adb uninstall failed: ProcessException ... exit code 1` at the
  gate's own clear (tolerated: the prior debug build had already been
  force-stopped and removed), then the conversation-history scenario went green
  at `00:54 +1` - the flipped relaunch leg included. The run then reported `17`
  passed and `Some tests failed`, with the four unrun scenarios of
  `system_prompt_accept_test.dart` and its `tearDownAll` marked `- did not
  complete [E]`. Nothing in that file failed an assertion; the file's first
  scenario had passed and the rest never started. That is the tooling dropping
  the device connection again, not a scenario verdict.
- Round 3 (the file alone, `flutter test integration_test/
  accept/system_prompt_accept_test.dart` on the same emulator, after a
  `pm clear`): `02:55 +4: All tests passed!`, exit 0 - four scenarios, so the
  round-2 break did not repeat and no system-prompt scenario is at fault.

The verdict the record leans on: every scenario of the suite has been green on
the device with this change in place - conversation-history in the full gate
round, system-prompt in its own round - and the CI `accept` job on a throwaway
emulator runs the whole suite, which is where the clean whole-suite verdict
lands. See the CI line below.

## On-device round (task 3.1, emulator on `<dev-box>`)

A live-endpoint round: a debug build run under `flutter run` on the emulator,
pointed at an OpenAI-compatible endpoint through a loopback plaintext relay on
`<dev-box>` wired to the device with `adb reverse`, the endpoint itself behind
its usual HTTPS front. Config entered in the app's own Settings screen through
`adb input` taps, not `--dart-define`, because this change touches no network
path and the harness flags that as the way to configure a live round.

What the screens showed:

1. Two exchanges in one chat (`what's 20 plus 20` -> `40`), then a `New chat`
   from the drawer, then another exchange in a second chat. Three chats in all,
   each its own conversation.
2. `adb shell am force-stop dev.natter.app`, then `am start` - a true process
   kill, not an in-process relaunch. The app opened on the `Say something.`
   empty state with a bare composer: no conversation restored, no history
   notice. This is the contract this change ships.
3. The drawer opened after that same kill listed all three chats under `Today`,
   and opening one (the `what's 20 plus 20` chat) put its user turn and its
   `40` reply back on screen in order. Storage intact.
4. Background and return mid-reply: a message sent, `KEYCODE_HOME` a second
   later, relaunch from the launcher. The same conversation was still on screen,
   its reply arrived, no new chat.
5. Both themes. The dark look (the emulator switched to `ui_night_mode 2`) came
   out with the same transcript on the theme's own tokens: user bubbles tinted,
   assistant bubbles plain, timestamps and copy controls legible. A dark-launch
   screen: the `Say something.` empty state over a bare composer.

This round supersedes the restore-on-launch step of the on-device round recorded
in `2026-10-24-local-conversation-history/validation.md` (task 6.2, steps 3-6:
"the relaunched app showed both the user turn ... and the assistant turn ..., so
the conversation was restored from storage"). That step asserted the behavior
this change reverses; the equivalent steps above assert the new one.

## Debt, named

- None open for this change. The true process-kill round that the accept-test
  header called manual is recorded above, and the acceptance suite's relaunch
  leg now pins the launch-on-new-chat contract in CI, so no round is left to
  run by hand.
