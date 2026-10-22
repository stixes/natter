# Natter

A deliberately small chat client: ChatGPT-quality UX, any OpenAI-compatible endpoint, first-class local chat history. Nothing else.

Working title: **Natter**. Package/app id: `dev.natter.app`. Verify Play Store / trademark clearance before any public release.

## Vision

People routing AI through their own gateways (LiteLLM, OpenRouter, Ollama's OpenAI API, llama.cpp server, corporate proxies) deserve a chat app as polished as ChatGPT without inheriting a platform's baggage. Existing options are self-hosted web platforms (Open WebUI, LibreChat, LobeChat), local-model managers (Jan, LM Studio, Msty), or minimal-but-crude clients (Maid). Natter is the missing middle: install the app, point it at a base URL + key, chat beautifully, own your history.

We compete on subtraction. Every feature we refuse to build is the product.

## Product principles

1. The chat screen is the product. Everything else is support.
2. History is sacred: instant, searchable, exportable, local, never leaves the device without explicit user action.
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

- Flutter (Dart), Material 3; Android is the primary target, iOS is a free rider, desktop is out of scope
- Riverpod for state; no other framework unless a proposal justifies it
- Drift (SQLite) for conversations/messages; shared_preferences for settings
- API keys via flutter_secure_storage (keystore-backed); never in SQL, logs, or backups
- `http` + json_serializable for OpenAI-compatible `chat/completions` with SSE streaming; no cloud SDK packages
- Provider formats: OpenAI-compatible first; Anthropic-native only if a proposal adds it
- Reasonable dependency budget: justify every pub package in code or in the proposal that adds it

## Dev environment: devcontainer

- Host needs only a container engine (Docker if available, else Podman) + a physical Android device (USB or network ADB)
- `.devcontainer/` image: Flutter SDK, JDK 21, Android SDK + platform-tools; Gradle and pub caches in named volumes
- No emulator inside the container (GPU/accel pain); debug on-device via adb forwarded from the host
- `flutter analyze && flutter test` must pass inside the container on any commit; integration tests via `integration_test` on a connected device

## Spec workflow (OpenSpec)

Layout: `openspec/project.md` (context), `openspec/specs/` (truth), `openspec/changes/` (in-flight proposals).

Rules:
1. Any user-visible behavior change starts as a proposal: `/opsx:propose <idea>` producing proposal + spec deltas + tasks.
2. No implementation before a proposal is approved (not silently added, no drive-by feature creep).
3. Small proposals: one screen or subsystem each. Prefer several tiny changes over one big rewrite.
4. Implement with `/opsx:apply` working the tasks checklist; commit per task where practical.
5. Close with `/opsx:archive` so `specs/` reflects shipped truth. Specs are the source of truth; if code and spec disagree, that is a bug in one of them.
6. A new dependency, a new permission, or a new network destination needs the proposal to say why in one sentence.

## Definition of done

- Spec delta updated, tests green, streaming edge cases handled (cancel, mid-stream error, retry, malformed SSE)
- No new permissions, no new network calls beyond what the proposal states
- Changelog entry (user-facing wording, not commit-speak)

## Tone and polish bar

The reference bar is the ChatGPT app's conversation feel: smooth token streaming, sensible auto-titling, instant thread switching. Flutter is chosen for velocity, not as an excuse: if any detail (scroll behavior, keyboard handling, markdown rendering, copy affordances, dark mode) looks or feels cheap on Android, it is not done.
