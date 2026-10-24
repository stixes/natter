# Validation

## Automated checks

Run in the devcontainer against Flutter 3.29.3 / Dart 3.7.2.

- `flutter analyze` — no issues.
- `flutter test` — 118 tests pass, including the generated Drift code
  (`lib/data/app_database.g.dart`) checked into the tree.
- `flutter build apk --debug` — builds `build/app/outputs/flutter-apk/app-debug.apk`.
  The merged manifest contains `android:allowBackup="false"`.

Coverage added by this change:

- `test/app_database_test.dart` — the schema opens in memory with both tables
  and both indexes present.
- `test/conversation_repository_test.dart` — a first user turn lands in one
  transaction; newest-first ordering; message order by time then id; reasoning
  round-trips from its nullable column; an empty history; a user-only turn;
  a save after close surfaces an exception.
- `test/conversation_controller_test.dart` — restore success and failure; user
  turn saved before the request; save failure still streams; in-flight drafts
  never reach the repository; assistant turn saved on normal end and on cancel
  with answer text; nothing saved when cancel arrives before any text; title
  set once and shortened; New chat clears without inserting a row; switching
  mid-stream; switching when no text arrived; load failure leaves the current
  conversation usable with a notice.
- `test/chat_screen_test.dart` — drawer newest-first ordering; empty history;
  New chat keeps earlier conversations; selection loads the target's messages;
  restored conversation renders in order and opens at the bottom; save-failure
  and load-failure banners without Retry; "History unavailable." drawer state.

## Notes on the automated runs

- The widget tests dispose the provider container before closing the fake
  repository. Registering `repo.close` first and `container.dispose` second
  (so teardown runs container-first) avoids a deadlock between the broadcast
  stream's close future and the still-active `StreamProvider` subscription.
- The history-list `StreamProvider` disables Riverpod's default auto-retry so a
  local database error surfaces as "History unavailable." instead of an
  indefinite retry timer that leaves a pending timer at test teardown.

## On-device round (task 6.2) — ran on the remote emulator

Ran 2026-10-24 on the always-on Android emulator on `<dev-box>` (Android 16,
API 36, device serial `<dev-box>:5555`), against the live llama-swap endpoint
at `<llama-swap-host>` (model `gemma4-26b-a4b`). No physical device was used.

Connection note: the remote adb server (`ADB_SERVER_SOCKET=tcp:<dev-box>:5037`)
works for `adb devices` and shell commands, but Flutter's VM-service port
forwarding is created on the emulator host and is unreachable from the
container. Integration runs and `flutter run` must connect directly to the
device port (`adb connect <dev-box>:5555`, using the emulator's adb key), so
the device serial is `<dev-box>:5555`.

Steps and results:

1. Built and installed the debug APK, seeded the endpoint settings (base URL
   and model; no key needed), and launched the app. The chat screen showed
   "Say something.", so the seeded settings were read.
2. Sent "Say hello in one word". The assistant replied "Hello!".
3. Force-stopped the app (`am force-stop`), confirmed no process remained, and
   relaunched (`am start`).
4. The relaunched app showed both the user turn "Say hello in one word" and the
   assistant turn "Hello!", so the conversation was restored from storage.
5. Pulled the on-device database (`app_flutter/natter.sqlite`) and confirmed one
   `conversations` row titled "Say hello in one word" and two `messages` rows
   (user and assistant).

An automated integration round also passed on the emulator: `7.1 plain model
streams incrementally` streamed "1" through "60" against the live endpoint.
