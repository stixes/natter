# Proposal

## Why

The app loses its base URL and model name when it restarts. The API key survives in
secure storage, so after a relaunch the app still holds a secret for an endpoint it has
forgotten. A user who configured Natter once returns to a chat screen that says no
endpoint is configured and has to type the URL and model again. For a "point it at a base
URL and chat" app, the configuration must survive the process that reads it.

## What Changes

- Replace the in-memory settings store with a `SharedPreferences` backed store for the
  non-secret fields.
- Persist the base URL and model name to disk and restore them at app startup. The API key
  keeps using secure, keystore-backed storage and is never written to plain settings.
- Keep the settings screen exactly as it is: one base URL, one API key, one model name. No
  profile list, no extra fields, no new screen.
- No change to chat requests, streaming, retry, or cancel behavior. The only visible
  difference is that a configured endpoint is still configured after a restart.

Out of scope: multiple endpoints or profiles, a profile picker, model discovery from
`/v1/models`, endpoint health checks, and migration from an earlier persisted format
(there is none). This change touches no product non-goal: settings remain on-device and no
cloud sync is introduced.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `chat-streaming`: adds a durable-endpoint-configuration requirement: the base URL and
  model survive an app restart, while the API key stays in secure storage and out of
  plain settings.

## Impact

- `pubspec.yaml`: adds `shared_preferences`, pinned to the newest release compatible with
  the dev image's Flutter 3.29.3 / Dart 3.7.2 toolchain. Reason: durable storage for
  non-secret settings.
- `lib/data/key_value_store.dart`: adds a `SharedPreferences` implementation of the
  existing `KeyValueStore` seam. The in-memory implementation stays for tests.
- `lib/state/chat_providers.dart`: production wiring uses the new store. The in-memory
  default remains the test default.
- `lib/main.dart`: initializes the preferences plugin before the provider container and
  overrides the settings store with the durable one. Startup already awaits
  `loadStored()`, so no extra loading step is needed.
- Tests: extend the storage seam tests with a preferences-backed store and a simulated
  restart that reloads a saved profile. Assert the API key never appears in the plain
  settings contents.
- No new permissions. No new network destination. No change to the streaming client.
- Changelog: one user-facing line saying the endpoint configuration now survives closing
  the app.
