# Tasks

## 1. Dependency and storage seam

- [x] 1.1 Add `shared_preferences: 2.5.3` to `pubspec.yaml` and run `flutter pub get`; verify the lock file resolves under the dev image's Flutter 3.29.3 / Dart 3.7.2 and that no newly added package requires a newer Dart SDK.
- [x] 1.2 Implement `SharedPreferencesKeyValueStore` in `lib/data/key_value_store.dart` over an injected `SharedPreferences` instance, implementing `read`, `write`, `delete`, and `contents`; verify a unit test using `SharedPreferences.setMockInitialValues` covers all four operations.
- [x] 1.3 Update the stale comments in `lib/data/key_value_store.dart` and `lib/state/chat_providers.dart` that say settings are not persisted or that persistence is undecided; verify `rg -n "not persisted|durable settings" lib` no longer claims the plain settings store is in-memory.

## 2. Production wiring and persistence behavior

- [x] 2.1 Wire `lib/main.dart` to await `SharedPreferences.getInstance()`, build the durable store, and override `settingsStoreProvider` in the `ProviderContainer`; verify a container-level test loads a saved base URL and model when the settings provider is overridden with a preferences-backed store.
- [x] 2.2 Add a simulated-restart test in `test/`: save a profile through `ProfileRepository`, construct a second repository over the same preferences and secure store, and load; verify the base URL and model are restored and the API key remains only in the secure store.
- [x] 2.3 Add a keyless-restart case to the same test file: save a profile with an empty key, reload it, and verify the endpoint still counts as configured and the plain settings contents do not contain the key field.
- [x] 2.4 Run `flutter analyze && flutter test` in the devcontainer and verify both pass.

## 3. On-device confirmation

- [x] 3.1 On `<device>`, save a base URL and model in Settings, force-stop the app, relaunch it, and verify the settings screen shows the saved base URL and model while the chat screen treats the endpoint as configured; record the result in `validation.md` under this change.

## Workflow follow-up

- Run the publishable scan on the commit (placeholders only, no hostnames or devices).
- Archive this change after review so `chat-streaming` gains the durable-endpoint-configuration requirement.
