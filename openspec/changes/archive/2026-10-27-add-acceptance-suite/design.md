# Design

## Context

See `proposal.md` - Why. Constraints that shape the approach:

- `integration_test` runs the test code inside the app's own process on the
  device, so test and app share one process and one network namespace.
- The app's chat client uses `dart:io` sockets directly (AGENTS.md: the
  Android cleartext block does not apply), so a `http://127.0.0.1:<port>`
  endpoint is reachable from the app under test without manifest changes.
- Existing harnesses (`integration_test/streaming_spine_test.dart`,
  `timestamp_visibility_test.dart`, `support/mock_reasoning_endpoint.py`)
  are live-endpoint, `--dart-define`-driven, and declare themselves disposable.
- Config lives in `shared_preferences`, keys in `flutter_secure_storage`,
  history in Drift; `main()` restores the most recent conversation before
  `runApp`. `adb shell pm clear dev.natter.app` already resets all of it for
  the existing rounds.

## Goals / Non-Goals

**Goals:**
- A suite that answers "is this build releasable?" in one command, under five
  minutes, with no external endpoint, key, or build define.
- Every scenario visibly cites the shipped spec requirement it confirms.
- The obligation on future changes lives in three enforceable places: the new
  `acceptance-testing` spec, `openspec/config.yaml` task rules, and AGENTS.md.

**Non-Goals (design-level, beyond the proposal):**
- Production code changes. The suite drives the app through real UI finders;
  no test-only hooks, keys, or entry points are added to `lib/`.
- Replacing the disposable live-endpoint harnesses; they still serve the
  validation.md rounds for network-path changes.

## Decisions

### Hermetic endpoint: scripted SSE server in the test process
The harness binds a `dart:io` `HttpServer` on `InternetAddress.loopbackIPv4`
port 0 inside the integration test, and each scenario configures the app (via
the settings screen, like a user) to `http://127.0.0.1:<port>/v1`. Handlers
script SSE shapes per scenario: normal deltas + `[DONE]`, malformed lines,
reasoning-only deltas, and an immediate-500 for the failure path.

Why over the alternatives: an external mock process (the existing
`support/mock_*.py` pattern) needs host-side process choreography and
emulator-to-host networking; a live endpoint via `--dart-define` is slow,
non-deterministic, and never CI-clean (user decision, Oct 2026). In-process
loopback gives deterministic chunk timing with zero choreography, and keeps
the suite runnable on any device including a physical `<device>`.

### One file per shipped capability, shared harness file
`integration_test/accept/`:

- `harness.dart` - endpoint server + scripted chunk writers, app start/pump
  helpers reusing the `main()` restore path, and settings-fill helpers that go
  through the settings screen UI.
- `chat_streaming_accept_test.dart`, `conversation_history_accept_test.dart`,
  `message_timestamps_accept_test.dart` - scenarios only.

Each scenario's `test()` name starts with the requirement it confirms (for
example `chat-streaming / Cancel mid-stream: partial answer stays`), and a
file header maps scenarios to spec requirements. Alternative considered: one
file per scenario; rejected as churn for a shallow suite.

### Scenario inventory (v1 of the suite)
Shallow confirmations, one outcome each, mapped to shipped specs:

| Scenario | Confirms (spec requirement) |
| --- | --- |
| first launch is unconfigured: guidance shows, Send inert | chat-streaming: endpoint configuration |
| configure, send, scripted deltas stream in, reply commits | chat-streaming: streaming + durable settings |
| cancel mid-stream keeps partial; cancel during thinking commits nothing | chat-streaming: cancel |
| unreachable port: failure surface, Retry after fixing config succeeds | chat-streaming: failures and retry |
| reasoning-only stream lands the blank-answer fallback | chat-streaming: reasoning capture |
| new chat, drawer lists both, relaunch restores turns | conversation-history: list + restore |
| committed turns show a timestamp; in-flight shows none | message-timestamps |

Requirement names are matched to the exact headings in `openspec/specs/` when
the tests are written; the table is the inventory, not the citation text.

### Relaunch restores from storage, in-process
The history scenario sends in conversation A, starts conversation B, then
re-invokes the app's startup path a second time in the same process (fresh
widget tree, fresh provider container reading from Drift/settings). That
proves restore-from-durable-storage, the user-observable behavior. A true
process kill is impossible from inside an integration test (force-stop kills
the instrumentation too); the cold-start check stays manual and is recorded
in validation.md. Alternative considered: two separate `flutter test`
invocations sharing device state; rejected - the gate must stay one command.

### Gate command
`scripts/accept.sh`: `adb shell pm clear dev.natter.app`, then
`flutter test integration_test/accept -d <dev-box-emulator>` with
`ADB_SERVER_SOCKET=tcp:<dev-box>:5037` and device id `emulator-5554` (the
always-on emulator per AGENTS.md; physical `<device>` is the fallback).
Placeholders in the script header, values from the local notes, so nothing
committed names a host. Exit code is the gate's verdict. The script reuses
`scripts/with-container-env.sh` if that is how the toolchain is reached.

### Workflow wiring
- `openspec/config.yaml` `rules.tasks` gains: "Every change whose spec delta
  touches a capability covered by the acceptance suite names the suite
  scenario to add or update in its tasks, or records why none applies."
- AGENTS.md: Definition of done gains "Acceptance suite green
  (`scripts/accept.sh`)"; the Spec workflow section gains the same obligation
  as rule 8. This is what makes the user's ask permanent: config.yaml steers
  proposal-time, AGENTS.md binds apply-time, and the `acceptance-testing`
  spec records it as shipped truth on archive.

## Risks / Trade-offs

- [In-process relaunch could mask a storage bug if anything is cached in
  statics] -> Harness asserts restore by reading through the fresh widget
  tree only; if a static cache turns out to defeat restore-proofing, fall
  back to a manual cold-start round (`am force-stop` + relaunch outside the
  test) recorded in validation.md.
- [Stream pacing flakes on remote adb] -> scripted writers pump chunks with
  generous, fixed delays; scenario helpers use `waitFor`-style polling with
  roomy timeouts; the five-minute budget covers a slow round.
- [Cleartext 127.0.0.1 blocked despite the dart:io exception] -> the app's
  client opens its own `dart:io` sockets (confirmed against `lib/data/` at
  implementation); the first harness smoke run on `<dev-box>` is the proof.
  If it ever fails, the fallback is binding the server on the device's own
  interface - a harness-local detail that changes no spec or task.
- [pm clear does not reset some keystore state] -> the existing live-endpoint
  rounds already rely on `pm clear` for a clean slate; the first run re-tests
  this assumption.

## UX and interaction

No app surface is touched; every row of
`openspec/design-ux-guidelines.md` (states, motion, copy, dark mode,
a11y) is N/A for this change. The only observable output is the test runner's
own pass/fail lines, which follow the shallow-failure rule in the spec: each
failure names its scenario and the observed outcome.

## Migration Plan

No shipped behavior to migrate. Rollback is deleting `integration_test/accept/`
and `scripts/accept.sh` and reverting the config.yaml/AGENTS.md lines.

## Open Questions

- Whether the disposable live-endpoint harnesses get removed once the suite
  is stable - answerable at any later archive, changes nothing here.
