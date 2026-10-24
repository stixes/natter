# Design

## Context

See proposal.md - Why. The relevant current state:

- `lib/data/key_value_store.dart` defines one seam with two implementations: an
  `InMemoryKeyValueStore` used for base URL and model, and a `SecureKeyValueStore` for the
  API key. The in-memory store dies with the process, so only the key survives a restart.
- `lib/data/profile_repository.dart` routes values by sensitivity: base URL and model to
  `settings`, the key to `secrets`. Its storage keys are `endpoint.baseUrl`,
  `endpoint.model`, and `endpoint.apiKey`.
- `lib/state/chat_providers.dart` builds the production store as
  `InMemoryKeyValueStore()` and comments that persistence is undecided. `main.dart` already
  awaits `profileProvider.notifier.loadStored()` before `runApp`, so the only missing piece
  is a durable store behind the seam.
- The settings screen is one base URL, one key, one model. It saves through the repository
  and pops. No screen change is needed.
- `shared_preferences` is not a dependency yet. AGENTS names it as the home for durable
  settings.

## Goals / Non-Goals

**Goals:**

- A configured base URL and model survive process death and device restarts.
- The API key keeps its existing storage path and never appears in the plain settings
  store, in logs, or in conversation storage.
- Tests stay hermetic: no plugin channel in unit tests unless a preferences mock is used.
- The change is additive to the current storage seam, so the profiles change can later
  generalize it without rewriting the chat path.

**Non-Goals:**

- No multiple profiles or profile picker. The app still has exactly one endpoint.
- No settings migration from a prior persisted format; none exists.
- No change to the settings screen, request headers, streaming, retry, or cancel.
- No model discovery or endpoint health checks.
- No backup policy change. Android Auto Backup is still on after this change; the history
  change owns the decision about keeping app data off the device.

## Decisions

**Use `shared_preferences` for non-secret settings.**
It is the storage AGENTS names for durable settings, it is already the platform's
conventional key/value store on Android, and it carries no server-side or cloud sync of its
own. Alternatives: a JSON file in the app documents directory (more code, more failure
modes, and a second storage idiom once Drift arrives) and Drift (a database for three
strings, and it would land before history). Secure storage for everything was rejected
because base URL and model are not secrets and the keystore is the wrong tool for
non-sensitive values.

**Pin `shared_preferences` to `2.5.3`, not a caret range.**
The dev image is Flutter 3.29.3 / Dart 3.7.2. Releases 2.5.4 and newer require Dart 3.9 and
Flutter 3.35, so a caret range would invite a resolution that cannot build in the pinned
container. 2.5.3's transitive `shared_preferences_android` resolves to a release that
supports Flutter 3.29.x. Exact pinning keeps the dev image and the lock file in agreement.

**Keep the `KeyValueStore` seam and add one implementation.**
`SharedPreferencesKeyValueStore` wraps a `SharedPreferences` instance and implements
`read`, `write`, `delete`, and `contents`. The in-memory implementation stays as the test
default. Alternative: expose `SharedPreferences` directly to the repository and delete the
seam. Rejected because the seam is what lets the existing storage tests assert where a
secret landed, and that assertion is part of the shipped key-storage guarantee.

**Initialize preferences once in `main` and override the settings provider.**
`SharedPreferences.getInstance()` is async. `main` awaits it, constructs the durable store,
and creates the `ProviderContainer` with
`settingsStoreProvider.overrideWithValue(store)`. The default provider stays in-memory so
widget and unit tests do not touch the plugin. Alternative: make the settings provider
asynchronous (`FutureProvider`), which would ripple through the repository and controller
for no behavior gain. Alternative: lazy-initialize the plugin inside the store on first
read; rejected because it hides an async failure inside a synchronous-looking seam and
still needs a container override for tests.

**Keep the existing storage keys.**
`endpoint.baseUrl` and `endpoint.model` move to the new store unchanged, so
`ProfileRepository` needs no edit and the later profiles change can migrate or namespace
them deliberately. Alternative: store a JSON blob under one key; rejected because it makes
partial reads and future key migrations less direct for no benefit with three values.

**Load stays where it is.**
`main` already awaits `loadStored()` before `runApp`, and `ProfileRepository.load()` already
merges plain settings with the secure key. The only change is which store the repository
receives. No new loading screen or flash of unconfigured UI.

**No migration path is needed, and the upgrade state is honest.**
A user upgrading from the current build may have an API key in secure storage but no base
URL or model, because those were never persisted. The app starts unconfigured; the user
enters the base URL and model once, and both persist from then on. There is no way to
recover an unknown URL or model, so pretending otherwise would be worse.

## Risks / Trade-offs

- **A preferences write fails silently** and the settings screen closes as if saved. The
  seam's `write` returns `Future<void>` and the repository awaits it, so a thrown plugin
  error propagates to `_save`, which currently has no failure UI. Mitigation: keep the
  existing behavior for this change (no new UI), and add a save-failure surface only if a
  device round shows it happens; a follow-up change owns that UI. The base URL and model
  are not secrets, so a failed write loses convenience, not privacy.
- **Android Auto Backup includes `shared_preferences` by default**, so the base URL and
  model can leave the device through the OS backup service even though the API key does
  not. This change leaves that as-is because only settings are stored; the history change
  must set the backup policy before conversation content lands. If configuration itself
  should stay off-device, that policy decision moves into the history change with the
  database.
- **A first launch with no stored settings now touches the plugin.** If the plugin fails to
  initialize, `main` throws before `runApp`. Mitigation: this is a platform-channel failure
  with no recovery surface in scope; the risk is low and the failure is loud rather than
  silent. A later change can add a fallback to in-memory storage.
- **Exact pinning** means a future Flutter upgrade needs a deliberate bump of
  `shared_preferences`. That is the same trade-off already accepted for
  `flutter_secure_storage`, and it keeps the container reproducible. The transitive
  `shared_preferences_android` plugin must also build against the dev image's compileSdk
  35; verify during implementation and pin the last compatible release if it does not.

## Open Questions

None. The screen, storage split, and key names stay as they are; the only open decision -
whether profiles arrive with this change - is answered in the proposal's scope: they do
not.
