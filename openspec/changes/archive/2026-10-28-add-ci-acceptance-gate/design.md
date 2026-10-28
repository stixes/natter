# Design

## Context

The project already has two gates, both manual: `flutter analyze && flutter
test` in the dev container before a commit, and the acceptance release gate
(`scripts/accept.sh`, governed by the `acceptance-testing` spec) on the
always-on emulator on `<dev-box>` before a release. The gate resolves its target
device from `NATTER_ACCEPT_DEVICE`, or from the single device `adb devices`
reports, and it needs no endpoint, credential, or `--dart-define` value: the
suite serves its own endpoint on the device's loopback. That hermeticity is the
fact that makes unattended CI possible at all.

The dev container deliberately contains no Android emulator (stack rule:
on-device testing goes through host-forwarded adb). So a CI build must supply
its own device, and it must not quietly reintroduce an emulator into the
container.

The toolchain the project actually tests against is pinned by
`.devcontainer/Dockerfile`: Flutter 3.29.3, JDK 21, Android command-line tools,
`platforms;android-35`, `build-tools;35.0.0`, platform-tools. The image re-checks
its own pins at build time and fails loudly if one moves. That pattern is worth
copying rather than reinventing.

See proposal.md - Why for motivation.

## Goals / Non-Goals

**Goals:**

- A commit's releasability is readable from the commit, without asking a
  developer what they ran.
- The acceptance gate runs where nobody has to be present, on a device the build
  creates and destroys.
- The build's verdict is legible enough to act on: which stage failed, and
  whether the gate ever ran.
- Toolchain drift between the dev image and CI is caught, not silently tolerated.

**Non-Goals:**

- Design-level: no build system for release artifacts (no APK published from
  CI, no signing, no distribution), no branch protection or required-check
  configuration in GitHub settings (the verdict is read by the person or agent
  who pushed, not enforced by the platform), no flaky-test retry policy, no
  coverage or performance tracking, no multi-API-level matrix.
- No change to the acceptance suite, its scenarios, its gate command, or the
  app's runtime behavior; those are governed by `acceptance-testing` and are
  untouched here.

## Decisions

### GitHub-hosted runner, not self-hosted

The build runs on GitHub-hosted `ubuntu-latest`. The suite is hermetic, so CI
has no use for the tailnet, and keeping GitHub-initiated jobs off the home
network means a workflow run on a public repository cannot reach
`<llama-swap-host>` or the always-on box. Alternatives considered: a
self-hosted runner on `<dev-box>` (near-zero setup, reuses the proven emulator,
and would run the suite in ~the same time as locally; rejected because it makes
the home machine CI infrastructure and puts any workflow run on the tailnet);
a container job using the dev image itself (exact parity, but the emulator and
system image would have to be installed into the container per run and KVM
access from a container job is not guaranteed - the parity benefit is preserved
instead by the pin check below).

KVM is available on hosted Linux runners but group permissions must be opened
in the job (the documented udev step). `scripts/ci-emulator.sh` fails fast if
`/dev/kvm` is missing, so the failure lands in the provisioning stage rather
than in a boot timeout.

### Two jobs, ordered by cost

`checks` runs the toolchain pin check, `flutter analyze`, and `flutter test`:
roughly two minutes, no device. `accept` runs the same pin check, boots the
device, runs `scripts/accept.sh`, and tears the device down. The gates run in
parallel, so an analyze failure does not have to wait behind an emulator boot,
and a device failure does not hide an analyze failure. Alternative considered:
one job with all three stages (one cold start fewer, but every cheap failure
then pays for an emulator boot, and the verdict becomes harder to read).

The pin check runs in both jobs rather than in a shared setup job: two jobs each
verifying their own toolchain is cheaper than a dependency edge, and it keeps
each job self-contained and re-runnable on its own. What it checks differs by
job: Flutter and JDK in `checks`, where the Android SDK plays no part (analyze
and the Dart test suite need no Android toolchain), and the Android platform and
build-tools packages in `accept`, after device provisioning has installed them.
Checking SDK packages before they are installed would manufacture a failure that
means nothing.

### Device bring-up lives in the repo, not in an action

`scripts/ci-emulator.sh` installs the exact SDK packages
(`platforms;android-35`, `build-tools;35.0.0`, `platform-tools`, `emulator`,
`system-images;android-35;google_apis;x86_64`), accepts licenses, creates the
AVD, launches it headless with software rendering, waits for boot, and prints
the device serial. The workflow then runs
`NATTER_ACCEPT_DEVICE=<serial> scripts/accept.sh`, which is the gate unchanged:
the existing `NATTER_ACCEPT_DEVICE` seam is the whole integration point, which
is why no `acceptance-testing` delta is needed. The script also captures
logcat to a file so the gate's device-side evidence survives the run.

Alternative considered: a maintained community emulator action (battle-tested
boot, wait, and teardown; fewer lines here). Rejected because it hides the exact
versions the project insists on pinning, and adds an external dependency to
track. It is the named fallback if hand-rolled bring-up proves flaky in
practice; the fallback is a workflow-file change only, since the boot logic
already sits behind one script.

`google_apis`, not `google_apis_playstore`: the Play image is larger, slower to
boot, and the suite needs neither Play Services nor a Play Store.

### System image at API 35, matching the compile pin

The CI device is an `android-35` x86_64 image, matching the platform the app
compiles against. The local default target is an API 36 emulator. That gap is
accepted rather than papered over: the acceptance suite asserts shipped-spec
behavior, which is not API-level specific, and CI is not the place that
discovers an API-level regression. Recorded as a standing debt in the change's
validation record: the shipped emulator target (API 36) is only ever exercised
by local rounds.

### Triggers and deduplication

`push` to any branch, `workflow_dispatch` for an explicit run, and
`pull_request` guarded to fork pull requests only. Same-repository PR heads are
already built by the push to their branch, so a commit is built once.
`pull_request_target` is deliberately not used: it would run fork code with
base-branch credentials, and CI holds no secrets to protect but the token would
still be write-scoped.

### Newest push wins, except on the default branch

`concurrency` is grouped per ref with `cancel-in-progress` on for non-default
branches and off for the default branch, where every commit must reach a
verdict. Alternatives considered: cancel everywhere (leaves the default branch
with a cancelled run and therefore no verdict, which is exactly the state the
monitoring rule must not mistake for green); cancel nothing (older runs finish
and the queue lags behind the branch).

### Stage names carry the verdict

Steps are named so a failure reads as a stage: `Check toolchain pins`,
`Provision device`, `Run acceptance gate`. A boot failure fails the
provisioning step, so the run says the gate never ran instead of claiming the
build is not releasable. On failure, an always-run step uploads the emulator
log, the captured logcat, and the test output.

`timeout-minutes` bounds each job so a wedged emulator boot reads as a failed
stage rather than an indefinitely pending run, and a pending run is the same
trap as a cancelled one: no verdict.

### Toolchain pins are declared twice, on purpose, and checked against drift

The workflow keeps its versions in one `env:` block with a comment pointing at
`.devcontainer/Dockerfile` as the sibling definition. Deriving one from the other
(a generated workflow, or an image-based job) was rejected as more machinery
than a two-line pin set warrants, so drift is instead caught at run time by the
pin check step, which greps the same version strings the image greps at build
time. If the two ever disagree, the first job to run fails.

### Caching is speed, not a dependency

pub and Gradle caches are restored from a key derived from `pubspec.lock` and
the Gradle build files, and saved on success. A cache miss costs minutes, not
correctness, so a cold cache is never a reason for a red verdict.

## Risks / Trade-offs

- [Ephemeral emulator bring-up is flakier than the always-on emulator] → versions
  are pinned, boot has an explicit wait with a bounded timeout, the failing
  stage is named, and device evidence is uploaded. No automatic retry of the
  gate: a re-run hides a real failure and turns the verdict into noise. If
  flakiness persists, the community emulator action is the named fallback, and a
  self-hosted runner becomes its own proposal.
- [Runner image drift changes the preinstalled SDK under the build] → the build
  installs the versions it needs by explicit package id and verifies them
  before testing, rather than trusting what the image happens to carry.
- [Hosted CI never exercises the app's own TLS handshake or a real model's
  markdown output] → live-endpoint rounds stay local and human-run and remain
  the definition-of-done requirement they already are; the CI record says so
  plainly rather than implying end-to-end coverage.
- [Two places to keep in step: the dev image and the workflow's pins] → one
  `env:` block, a pointer comment, and a pin check that fails on the first
  mismatched version.
- [The monitoring rule depends on a human or agent actually looking] → the
  verdict is attached to the commit and the rule lands in `AGENTS.md` as a step
  in the definition of done; the enforcement is procedural, not platform-side,
  because required-check and branch-protection configuration is out of scope.
- [Public repository, hosted runners, free minutes] → no cron schedule, no
  matrix, cancellation of superseded runs, and fork PRs run without secrets and
  with a read-only token. The cost is a few minutes per push.

## Migration Plan

1. Land `scripts/ci-emulator.sh` and `.github/workflows/ci.yml` in one commit;
   the first push to any branch produces the first verdict.
2. Watch the first runs to confirm stage timings and that the budget holds;
   record timings in the change's validation record.
3. Update `README.md`, `.devcontainer/README.md`, and `AGENTS.md` in the same
   change so the instructions match the new reality the day it exists.
4. Rollback is deletion of the workflow file: nothing else depends on CI, and no
   app, build, or device behavior changes.

## UX and interaction

No user-facing surface: the app is untouched, and there is no screen, state,
motion, dark-mode, or accessibility consequence to this change, so those rows
from openspec/design-ux-guidelines.md do not apply.

The developer-facing surface is the verdict, and it gets the same care as copy:

- **States**: pending (no verdict yet - the trap case), cancelled (no verdict,
  not a pass), failed-at-provisioning (the gate never ran), failed-at-gate (the
  build is not releasable, and the failing scenario is named), and passed. The
  wording of each stage name and each failure must keep those five readable
  without opening logs, because the monitoring rule depends on reading the
  verdict at a glance.
- **Copy**: job and step names are the interface - `checks`, `accept`,
  `Check toolchain pins`, `Provision device`, `Run acceptance gate`. Failure
  output must name the stage and, for a gate failure, name the scenario, which
  the gate already does by contract.
- **Accessibility**: nothing in-app to audit. The verdict is GitHub's own
  Checks UI, which is not this project's to design.

## Open Questions

- Should CI also run `openspec validate --all --strict`? It is cheap in wall
  clock but drags a Node toolchain and the OpenSpec CLI into CI for a check that
  only matters on the days specs move. Deferred; it is an additive step and
  changes nothing here.
- Whether pub and Gradle caching stays on after the first runs, once real
  timings show how much it saves. Either answer is a workflow tweak.
