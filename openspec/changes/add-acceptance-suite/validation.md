# Validation

## Automated checks

Run in the devcontainer against Flutter 3.29.3 / Dart 3.7.2.

- `flutter analyze` — no issues found.
- `flutter test` — 153 tests pass. No production code changed by this change,
  so the suite is unchanged; the run confirms it still passes.

## Acceptance suite run (tasks 1.1, 2.1-2.5, 3.1, 3.2, 4.1, 6.2)

Ran 2026-10-26 from the devcontainer against the always-on Android emulator on
`<dev-box>` (Android 16, API 36), reached through the container-local adb client
(`adb connect <dev-box>:5555`); device id taken from the git-ignored local
notes and passed as `NATTER_ACCEPT_DEVICE`. No physical `<device>` was used.

Command: `scripts/accept.sh` (clears `dev.natter.app`, then
`flutter test integration_test/accept -d <device>`).

Result: **exit 0**, `All tests passed!`, **wall clock 162 s (2:42)** for the
whole gate, from clean app state to the last scenario. That is inside the
five-minute budget in `specs/acceptance-testing/spec.md`.

Scenarios confirmed, in run order:

| # | Scenario | File |
| --- | --- | --- |
| 1 | `chat-streaming / Endpoint configuration: first launch is unconfigured` | `chat_streaming_accept_test.dart` |
| 2 | `chat-streaming / Streaming reply: configure, send, stream, commit` | `chat_streaming_accept_test.dart` |
| 3 | `chat-streaming / Cancel mid-stream: partial answer stays` | `chat_streaming_accept_test.dart` |
| 4 | `chat-streaming / Cancel during thinking: nothing commits` | `chat_streaming_accept_test.dart` |
| 5 | `chat-streaming / Failure and retry: unreachable endpoint, fix, retry` | `chat_streaming_accept_test.dart` |
| 6 | `chat-streaming / Reasoning-only reply: blank-answer fallback lands` | `chat_streaming_accept_test.dart` |
| 7 | `conversation-history / List and switching: drawer, open, relaunch` | `conversation_history_accept_test.dart` |
| 8 | `message-timestamps / Display: committed labelled, in-flight not` | `message_timestamps_accept_test.dart` |

Hermeticity held: the app was configured through the settings screen to
`http://127.0.0.1:<port>/v1` on the device's own loopback interface, served by
the harness `HttpServer`; no external endpoint, no credential, and no
`--dart-define` value was supplied.

The failing-gate behaviour is confirmed from the bring-up rounds: while the
history scenario was still wrong, the same command exited non-zero and named
the failing scenario in its output (`the drawer never listed ...`), and the
chat-streaming cancel scenarios failed the same way before the scripted SSE
writer was flushed per line.

Timing note: the gate runs three separate debug builds (one per scenario file,
about 15-17 s each), so a cold Gradle cache, or a red run that waits out a
scenario's poll deadline, can push a round past five minutes. The budget above
is the green run from clean app state, which is what the gate asserts.

## Manual cold-start round (task 3.1)

The suite proves restore-from-storage by re-running `app.main()` in the same
process. A true process kill cannot be driven from inside an integration test,
so one manual round covered it, on the same emulator and date:

1. Installed `app-x86_64-debug.apk`, launched the app once so it created
   `app_flutter/natter.sqlite`, then force-stopped it.
2. Seeded one conversation ("Cold start check") with a user turn and an
   assistant turn ("Restored from storage.") through
   `adb shell run-as dev.natter.app sqlite3`, using the device clock's epoch
   **seconds** (Drift stores date-times as seconds).
3. `adb shell am force-stop dev.natter.app`, confirmed no process remained
   (`ps -A | grep natter` = 0), then launched the app fresh.
4. Dumped the accessibility tree: it showed `Cold start check` and
   `Restored from storage.`, so the turns came back from durable storage on a
   real cold start.
5. Cleaned up: deleted the seeded rows (0 conversations left), removed the
   pushed APK and the UI dump from the device.

## Findings worth keeping

- `HttpResponse` buffers the whole body until `close()` by default. A scripted
  SSE writer must set `bufferOutput = false`, or a client that reads
  incrementally sees nothing until the response ends - which makes
  "streaming" look broken and made both cancel scenarios fail.
- The history drawer is a `ListView.builder`: only tiles in the viewport are
  built. Anything that asserts on a tile must poll, and must re-open the drawer
  if a rebuild dismissed it, rather than assume the first open stays open.
- A drawer tile's title is the conversation's stored title, not the message
  text, so a drawer assertion should read `ListTile.title`, not scrape texts.

## Debt

None for the suite itself. The over-the-wire latency of the remote adb link is
covered by roomy poll timeouts; no scenario was descoped.
