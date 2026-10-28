# Proposal

## Why

Every quality gate in this project is a command that only runs when someone
remembers to run it: `flutter analyze && flutter test` before a commit, and
`scripts/accept.sh` on the emulator on `<dev-box>` before a release. Both are
local habits, so a pushed commit can be silently broken, and the acceptance
evidence that a change is "done" depends on a single always-on machine being
available. A GitHub Actions build makes the verdict automatic, attached to the
commit, and independent of the dev box.

## What Changes

- A GitHub Actions workflow, `.github/workflows/ci.yml`, triggered on a push to
  any branch, on manual dispatch, and on pull requests from forks only, so a
  branch that is also a PR head is not built twice.
- Two jobs: a checks job (`flutter analyze` then `flutter test`) and an accept
  job that boots an ephemeral emulator inside the runner and runs the existing
  `scripts/accept.sh` against it. The acceptance suite itself, its scenarios,
  and the gate command are unchanged.
- Emulator bring-up lives in the repo as `scripts/ci-emulator.sh`, so the boot
  and boot-wait logic is auditable and reusable, and the workflow YAML stays a
  list of pinned versions.
- Toolchain pins mirrored from `.devcontainer/Dockerfile` (Flutter 3.29.3, JDK
  21, Android platform 35, build-tools 35.0.0, platform-tools), re-checked in a
  first step that fails loudly when a pin moves, following the image's existing
  "break loudly instead of drifting" pattern.
- Per-ref concurrency with cancellation of superseded runs, except on the
  default branch, where the newest run must still produce a verdict.
- Project instructions updated: `AGENTS.md` gains a rule that every push is
  watched for its CI verdict before the next step (implementing, archiving,
  releasing), and `README.md` plus `.devcontainer/README.md` point at the
  workflow as the place the gate now also runs.
- No change to the app: no new pub package, no new permission, no new network
  destination reachable by the app, no APK published from CI.

## Capabilities

### New Capabilities

- `continuous-integration`: unattended build verdicts for this repository -
  when a build runs, what it runs, what its verdict means, what evidence a
  failure leaves, and what the project does with the verdict.

### Modified Capabilities

None. `acceptance-testing` is untouched: the gate command, its exit-status
contract, its clean-state start, and the suite's hermeticity all stay as
shipped. CI only supplies a device for the gate to target, which the existing
`NATTER_ACCEPT_DEVICE` seam already covers.

## Impact

- New files: `.github/workflows/ci.yml`, `scripts/ci-emulator.sh`.
- Edited docs: `AGENTS.md` (CI monitoring rule, Dev environment section),
  `README.md` (Verify section, status badge), `.devcontainer/README.md` (the
  gate also runs unattended).
- New external dependencies, all CI-side rather than app-side, each carrying
  its reason: `actions/checkout` (fetch the commit under test),
  `actions/setup-java` (a JDK 21 install whose version is an input rather than
  an apt incantation that the runner image may change under the build), and
  `subosito/flutter-action` pinned to `3.29.3` (a Flutter install whose version
  is an input rather than a download-and-untar script). Android SDK packages and
  emulator bring-up are hand-rolled in `scripts/ci-emulator.sh` rather than
  pulled in as an action, because the package versions must stay explicit in the
  repo, matching the dev image.
- No CI secrets, no credentials, no endpoint configured for CI: the acceptance
  suite serves its own endpoint on the device's loopback and needs nothing
  supplied. Live-endpoint on-device rounds stay local and human-run.
- Runner surface: GitHub-hosted `ubuntu-latest` only. No self-hosted runner, so
  no GitHub-initiated job ever runs on the home network or reaches
  `<llama-swap-host>`.
- Out of scope: publishing or signing a release APK from CI; running
  live-endpoint validation rounds in CI (they need an endpoint and a key that
  CI must not hold); a self-hosted runner; branch protection or
  required-check enforcement (the verdict is monitored, not enforced by
  GitHub); flaky-test retry policy; iOS or desktop builds; performance or
  startup benchmarks. No product non-goal is touched: CI adds no accounts, no
  telemetry, no cloud sync, no on-device inference, and no new app dependency.
