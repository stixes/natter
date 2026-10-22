# Proposal

## Why

The project's own stack rules require that `flutter analyze && flutter test` pass inside a devcontainer, and AGENTS.md specifies a `.devcontainer/` image (Flutter SDK, JDK 21, Android SDK + platform-tools). That container does not exist yet, and the repo is not even under git. `add-streaming-spine` task 1.1 depends on this toolchain existing. This change provides the reproducible dev environment so feature work can start and be verified.

## What Changes

- Add `.devcontainer/`: a `devcontainer.json` plus image definition providing Flutter SDK, JDK 21, and Android SDK + platform-tools.
- Persist Gradle and pub caches in named volumes for fast rebuilds.
- Deliberately exclude an emulator; on-device testing runs against a physical Android device via host-forwarded adb, per the stack rules.
- Initialize git with a Flutter-appropriate `.gitignore`.
- Establish the in-container check (`flutter analyze && flutter test`) as the verification gate for all future changes.

No user-visible app behavior is introduced, so this change opts out of spec deltas (`skip_specs: true`).

## Capabilities

### New Capabilities
<!-- none: tooling/infrastructure only, no spec-level behavior -->

### Modified Capabilities
<!-- none -->

## Impact

- New files: `.devcontainer/devcontainer.json`, image/tooling definition, `.gitignore`, git init.
- No app code, no runtime dependencies, no new network destinations at app runtime. Container image pulls (Flutter/Android SDK bases) happen at dev-time only, not from the shipped app.
- Unblocks `add-streaming-spine` task 1.1 and every subsequent change's test gate.
- Engine constraint: verification needs a Docker-compatible container engine, not Docker specifically. Docker is used when a daemon responds, otherwise Podman via its Docker-compatible API (verified working with the devcontainer CLI on the working host).
