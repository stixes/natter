# Tasks

## 1. Harness

- [x] 1.1 Create `integration_test/accept/harness.dart`: loopback `HttpServer` helper with scripted SSE writers (normal deltas + `[DONE]`, malformed lines, reasoning-only deltas, immediate failure), settings-fill helpers that drive the settings screen UI, and an app start/relaunch helper reusing `main()`'s restore path. Verify: a smoke scenario (configure, send, scripted reply streams and commits) runs green on the `<dev-box>` emulator via `flutter test integration_test/accept -d emulator-5554`.
- [x] 1.2 Name every scenario after the spec requirement it confirms and put a scenario-to-requirement map in each file header. Verify: each scenario's `test()` name starts with `<capability> / <requirement>:` and headers cite the shipped spec file.

## 2. chat-streaming scenarios

- [x] 2.1 First-launch unconfigured: setup guidance shows and Send is inert. Verify: scenario green on the emulator from a `pm clear` state.
- [x] 2.2 Configure endpoint and model, send, scripted deltas stream in pieces, reply commits and persists. Verify: scenario green on the emulator.
- [x] 2.3 Cancel mid-stream keeps the partial answer; cancel during thinking commits nothing. Verify: scenario green on the emulator with a slow scripted writer.
- [x] 2.4 Unreachable port shows the failure surface; Retry after fixing the config succeeds. Verify: scenario green on the emulator.
- [x] 2.5 Reasoning-only stream lands the blank-answer fallback. Verify: scenario green on the emulator with reasoning-only deltas.

## 3. conversation-history and message-timestamps scenarios

- [x] 3.1 History round trip: send in chat A, start chat B, drawer lists both, in-process relaunch restores A's turns from storage. Verify: scenario green on the emulator; validation.md also records one manual cold-start (`am force-stop` + relaunch) round.
- [x] 3.2 Committed turns show a timestamp; the in-flight placeholder shows none. Verify: scenario green on the emulator.

## 4. Gate command

- [x] 4.1 Add `scripts/accept.sh`: clean app state (`adb shell pm clear dev.natter.app`), run the suite against the `<dev-box>` emulator (`ADB_SERVER_SOCKET=tcp:<dev-box>:5037`, device id `emulator-5554`), physical `<device>` as fallback; placeholders and a header note, never a real host. Verify: `scripts/accept.sh` exits 0 on a full green run in under five minutes, and exits non-zero naming the failing scenario when one scenario is deliberately broken and then reverted.

## 5. Workflow wiring

- [x] 5.1 Add the acceptance-suite obligation to `openspec/config.yaml` `rules.tasks` (name the scenario to add/update, or record why none applies). Verify: rule text present; `openspec validate add-acceptance-suite --strict` still green.
- [x] 5.2 Add to AGENTS.md: a Definition-of-done line "acceptance suite green (`scripts/accept.sh`)" and a Spec workflow rule carrying the suite obligation. Verify: read the diff; both lines present and phrased as obligations.

## 6. Verification and hygiene

- [x] 6.1 `flutter analyze && flutter test` green inside the devcontainer. Verify: both commands exit 0 in `scripts/podman-shim.sh` (or the documented container entry).
- [x] 6.2 Record the full suite green on the `<dev-box>` emulator in `validation.md` beside the change, with wall-clock time proving the five-minute budget. Verify: `openspec/changes/add-acceptance-suite/validation.md` names device, date, scenario list, and timing.
- [x] 6.3 Publishable scan clean: grep every committed blob in `git rev-list --all` for hosts, addresses, and device names. Verify: scan output clean on the final commit.

## Workflow follow-up

- Archive the change (`/opsx-archive`) so `acceptance-testing` lands in `openspec/specs/`.
