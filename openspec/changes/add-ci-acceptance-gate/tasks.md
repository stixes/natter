# Tasks

## 1. Device bring-up script

- [x] 1.1 Write `scripts/ci-emulator.sh`: preflight check that `/dev/kvm` is
      present and usable before anything is downloaded, then install the exact
      SDK packages (`platforms;android-35`, `build-tools;35.0.0`,
      `platform-tools`, `emulator`, `system-images;android-35;google_apis;x86_64`),
      accept licenses, create the AVD, launch it headless with
      `-gpu swiftshader_indirect` and no animations, wait for boot, and print
      the device serial. Follow the preflight-then-work shape of
      `scripts/accept.sh` rather than failing inside a download. Verify: the
      script exits with a readable "no KVM" message when run inside the dev
      container (which has neither `/dev/kvm` nor an emulator) without
      installing anything, and `bash -n scripts/ci-emulator.sh` is clean.
- [x] 1.2 Add teardown and device-side evidence to the script: an exit trap that
      stops the emulator, and a background `adb logcat` written to a file the
      workflow can upload. Verify: after a scripted boot-and-exit round on a
      machine that has KVM, the logcat file is non-empty and no emulator process
      remains. On the dev box, where KVM is absent, verify the trap and the
      logcat path by reading the script and confirming the trap covers the
      preflight-failure path too.
- [x] 1.3 Bound the boot wait with an explicit timeout that fails with the
      message `Provision device: emulator did not boot within <n>s`. Verify: run
      the script with an impossible AVD name on a KVM host, or read the timeout
      branch and confirm the failure text names provisioning and the timeout; a
      CI run must never sit waiting indefinitely.

## 2. Workflow file and the cheap checks job

- [ ] 2.1 Create `.github/workflows/ci.yml` with triggers `push` to every
      branch, `workflow_dispatch`, and `pull_request` restricted to fork pull
      requests so a same-repository PR head is built once; `concurrency` grouped
      per ref with `cancel-in-progress` on for non-default branches and off for
      the default branch; `timeout-minutes` on every job; and an
      `actions/checkout` step as the first step of each job. Verify: one push to
      a scratch branch produces exactly one run for that commit, and pushing
      twice in quick succession cancels the first run while the second reaches a
      verdict.
- [x] 2.2 Declare the toolchain versions in a single `env:` block (Flutter
      3.29.3, JDK 21, Android platform 35, build-tools 35.0.0, platform-tools)
      with a comment naming `.devcontainer/Dockerfile` as the sibling
      definition. Verify: reading the block against the Dockerfile header
      comment shows matching versions, and the comment points both ways.
- [ ] 2.3 Install the toolchain the pins describe: JDK 21 (`actions/setup-java`
      with a distribution the pin check can read) and Flutter pinned to the
      declared version via `subosito/flutter-action`, pub cache on, in both jobs.
      Verify: `flutter --version` and `java -version` inside the job report the
      declared versions, and a second run with a warm cache is visibly faster in
      the recorded timings.
- [ ] 2.4 Add a `Check toolchain pins` step before any test command in both
      jobs, grepping the running versions the way the Dockerfile's verification
      `RUN` does: Flutter and JDK in `checks` (the Android SDK is not needed for
      analyze or Dart tests), and the Android platform and build-tools packages
      in `accept`, after `Provision device` has installed them. Verify: on a
      scratch branch, temporarily change one pin in the workflow, push, and watch
      the job fail at that step with the offending version named and no test
      output at all; then revert the pin and confirm the step passes.
- [ ] 2.5 Add the `checks` job: pin check, `flutter analyze`, `flutter test`,
      with pub and Gradle caches keyed to `pubspec.lock` and the Gradle build
      files. Verify: the job goes green on a clean branch, and a deliberately
      failing unit test on a scratch branch turns only this job red.
- [ ] 2.6 Add a pub-cache and Gradle-cache cold-run timing note to the workflow
      as a comment naming where the timings are recorded. Verify: the first
      green run's timings appear in the change's `validation.md`.

## 3. Accept job: the release gate on a provisioned device

- [ ] 3.1 Add the `accept` job: KVM group permissions step, then `Provision
      device` running `scripts/ci-emulator.sh`, then the Android package pin
      check, then `Run acceptance gate` running `NATTER_ACCEPT_DEVICE=<serial>
      scripts/accept.sh` with the gate script itself unedited. Verify: the job
      goes green on a clean branch and reports the same scenario count as a
      local gate run on the emulator on `<dev-box>` (12 scenarios, exit 0).
- [ ] 3.2 Confirm the gate needs no configuration in CI: no secret, no
      credential, no `--dart-define` in the accept job. Verify: the job passes
      with no repository secrets defined, and `grep -n "secrets\." .github/workflows/ci.yml`
      returns nothing.
- [ ] 3.3 Add always-run failure evidence: upload the emulator log, the captured
      logcat, and the test output when either device stage fails. Verify: on a
      scratch branch, break something the gate asserts, push, and retrieve both
      the device log and the logcat from the failed run, with the failing
      scenario named in the job output.
- [ ] 3.4 Make a provisioning failure read as provisioning, not as a verdict on
      the build: the boot step and the gate step are distinct, and the upload
      step names which stage produced the evidence. Verify: on a scratch branch,
      point the script at a nonexistent system-image package id, push, and
      confirm the run fails at `Provision device`, that `Run acceptance gate`
      never appears to have run, and that the run is not reported as "the build
      is not releasable". Revert afterward.

## 4. Time budget

- [ ] 4.1 Record stage timings of the first fully green build in the change's
      `validation.md` (pin check, analyze, unit tests, device provisioning,
      acceptance gate, whole run). Verify: the whole run is inside fifteen
      minutes; if it is not, the recorded stage durations name the stage
      responsible and a follow-up is noted there.
- [ ] 4.2 Confirm the acceptance gate keeps its own sub-five-minute budget on the
      CI device as well as on the emulator on `<dev-box>`. Verify: the recorded
      `Run acceptance gate` duration is under five minutes.

## 5. Instructions and docs

- [x] 5.1 Add a `### Continuous integration` subsection to `AGENTS.md` under the
      dev environment: the build runs on every branch push and manual dispatch,
      its two jobs, and the rule that the newest build for a pushed commit is
      read before starting the next change, archiving, or calling a build
      releasable, with a red verdict fixed, re-run, or recorded as debt, and a
      cancelled or pending run treated as no verdict. Include the read command
      (`gh run list --branch <branch> --limit 1` or the commit's Checks page).
      Verify: re-read the section against the monitoring requirement in the spec
      delta and confirm both cases (red, and cancelled-or-pending) appear.
- [x] 5.2 Add a definition-of-done bullet to `AGENTS.md`: a change's push has a
      green CI verdict on the pushed commit, or a recorded reason it does not.
      Verify: the bullet is present and consistent with 5.1.
- [ ] 5.3 Update `README.md`: the Verify section notes that the same commands
      run unattended on every push, and the dev-environment paragraph states
      that CI provisions its own throwaway device while the container still runs
      no emulator. Verify: the commands as written are the ones the workflow
      runs, and the badge resolves on the repository's main page.
- [x] 5.4 Update `.devcontainer/README.md`: the verification gate and the
      acceptance gate both also run unattended in CI, with a pointer to the
      workflow, and a note that the emulator deliberately stays out of the
      container. Verify: the file's gate section matches `AGENTS.md` without
      contradicting the no-emulator rule.
- [x] 5.5 Add the `## add-ci-acceptance-gate` entry to `CHANGELOG.md` in
      user-facing wording. Verify: the entry names what a developer notices
      (a verdict on every push) rather than commit-speak.

## 6. Integration checks

- [ ] 6.1 Run a clean branch build end to end and read the verdict the way the
      new rule requires: both jobs green, verdict attached to the pushed commit,
      accept job green with the expected scenario count. Verify: the reading
      matches the five verdict states named in the design, with no ambiguity
      about which stage produced the verdict.
- [ ] 6.2 Record in the change's `validation.md` why no acceptance-suite
      scenario changes: the delta governs the build, not app behavior, and the
      suite and gate command are untouched - CI only supplies a device through
      the existing `NATTER_ACCEPT_DEVICE` seam. Verify: the reason is written in
      `validation.md`, and `integration_test/accept/` shows no diff for this
      change (`git diff --stat main -- integration_test/accept/` is empty).
- [ ] 6.3 Record in `validation.md` why no live-endpoint on-device round applies
      to this change: the app's network path is untouched and CI runs the
      hermetic suite; the destinations CI itself reaches belong to the build
      toolchain, not the app. Verify: the record says so, and the app diff for
      this change is empty (`git diff --stat main -- lib/ pubspec.yaml`).
- [ ] 6.4 Record standing debt in `validation.md`: CI never exercises the shipped
      API 36 emulator target, the app's own TLS handshake, or a real model's
      output - those remain local, human-run rounds, and the change that owes
      the TLS observation is named alongside. Verify: the three gaps are listed
      with the rounds that still owe them.
- [ ] 6.5 Run the publishable scan on the commit and the pushed tree, and confirm
      the only hostnames in the workflow are public vendor endpoints
      (GitHub, `dl.google.com`, `pub.dev`) rather than any host, device, or
      address of the project. Verify: the scan over every blob in
      `git rev-list --all` and over the pushed tree reports no project host,
      address, or device name.

## Workflow follow-up

- After the change is implemented and the first builds are watched, run
  `openspec validate add-ci-acceptance-gate --strict`, then archive it so
  `openspec/specs/continuous-integration/spec.md` becomes shipped truth.
- The push that lands the archive is itself subject to the new monitoring rule:
  read its verdict before moving on.
