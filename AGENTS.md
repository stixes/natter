# Natter

A deliberately small chat client: ChatGPT-quality UX, any OpenAI-compatible endpoint, first-class local chat history. Nothing else.

Working title: **Natter**. Package/app id: `dev.natter.app`. Verify Play Store / trademark clearance before any public release.

## Vision

People routing AI through their own gateways (LiteLLM, OpenRouter, Ollama's OpenAI API, llama.cpp server, corporate proxies) deserve a chat app as polished as ChatGPT without inheriting a platform's baggage. Existing options are self-hosted web platforms (Open WebUI, LibreChat, LobeChat), local-model managers (Jan, LM Studio, Msty), or minimal-but-crude clients (Maid). Natter is the missing middle: install the app, point it at a base URL + key, chat beautifully, own your history.

We compete on subtraction. Every feature we refuse to build is the product.

## Product principles

1. The chat screen is the product. Everything else is support.
2. History is sacred: instant, searchable, exportable, local, never leaves the device without explicit user action. (Destination, not shipped: `openspec/specs/` says what exists today.)
3. No accounts, no sign-in, no cloud sync (until a spec proposal argues otherwise).
4. BYO endpoint only. We are never a proxy and never hold API keys server-side.

### Explicit non-goals (changing one requires a spec proposal that names it)

- No local/on-device inference (no llama.cpp bundling)
- No RAG, document upload, knowledge bases, embeddings
- No agents, tools, function calling UI, MCP
- No multi-user, no team features, no admin
- No analytics or telemetry of any kind
- No prompt marketplace, sharing feeds, or social features

## Stack

- Flutter (Dart), Material 3. Android only: there is no `ios/` scaffolding, and iOS would arrive with a proposal. Desktop is out of scope.
- Riverpod for state; no other framework unless a proposal justifies it.
- `pubspec.yaml` is the truth about what is installed, and it stays deliberately small: every pub package needs a reason in code or in the proposal that adds it.
- `flutter_secure_storage` is pinned to `^9.2.2`, because v10 wants Android SDK 36 and the dev image pins 35. API keys reach only its keystore-backed store, never SQL, logs, or backups.
- History is Drift (SQLite) territory and durable settings land on `shared_preferences`. Neither is a dependency yet; the proposal that adds one owes the reason.
- Streaming is `http` against `chat/completions`, SSE parsed by hand: no codegen, no cloud SDK packages.
- Provider formats: OpenAI-compatible first; Anthropic-native only if a proposal adds it.
- Android's cleartext block does not constrain this app: dart:io opens its own sockets rather than going through OkHttp, so a plain `http://` endpoint needs no manifest or network-security config.

## Dev environment: devcontainer

- Host needs only a container engine (Docker if available, else Podman); a physical Android device is not required
- `.devcontainer/` image: Flutter SDK, JDK 21, Android SDK + platform-tools; Gradle and pub caches in named volumes
- The default debug and integration target is the always-on Android emulator on `<dev-box>`, reached over the tailnet through its remote adb server (`ADB_SERVER_SOCKET=tcp:<dev-box>:5037`, device id `emulator-5554`); no emulator runs inside the container
- A physical device is an optional fallback when the emulator host is unavailable; `.devcontainer/README.md` covers host-forwarded adb for that case
- Emulator host, address, and key details live in the git-ignored local notes, never in a commit
- `flutter analyze && flutter test` must pass inside the container on any commit; integration tests via `integration_test` run on the emulator

### Continuous integration

- `.github/workflows/ci.yml` builds every push on every branch, plus a manual run: a `checks` job (`flutter analyze`, `flutter test`) and an `accept` job that boots a throwaway emulator inside the runner and runs `scripts/accept.sh` unchanged against it
- CI holds no secrets and configures no endpoint: the acceptance suite serves its own loopback endpoint, so live-endpoint rounds stay local and human-run
- The device comes from `scripts/ci-emulator.sh`; the emulator deliberately stays out of the dev container
- Superseded runs on a working branch are cancelled, runs on the default branch never are, and a cancelled or still-pending run is no verdict
- Read the newest build's verdict for a pushed commit before starting the next change, archiving a change, or calling a build releasable: `gh run list --branch <branch> --limit 1`, or the commit's Checks page. A red verdict is fixed, re-run, or recorded as debt - never passed over in silence
- CI toolchain pins live in the workflow `env:` block and mirror `.devcontainer/Dockerfile`; a `Check toolchain pins` step fails before any test runs when the two drift apart

## Publishing hygiene

The remote is public, so every commit is **publishable** material: hosts, addresses, devices, machines, and people read as placeholders in anything committed, including docs, validation records, and test fixtures.

- Vocabulary: `<llama-swap-host>`, `<dev-box>`, `<tls-front-host>`, `<device>`; example base URLs use RFC 5737 documentation space (`192.0.2.0/24`); hosting is described generically ("the HTTPS front") rather than by tunnel or product name
- Command blocks say the angle brackets are placeholders, since they are not shell-safe as written
- Endpoint URLs, models, and keys for on-device rounds arrive through `--dart-define`, so they never land in a committed file
- A leak is rewritten out of history and force-pushed, not layered over: a follow-up commit leaves the old blob public
- Verification scans commits and the published file, never the working copy: every blob in `git rev-list --all`, then the same scan over the pushed tree

## Spec workflow (OpenSpec)

Layout: `openspec/specs/` (shipped truth), `openspec/changes/` (in-flight proposals), `openspec/config.yaml` (context and artifact rules handed to the OpenSpec CLI).

Rules:
1. Any user-visible behavior change starts as a proposal: `/opsx-propose <idea>` producing proposal + spec deltas + tasks.
2. No implementation before a proposal is approved (not silently added, no drive-by feature creep).
3. Small proposals: one screen or subsystem each. Prefer several tiny changes over one big rewrite.
4. Implement with `/opsx-apply` working the tasks checklist; commit per task where practical.
5. Close with `/opsx-archive` so `specs/` reflects shipped truth. Specs are the source of truth; if code and spec disagree, that is a bug in one of them.
6. A new dependency, a new permission, or a new network destination needs the proposal to say why in one sentence.
7. `openspec validate <change> --strict` is green before a proposal counts as approved, and before it is archived.
8. A change whose spec deltas touch a capability the acceptance suite covers (`integration_test/accept/`) names the suite scenario to add or update in its tasks, or records why none applies. The suite itself is governed by the `acceptance-testing` spec.

## Definition of done

- Spec delta updated, tests green, streaming edge cases handled (cancel, mid-stream error, retry, malformed SSE)
- Acceptance suite green (`scripts/accept.sh`) on the emulator on `<dev-box>` (or `<device>` as fallback); a change that alters covered behavior lands its suite update with it
- No new permissions, no new network calls beyond what the proposal states
- Changelog entry (user-facing wording, not commit-speak)
- A change that touches the network path owes on-device rounds against a live endpoint, recorded in `validation.md` beside the change. A round that gets descoped is named there as debt, and the change that owes it is named with it
- Publishable scan clean on every commit (Publishing hygiene)
- CI verdict green on the pushed commit, or a recorded reason it is not; a cancelled or pending run counts as no verdict rather than as a pass

## Tone and polish bar

The reference bar is the ChatGPT app's conversation feel: smooth token streaming, sensible auto-titling, instant thread switching. Flutter is chosen for velocity, not as an excuse: if any detail (scroll behavior, keyboard handling, markdown rendering, copy affordances, dark mode) looks or feels cheap on Android, it is not done.
