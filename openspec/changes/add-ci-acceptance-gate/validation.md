# Validation

## What ran, and where

CI: GitHub-hosted `ubuntu-24.04`, no repository or organisation secrets, branch
`add-ci-acceptance-gate` and a scratch branch `ci-probes`, 2026-10-28. Every run
below is a push or dispatch on this change's branch unless named otherwise.

Local (dev container, Flutter 3.29.3 / Dart 3.7.2): `flutter analyze` clean,
`flutter test` green, `bash -n` clean on both new scripts, `scripts/ci-pins.sh`
passing in all three modes, `scripts/ci-emulator.sh` refusing to start with
`Provision device: no /dev/kvm on this machine` and installing nothing, and
`scripts/ci-emulator.sh teardown` plus a bogus mode returning the expected exit
codes.

## Green builds

| Run | Shape | checks | accept | whole build wall clock |
| --- | --- | --- | --- | --- |
| `40682816222` | first full green | success (60 s) | success (8 m 48 s) | 8 m 49 s |
| `40688563097` | after the install assertion and the timeout rebalance | success (78 s) | success (8 m 25 s) | 8 m 26 s |
| `40689817038` | `workflow_dispatch`, same tree, Gradle output cache present | success (78 s) | success (10 m 04 s) | 10 m 04 s |

Gate scenario count on CI: `🎉 12 tests passed.` - the same twelve scenarios the
local gate runs on the emulator on `<dev-box>`, which also exits 0.

## Stage timings, and where the budget actually goes (tasks 4.1, 4.2)

Seconds per step, the three green runs above in column order:

| Step | 40682816222 | 40688563097 | 40689817038 |
| --- | --- | --- | --- |
| checkout | 1 | 1 | 1 |
| pin check (declared) | 0 | 0 | 0 |
| setup-java | 1 | 12 | 5 |
| flutter action | 14 | 11 | 15 |
| pin check (running, checks job) | 2 | 0 | 1 |
| analyze | 14 | 15 | 13 |
| unit tests | 22 | 22 | 19 |
| Provision device | 80 | 94 | 86 |
| pin check (Android packages) | - | 5 | 3 |
| Run acceptance gate | 403 | 370 | 473 |
| Tear down device | 2 | 2 | 3 |

The whole build is inside the fifteen-minute budget in every run, with 4.5
minutes of headroom at worst. The stages are: about two minutes of toolchain and
pin checks, about ninety seconds of device provisioning, and then the gate.

**The gate does not fit five minutes on a CI device.** It costs 370-492 s here,
against 162 s (2 m 42 s) recorded for the same command on the emulator on
`<dev-box>` in `archive/2026-10-27-add-acceptance-suite/validation.md`. That is
not a violation of the shipped requirement: the five-minute scenario in
`specs/acceptance-testing/spec.md` is scoped to "the default emulator target",
and a throwaway runner device is not that target. It is a cost of this build, and
the stage that carries it is `Run acceptance gate`.

Where that time goes: `scripts/accept.sh` runs
`flutter test integration_test/accept -d <device>` once over the directory, and
Flutter still performs a build, install and launch cycle per acceptance file -
four files, four Gradle invocations, visible in the gate's own output as four
`Running Gradle task` blocks. The device is new every run, so nothing is warm.

Attempted fix, measured rather than assumed: an explicit `actions/cache` over
`build/app`, `android/.gradle` and `.gradle`, keyed to the inputs of a build plus
the Flutter version. The cache was 228 MB, restored in about four seconds, and the
gate then took 473 s, versus 403 s and 370 s in runs without it. The spread
between runs is wider than the saving, so the step was reverted in
`0e45cc0` rather than left in place.

Debt, named: the CI gate has no budget of its own, and each acceptance file costs
roughly ninety seconds of CI time. At four files the build has 4.5 minutes of
slack; a fifth and sixth file spend most of it. If the gate reaches the nine
minute step cap, the options are two accept jobs splitting the suite across two
devices, a larger runner tier, or fewer acceptance files per build cycle. None is
in scope here.

## Declared pins and drift (tasks 2.2, 2.4)

Scratch-branch commit flipped `ANDROID_PLATFORM` from `35` to `34` in the
workflow's `env:` block. Run `40684317177`: **both** jobs failed at
`Check toolchain pins (declared)`, and every later step in both jobs was
skipped - no analyze, no test, no Gradle, no device:

```text
declared pin "platforms;android-34" does not appear in .devcontainer/Dockerfile
```

The next commit restored the pin, and in the following runs the step passes in
both jobs before any test command, as required.

Locally, the same script catches the other two kinds of drift:
`ANDROID_PLATFORM=34 scripts/ci-pins.sh declared` exits 1 naming the package, and
`FLUTTER_VERSION=3.99.9 scripts/ci-pins.sh running` exits 1 naming the running
version. The Android-package mode is checked in CI after provisioning
(`Check toolchain pins (Android packages)`, 3-5 s per run).

## Triggers, concurrency, and the verdict rule (task 2.1)

- Every push to a non-default branch queued exactly one run for that commit.
- Two pushes six seconds apart on `ci-probes`: the older run
  (`40684294526`) reported `cancelled`, the newer (`40684317177`) reached a
  verdict. This is the `cancel-in-progress: true` arm of the per-ref concurrency
  group.
- `workflow_dispatch` produced run `40689817038` on the same branch.
- `pull_request` is restricted to fork pull requests (`github.event.pull_request
  .head.repo.full_name != github.repository`) so a same-repository PR head is
  built once, by its push. Not exercised: no fork PR exists for this change.
- The default-branch arm has `cancel-in-progress: false`, so a push to `main`
  always reaches a verdict. Not exercised until the archive push to `main`, which
  is the first run that will read it.

## A red gate is attributed to the gate (task 3.3)

Scratch-branch commit changed one assertion in the message-timestamps scenario
from `hasLength(1)` to `hasLength(99)`. Run `40686818003`:

- `checks` success, `accept` failure; the failing step is `Run acceptance gate`.
- The scenario is named in the job output: `message-timestamps / Display:
  committed labelled, in-flight not (failed)`, and `11 tests passed, 1 failed.`
- Evidence artifact `accept-device-evidence-40686818003` retrieved with
  `gh run download`: `emulator.log` 8,826 B, `logcat.txt` 10,885,842 B,
  `sdk-install.log` 15,797 B, `avd-create.log`, `avd-list.log`, `device-serial`,
  and the `gate-ran` marker - so the evidence distinguishes "the gate ran and
  said no" from "no verdict exists".

## A provisioning failure is not a verdict (task 3.4)

Scratch-branch commit pointed `system_image()` at
`system-images;android-35;google_apis;x86_99`. Run `40688618078`:

- `checks` success; `accept` failed at `Provision device`; `Put adb on PATH`, the
  Android pin check, and `Run acceptance gate` were all skipped, so the run cannot
  be read as "the build is not releasable".
- The failure text is the stage name plus the resolver's own complaint:
  `Warning: Failed to find package 'system-images;android-35;google_apis;x86_99'`
  then `Provision device: the Android SDK packages above could not be installed`.
- The evidence artifact held only `sdk-install.log` (1,293 B) and no `gate-ran`.

This command-line tools revision exits non-zero on an unresolvable id, so the
on-disk assertion added in `b7d1ee2` did not fire; it is a backstop for revisions
that exit 0 after skipping a package, which is the case that would otherwise show
up as an avd that will not boot.

## The gate is a guest here (tasks 3.1, 3.2, 6.2)

- `git diff --stat main -- integration_test/accept/` is empty: the suite is
  untouched, so no acceptance scenario changes and none needed adding. The gate
  command, `scripts/accept.sh`, is likewise untouched; CI supplies a device
  through the existing `NATTER_ACCEPT_DEVICE` seam and puts `platform-tools` on
  `PATH` so the gate's own `adb` call resolves.
- No configuration is needed in CI: `gh secret list` returns nothing, there is no
  organisation secret, and `grep -n "secrets\." .github/workflows/ci.yml` returns
  nothing. The suite serves its own endpoint on the device's loopback.
- No acceptance scenario changed, because the delta governs the build rather than
  app behaviour - see the empty app diff below.

## Why no live-endpoint on-device round applies (task 6.3)

`git diff --stat main add-ci-acceptance-gate -- lib pubspec.yaml` is empty: the
app's network path is not touched by this change, and CI runs only the hermetic
suite. The destinations CI itself reaches belong to the toolchain - the Android
SDK download, Google's Maven, `pub.dev`, GitHub's own package registry and API -
not to the app, which makes no network call in a CI build.

## Publishable scan (task 6.5)

Scan over every blob in `git rev-list --all`, then over the pushed tree, for
project hosts, addresses, and device names. Result recorded after the final push
below; the workflow's only non-GitHub hosts are `dl.google.com` (SDK, via the
Android tooling), Google's Maven repository and `pub.dev` (both reached through
the toolchain, not written as URLs in the workflow), plus the action references
`actions/checkout`, `actions/setup-java`, `subosito/flutter-action`. Placeholders
remain placeholders: `<dev-box>`, `<device>`, `<tls-front-host>`, `<model>`.

## Standing debt this change opens (task 6.4)

1. **CI provisions API 35; the app's default local target is API 36.** CI never
   exercises the target the app is normally built against. Any change touching
   platform channels, keystore behaviour, notifications, or anything
   version-sensitive still owes a local round on the emulator on `<dev-box>`.
2. **CI never exercises the app's TLS path.** The suite's endpoint is loopback
   HTTP by design. The open item is recorded in
   `archive/2026-10-22-add-streaming-spine/validation.md` ("TLS on the device is
   unverified") and sharpened in `archive/2026-10-28-render-markdown-replies/validation.md`,
   where a relay made the hop TLS beyond the app while the app's own leg stayed
   cleartext. That round is still owed, and it is not a CI round.
3. **CI never sees a real model's output.** Reply rendering is verified against
   scripted SSE. Model-shaped findings (table column widths, code-block wrapping,
   draft re-render cadence at ~120 tok/s) came from live rounds on `<dev-box>`,
   and any change to reply rendering still owes one.
4. **The CI gate's time cost** is the fourth item, with its numbers and options
   above.
5. **Failing runs carry ~11 MB of logcat.** Within the artifact limit, recorded so
   nobody is surprised by the size of a red gate's evidence.

## Noise seen in the CI gate, not mistaken for findings

- drift prints its debug-only "created the database class multiple times" warning
  once per scenario (each scenario builds its own provider container over the
  same executor). It appears in the CI log twelve times and does not affect the
  verdict. Worth a small change of its own if it keeps costing reading time.
- The CI gate printed `Your project is configured with Android NDK
  26.3.11579264, but the following plugin(s) depend on a different Android NDK
  version` naming `flutter_secure_storage`, `path_provider_android`,
  `shared_preferences_android`, `sqlite3_flutter_libs`, and suggesting
  `ndkVersion = "27.0.12077973"`. Whether the same line appears in a local build
  was not checked here. A build-config change is out of scope for this change and
  would go through its own proposal if taken up.
- `actions/cache` does not save when the job fails, so a red gate run seeds no
  cache; the first green run is always cold.

## Verdict rule in practice (AGENTS.md)

Each push in this implementation was followed by reading the newest run for the
pushed commit before the next step: red runs were fixed on the spot (five
distinct causes: pin-check parsing, an unknown avd hardware profile, `adb` not on
`PATH`, the avd home not being pinned, and serial resolution racing the guest's
registration), and scratch probes were run on a separate branch so that this
branch's verdicts stayed interpretable. No run on this branch was passed over
while pending or cancelled.
