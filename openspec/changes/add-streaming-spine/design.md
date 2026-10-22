# Design

## Context

See proposal.md - Why. The repo is greenfield: no Flutter project, code, or specs exist yet. This change bootstraps the app and stands up the streaming spine as the first thin slice. The constraints that shape the approach are the stack rules (Riverpod, `http`, secure storage, justify every dep), Android-only, and the reality that "OpenAI-compatible" spans several dialects (grounded against llama.cpp, llamaswap, and OpenRouter).

## Goals / Non-Goals

**Goals:**
- One end-to-end path: configure an endpoint, send a chat request, stream and render an assistant reply smoothly on Android.
- Prove the compat + ChatGPT-quality streaming bet on real endpoints. For this change that means a live llama.cpp-family endpoint on a device; the hosted-provider leg is deferred (see Decisions).
- Establish an architecture that profiles (change #2) and history (change #3) extend rather than replace.

**Non-Goals:**
- Endpoint profiles / switching, model picker backed by `/v1/models`, persisted history, thread lists, markdown, show-thinking toggle, reasoning replay, Anthropic-native format, iOS polish.

## Decisions

- **Streaming via `http` SSE.** Use the `http` package to open the `chat/completions` stream and parse `data:` lines manually, terminating on `[DONE]`. Chosen over a cloud SDK to keep the BYO-endpoint contract thin and honor the no-SDK stack rule. Alternative (an OpenAI client package) rejected: hides the dialect differences we must handle explicitly.

- **Placeholder state machine driven by first-token classification.** The assistant bubble has ephemeral states: `Waiting` (nothing yet) -> either `Thinking` (first token is reasoning, no answer yet) or answer (first token is content). A role-only/empty delta does not advance the state. The dots animate on a frame timer independent of token arrival, and the timer stops on cancel/error. This single `Waiting`/`Thinking` affordance covers both "we hide reasoning" (Qwen, deepseek) and "the provider hides reasoning" (o-series), so it is the universal waiting-for-answer affordance, not a reasoning feature.

- **Reasoning parse = flat-string superset `reasoning_content ?? reasoning`.** Covers llama.cpp/llamaswap (`reasoning_content`) and OpenRouter/Ollama-style (`reasoning`) with zero config. Reasoning is captured and kept in memory for the session, but not rendered. Rationale: hide-by-default matches cloud UX, and persisting keeps the in-session conversation replayable for models that expect it (Qwen). Alternatives: auto-detect the field name (rejected: fragile, needs probes, fights BYO-URL ethos); a per-provider field config (deferred to a later profile-level flag).

- **`reasoning_details` (OpenRouter structured/signed array) is out of scope.** It matters mainly for signed-thinking replay with tool use; tools are a non-goal, so v1 uses the flat string superset.

- **No reasoning replay in this change.** Reasoning is stored/replayed within the in-memory session but NOT echoed back in requests. `reasoning_content` on an assistant message is not part of the OpenAI schema, so replay is a per-gateway policy problem; default store-and-not-replay, defer replay to a later profile-level capability.

- **Blank-answer fallback.** If the stream ends with empty content but non-empty reasoning, render the reasoning as the answer. Grounded failure mode: some qwen3 runs never emit the thinking-end marker, so the whole answer lands in reasoning and content stays empty.

- **Ephemeral, in-memory session state (Riverpod).** No Drift/SQLite this change. The reasoning-capture decision forward-compatibly informs the future nullable `reasoning_content` message column. Alternative (add persistence now) rejected: keeps the slice tiny and retires the product risk first.

- **Minimal single-endpoint config as a degenerate profile.** One base URL + key + model, shaped like the future multi-profile model so change #2 generalizes rather than rewrites. Key stored via `flutter_secure_storage` (keystore-backed), never in conversation storage/logs/plain settings.

- **Plain-text answer rendering.** Defer markdown to a later change to keep deps minimal and prove streaming first.

- **Android only.** Framework does not block iOS, but nothing here targets iOS polish; validation is on an Android device.

- **OpenRouter (second-provider) validation is deferred out of this change.** The reasoning-field superset (`reasoning_content` vs `reasoning`) has therefore only been proven against a llama.cpp-family gateway, not against an OpenRouter-shaped dialect, and no TLS-on-device path was observed either (the test device could not resolve the HTTPS front hostname). Rationale: MVP is BYO-endpoint with no hosted-provider requirement, no key was available, and holding a task-complete slice open on it buys nothing. The debt is explicit: the next change that touches provider differences (profiles, or any change that adds a hosted provider) owes an on-device round against a second provider, including one that requires an API key, using the harness under `integration_test/`. `validation.md` in this change records exactly which rounds ran and which did not.

## Risks / Trade-offs

- Throwaway config UI: the single-endpoint screen is later superseded by profiles. Mitigation: shape it as one profile from the start; rework is small.
- Mid-stream error / malformed SSE handling is where compat clients usually break. Mitigation: explicit edge-case requirements (cancel, error, retry, blank-answer) are acceptance criteria, validated on a real llama.cpp-family endpoint; the second-provider leg of that validation is deferred, so dialect coverage is thinner than originally planned (see Decisions).
- Superset parse could mis-handle a future dialect where both fields mean different things. Mitigation: v1 takes whichever is present; profile-level field policy is the named later escape hatch.
- Ephemeral state means "history is sacred" is not yet satisfied. Accepted: this slice targets the product bet; persistence is change #3.

## Open Questions

- Exact retry semantics (re-send whole conversation vs last turn) - resolvable at implementation without changing specs.
- Whether the single model field gains free-text vs picker behavior in change #2 (out of scope here; free-text only for #1).
