# Proposal

## Why

Nothing in the project today confirms on demand that the app is in a
releaseable state. The only end-to-end checks are the task-scoped harnesses in
`integration_test/`, which declare themselves deliberately not CI-clean, take
minutes per round, and need a live endpoint and `--dart-define` values. A
release gate needs simple, hermetic, always-runnable confirmations of the key
behaviors the shipped specs promise.

## What Changes

- A durable acceptance suite under `integration_test/accept/`: shallow tests,
  one file per shipped capability, each naming the spec requirement it
  confirms. Not a detailed diagnostic suite; they exist to answer "is this
  build releasable?"
- The suite is hermetic: each test drives the real app against a scripted
  SSE endpoint served in-process on the device's loopback interface, so no
  external endpoint, key, or `--dart-define` is needed. (The loopback
  destination is created by the test itself and reached by the app's own
  dart:io socket; no new permission and no network destination the app can
  reach on its own.)
- A single gate command `scripts/accept.sh` (clean app state, run suite on the
  emulator on `<dev-box>`, device id `emulator-5554`; a physical `<device>` is
  the fallback): exit code 0 means releasable, and the suite stays under a few
  minutes.
- A new spec capability `acceptance-testing` recording the suite contract,
  including the obligation that future changes touching shipped capabilities
  add or update the suite's scenarios as part of their tasks.
- Workflow edits: `openspec/config.yaml` gains a tasks rule making the
  accept-suite update explicit in every change; AGENTS.md's Definition of done
  gains "accept suite green" and the Spec workflow section names the rule.

**Out of scope:** CI infrastructure or hosted pipelines; cold process-restart
verification (the suite re-launches the app in-process from durable storage,
which is the observable behavior; a true kill-and-relaunch round stays manual);
scenario coverage of history expiry internals (unit-tested logic, not a
user-visible golden path); replacement or removal of the existing task-scoped
harnesses, which still serve the live-endpoint validation.md rounds; any
change to app behavior. No product non-goal is touched.

## Capabilities

### New Capabilities

- `acceptance-testing`: the acceptance suite as a standing capability - what it
  proves, how it runs (single hermetic command), how it maps to shipped specs,
  and the obligation on future changes to grow it.

### Modified Capabilities

- None. No shipped app behavior changes; `chat-streaming`,
  `conversation-history`, and `message-timestamps` specs are unchanged.

## Impact

- New: `integration_test/accept/` (suite files, in-test scripted SSE endpoint,
  shared helpers) and `scripts/accept.sh`.
- Edited: `openspec/config.yaml` (tasks rule), `AGENTS.md` (Definition of done,
  Spec workflow rules).
- No new pub dependency: `integration_test` and `flutter_driver` are already
  dev dependencies, and the scripted endpoint is plain `dart:io`.
- The suite exercises the shipped network path only against its own loopback
  endpoint; the live-endpoint validation.md requirement for network-path
  changes is untouched.

## UX impact

No user-facing surface: the suite and its runner are development tooling. The
app itself is unchanged.
