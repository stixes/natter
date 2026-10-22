# Natter

A deliberately small chat client: point it at any OpenAI-compatible endpoint, chat, and keep your history on-device.

Package/app id: `dev.natter.app`. Android is the primary target.

## Dev environment

All development happens inside the devcontainer (`.devcontainer/`): Flutter SDK, JDK 21, and the Android SDK, with Gradle and pub caches in named volumes. The host needs only a container engine (Docker, or Podman with `podman machine` running on macOS) and a physical Android device. There is no emulator in the container.

## Verify

Inside the container:

```
flutter analyze
flutter test
```

Both must pass on any commit.

## Run on a device

Start an adb server on the host, then from the container:

```
flutter run --debug
```

On macOS + Podman, `ADB_SERVER_SOCKET=tcp:host.containers.internal:5037` is exported automatically inside the container.
