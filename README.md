# Natter

![CI](https://github.com/stixes/natter/actions/workflows/ci.yml/badge.svg)

A deliberately small chat client: point it at any OpenAI-compatible endpoint, chat, and keep your history on-device.

Package/app id: `dev.natter.app`. Android is the primary target.

## Dev environment

All development happens inside the devcontainer (`.devcontainer/`): Flutter SDK, JDK 21, and the Android SDK, with Gradle and pub caches in named volumes. The host needs only a container engine (Docker, or Podman with `podman machine` running on macOS). The default test target is an always-on Android emulator on `<dev-box>`, reached over the tailnet through its remote adb server; a physical device is an optional fallback. There is no emulator in the container, and there is no need for one: CI provisions its own throwaway device when it runs the acceptance gate.

## Verify

Inside the container:

```
flutter analyze
flutter test
```

Both must pass on any commit.

The same commands, plus the acceptance gate (`scripts/accept.sh`), also run unattended on every push to every branch (`.github/workflows/ci.yml`), on a device the build provisions for itself. Its verdict is attached to the commit; a red verdict is fixed or recorded as debt before work moves on.

## Run on the emulator

Point the container at the emulator's remote adb server, then run:

```
export ADB_SERVER_SOCKET=tcp:<dev-box>:5037
adb devices
flutter run --debug
```

For a physical-device fallback, start an adb server on the host instead. On macOS + Podman, `ADB_SERVER_SOCKET=tcp:host.containers.internal:5037` is exported automatically inside the container. Set only one `ADB_SERVER_SOCKET` at a time.
