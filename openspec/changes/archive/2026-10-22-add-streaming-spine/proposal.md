# Proposal

## Why

Natter's core promise is "point it at a base URL + key and chat beautifully," but that phrase hides a family of subtly different "OpenAI-compatible" dialects and a ChatGPT-quality streaming bar. Both are product risks we should retire before building any other subsystem. This change proves the scary part end to end on real endpoints.

## What Changes

- Add a single chat screen that streams an assistant reply token-by-token over SSE from a user-configured OpenAI-compatible endpoint.
- Add a minimal single-endpoint configuration (one base URL, one API key, one model name) so the developer can point the app at a live llama.cpp server or OpenRouter and validate the streaming spine. This is the degenerate one-profile form of the future profiles change.
- Add assistant-message state rendering: a `Waiting...` placeholder (dots animating), transitioning to a `Thinking...` placeholder while a reasoning stream is active, then to the streamed answer text.
- Parse and persist reasoning per message (in-memory for this session) from either `delta.reasoning_content` or `delta.reasoning`, but do NOT render it (hide it, matching cloud-provider UX).
- Add streaming edge-case handling: cancel, mid-stream error, retry, and a blank-answer fallback when the model returns an empty `content` but non-empty reasoning.
- Render the answer as plain text (no markdown rendering in this change).
- Android only. iOS is not blocked by the framework but is neither validated nor polished here.

Deliberately out of scope: endpoint profiles/switching, persisted history and thread lists, model pickers backed by `/v1/models`, markdown rendering, a show-thinking toggle, reasoning replay, and Anthropic-native format.

## Capabilities

### New Capabilities
- `chat-streaming`: the chat screen's request/stream lifecycle against an OpenAI-compatible endpoint - placeholder states, reasoning capture (hidden), streaming edge cases, and the minimal single-endpoint configuration that drives it.

### Modified Capabilities
<!-- none; this is the first capability in the project -->

## Impact

- Bootstraps the Flutter app (no code exists yet): entry point, chat screen, minimal settings.
- New dependencies (each justified by the stack rules): `flutter_riverpod` (state), `http` (SSE streaming), `flutter_secure_storage` (the single API key; sensitive regardless of count). No markdown, DB, or codegen packages in this change.
- One network destination beyond the user's own endpoint: none. All network traffic goes to the user-configured base URL; the app makes no other outbound calls.
- Conversation state is ephemeral (in-memory, per session). Drift/SQLite is deferred to a later history change; the reasoning-capture decision here forward-compatibly informs the future nullable `reasoning_content` column.
