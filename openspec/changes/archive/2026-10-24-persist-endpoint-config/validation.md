# Validation

## Environment

- Unit and widget tests: devcontainer, Flutter 3.29.3 / Dart 3.7.2.
  `flutter analyze` is clean and `flutter test` is 80/80 passing.
- On-device round: physical Android device (`<device>`), debug APK installed
  with `adb install -r`, package `dev.natter.app`.
- Endpoint values for the round: base URL `http://192.0.2.10:8080/v1`, model
  `qwen3-test`, API key empty. The URL is RFC 5737 documentation space; no
  request was made, so no real host is named here.

## Task 3.1 - configuration survives a restart

1. Cleared app data (`adb shell pm clear dev.natter.app`) and launched the app.
   The chat screen showed `No endpoint configured. Open Settings to set a base
   URL and model.`
2. Opened Settings, entered the base URL and model, left the API key empty, and
   saved. The screen popped back to chat, which then showed `Say something.`
   with the send button enabled.
3. Force-stopped the app (`adb shell am force-stop dev.natter.app`) and
   relaunched it (`adb shell am start -n dev.natter.app/.MainActivity`).
4. The relaunched chat screen showed `Say something.` with the send button
   enabled and no "No endpoint configured" message, so the endpoint still
   counted as configured.
5. Opened Settings and confirmed the base URL field read
   `http://192.0.2.10:8080/v1` and the model field read `qwen3-test`. The API
   key field was empty, and the saved plain settings held only the base URL and
   model fields.

Result: pass. The base URL and model survived process death and a relaunch,
and a keyless endpoint still counted as configured.

## Note on the debug build

`flutter build apk --debug` reported an NDK version warning: the project uses
Android NDK 26.3.11579264 while `flutter_secure_storage`, `path_provider_android`,
and `shared_preferences_android` request NDK 27.0.12077973. The build completed,
installed, and ran. This is a plugin-version warning unrelated to endpoint
persistence; aligning the NDK version would be a separate change.
