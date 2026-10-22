# Tasks

## 0. Container engine

- [x] 0.1 Create `scripts/with-container-env.sh` (sourceable helper: prefer Docker if `docker info` succeeds; else start `podman.socket`, export `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock`, put a `docker`->`podman` shim dir on PATH; else fail with a clear message) and verify with the engine present on this host: `devcontainer read-configuration` succeeds and a trivial `up` reaches a running container (a non-exiting `up` under Podman is cosmetic, not a failure)

## 1. Repository init

- [x] 1.1 Run `git init` and verify `git status` reports a repository at the project root
- [x] 1.2 Add a Flutter `.gitignore` (build/, .dart_tool/, .idea/, .flutter-plugins*, android/.gradle, .pub-cache) and verify `git status` stays clean of generated paths

## 2. Devcontainer definition

- [x] 2.1 Create `.devcontainer/devcontainer.json` referencing a Flutter base image, including `runArgs: ["--security-opt", "label=disable"]` (SELinux bind-mount allowance, accepted by Docker as well), and verify the devcontainer CLI builds the image without error and the workspace is mounted inside the container
- [x] 2.2 Layer JDK 21, Android SDK, and platform-tools in the image (pin versions) and verify inside the container `java -version` shows 21 and `sdkmanager --list` succeeds
- [x] 2.3 Verify `flutter --version` and `flutter doctor` report the Android toolchain ready (licenses accepted) inside the container

## 3. Cache volumes

- [x] 3.1 Mount named volumes for Gradle (`~/.gradle`) and pub (`~/.pub-cache`) in devcontainer.json and verify a rebuild reuses the cache (second build is materially faster / cache dir persists across recreate); under Podman, named volumes are auto-relabeled for SELinux - only persistence needs verifying

## 4. Verification gate

- [x] 4.1 Create a throwaway Flutter scaffold inside the container (`flutter create .`) and verify `flutter analyze && flutter test` pass in-container, proving the toolchain (then remove the scaffold)
- [x] 4.2 Confirm no emulator/emulator tooling is present and that the on-device path is host-forwarded adb, by checking `flutter doctor` shows no emulator and documenting the adb-forward step

## Workflow follow-up

- Verification runs on this host through the Podman fallback path (task 0.1); the gate stands: no checkbox without an actually green in-container run.
- Archive after the container builds and the toolchain check is green.
- With this change archived, resume `add-streaming-spine` (its task 1.1 now has a toolchain to build on).
