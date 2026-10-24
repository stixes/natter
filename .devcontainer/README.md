# Natter dev container

Flutter SDK 3.29.3, JDK 21, Android SDK (platform 35, build-tools 35.0.0,
platform-tools) - all pinned via `ghcr.io/cirruslabs/flutter:3.29.3` and
re-checked at image build time (see Dockerfile). No emulator runs inside the
container; testing targets the always-on emulator on `<dev-box>` through its
remote adb server (see below).

## Engine

Works with Docker or Podman (Docker preferred when a daemon responds).
Before any devcontainer command:

    . scripts/with-container-env.sh

On the Podman branch it also needs the socket active
(`systemctl --user start podman.socket` - the helper starts it).

## Up / down

    npx @devcontainers/cli up --workspace-folder . --remove-existing-container

Note: under Podman, `up` can hang after "Container started" even though
the container is up; Ctrl-C (or a timeout) is fine - check
`docker ps -f label=devcontainer.local_folder=$PWD`.

Gradle (`~/.gradle`) and pub (`~/.pub-cache`) caches live in named volumes
(`natter-gradle-cache`, `natter-pub-cache`), each engine keeping its own
copy. They persist across container removal.

## Verification gate

Every change must be green in-container before commit:

    flutter analyze && flutter test

## Emulator testing (default target)

The default debug and integration target is the always-on Android emulator on
`<dev-box>`. It is reached over the tailnet; no device needs to be attached to
this host. From the container:

1. `export ADB_SERVER_SOCKET=tcp:<dev-box>:5037`
2. Verify: `adb devices` shows `emulator-5554 device`, and `flutter devices`
   shows the emulator.
3. Run from `/workspaces/natter`: `flutter run -d emulator-5554`.

Do not run `adb kill-server` while `ADB_SERVER_SOCKET` points at the emulator:
it kills the remote server. Emulator host, address, and key details live in the
git-ignored local notes.

### Fallback: host-forwarded adb for a physical device

Use only when the emulator host is unavailable. Run the adb server on the host
with a physical device attached, reachable from the container's network:

1. Host: `adb kill-server && adb -a -L tcp:5037 fork-server server &`
2. Container: `export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037`
3. Verify: `adb devices` then `flutter devices` show the device;
   `flutter run -d <device>` from `/workspaces/natter`.

`host.docker.internal` resolves via host-gateway on both Docker and
Podman (added through `runArgs`). Set only one `ADB_SERVER_SOCKET` at a time.

Wireless debugging rotates the device's adb port when it sleeps, so a stale
endpoint shows up as a missing entry or `device offline` in `adb devices`.
Re-run `adb connect <device-ip>:<port>` with the port the phone is currently
advertising.
