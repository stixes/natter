# Design

## Context

See proposal.md - Why. No Flutter toolchain, devcontainer, or git exists yet. AGENTS.md fixes the intended shape: a devcontainer with Flutter SDK, JDK 21, Android SDK + platform-tools; Gradle and pub caches in named volumes; no emulator (on-device via host adb). This change realizes that.

## Goals / Non-Goals

**Goals:**
- A reproducible container that runs `flutter --version`, `flutter analyze`, and `flutter test` for the future app.
- Warm Gradle and pub caches via named volumes so rebuilds are fast.
- git initialized with a Flutter `.gitignore` so changes can be committed per task.

**Non-Goals:**
- No Android emulator or GPU setup (explicitly excluded by the stack rules).
- No CI pipeline, no signing/keystore, no release tooling.
- No app code — that is `add-streaming-spine`.

## Decisions

- **devcontainer.json as the entry point.** VS Code / devcontainer-CLI standard, keeps the environment declarative and host-agnostic. Alternative (bare Dockerfile or docker-compose): more manual, less tooling integration. Chosen to match the "host needs only Docker + a device" model.

- **Flutter base image, then add JDK 21 + Android SDK + platform-tools.** Start from an official Flutter image and layer the Android toolchain, pinning JDK 21 to match the stack rule. Alternative (Google's Android image + add Flutter) rejected: Flutter-first keeps `analyze`/`test` fastest to stand up.

- **Named Docker volumes for Gradle (`~/.gradle`) and pub (`~/.pub-cache`).** Survives container recreation; matches AGENTS.md. Not baked into the image (keeps image lean, caches updatable).

- **No emulator; adb forwarded from host.** AGENTS.md rule; verification of on-device tasks happens on a physical device, not in-container.

- **git init + Flutter `.gitignore` (build/, .dart_tool/, .idea/, .flutter-plugins, android/.gradle, etc.).** Establishes the repo so "commit per task" is possible. Not part of the container image.

- **Engine preference: Docker if a daemon responds, Podman fallback via its Docker-compatible API.** A tiny helper (`scripts/with-container-env.sh`, sourced before devcontainer commands) tries `docker info`; if that fails and `podman info` works, it starts `podman.socket` (user service), exports `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock`, and puts a one-line `docker`->`podman` shim on PATH (the devcontainer CLI spawns a `docker` binary even when DOCKER_HOST is set; the alternative is distro packaging such as `podman-docker`). Grounded: devcontainer CLI 0.89 builds, runs, and execs containers against Podman 5.8.7 rootless (crun, SELinux enforcing) on the working host.
- **Artifacts stay engine-agnostic; plain Docker remains fully supported.** devcontainer.json and the image definition contain no engine branching; `runArgs: ["--security-opt", "label=disable"]` is accepted by both engines (no-op elsewhere). Named volumes work on both, each engine keeping its own copy - no cross-engine expectations. Docker-in-podman was evaluated (proved to run here) and rejected: requires `--privileged`, breaks workspace bind-mount path mapping through the inner daemon, doubles storage layers; last resort only if some tool rejects the Podman API.
- **Verification runs on this host via the Podman fallback.** The earlier blocker (host has neither Docker nor Flutter) is lifted by the engine decision above. The gate is unchanged: no task is checked off without an actually green in-container run.

## Risks / Trade-offs

- Image/toolchain drift over time. Mitigation: pin Flutter and JDK 21 versions; Android SDK via sdkmanager with an explicit platform.
- Large first pull (Android SDK). Mitigation: named volumes amortize cost across sessions.
- SELinux (enforcing on the working host) may deny the workspace bind mount from `$HOME` under Podman. Mitigation: `runArgs: ["--security-opt", "label=disable"]` in devcontainer.json (accepted by Docker too); named volumes are auto-relabeled by Podman, no action needed.
- Under Podman, `devcontainer up` builds and starts the container but the CLI does not exit cleanly. Mitigation: treat a running container as success; do not read the hang as a build failure.
- Engine-specific drift between Docker and Podman paths. Mitigation: the engine helper centralizes the differences in ~10 lines; both quirks above are documented in tasks.
