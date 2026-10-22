# Tasks

## 1. Project bootstrap

- [x] 1.1 Create the Flutter project (`dev.natter.app`), Android-only target, and verify `flutter analyze` and `flutter test` pass in the devcontainer
- [x] 1.2 Add dependencies `flutter_riverpod`, `http`, `flutter_secure_storage` to pubspec and verify the app still builds with no unused-dep warnings

## 2. Minimal single-endpoint configuration

- [x] 2.1 Build a config screen for base URL, API key, and model name; verify the values round-trip on reopening the screen
- [x] 2.2 Store the API key via `flutter_secure_storage` and verify the key is absent from logs and any non-secure settings store (test inspects stored locations)
- [x] 2.3 Expose the config as a single profile-shaped state (Riverpod) so change #2 generalizes it; verify a chat request reads URL/key/model from that state

## 3. Streaming request layer

- [x] 3.1 Implement `chat/completions` streaming over `http` SSE, parsing `data:` lines to `[DONE]`; verify a unit test replays a canned SSE fixture into ordered deltas
- [x] 3.2 Classify each delta as answer / reasoning / role-only, parsing reasoning from `reasoning_content ?? reasoning`; verify unit tests cover each field name and the role-only case

## 4. Assistant state machine and reasoning capture

- [x] 4.1 Implement the ephemeral state machine `Waiting` -> (`Thinking` while reasoning, no answer yet) / (answer on first content), role-only/empty deltas do not advance state; verify unit tests cover both transitions and the role-only guard
- [x] 4.2 Capture reasoning into in-memory session message state without rendering it; verify a test asserts reasoning is retained and answer text excludes it
- [x] 4.3 Animate the placeholder dots on a timer independent of token arrival and stop on cancel/error; verify a test that the timer stops after cancel

## 5. Chat screen rendering (plain text, ephemeral)

- [x] 5.1 Render user and assistant messages with the placeholder and streamed plain-text answer; verify a widget test shows streamed text growing incrementally
- [x] 5.2 Confirm the conversation lives only in memory; verify a test that no persistence write occurs and a fresh session starts empty

## 6. Streaming edge cases

- [x] 6.1 Implement cancel mid-stream preserving prior state; verify a test that partial output does not corrupt the conversation
- [x] 6.2 Surface mid-stream errors and keep prior messages intact; verify a test that an injected stream error leaves earlier messages unchanged
- [x] 6.3 Implement retry of the failed reply using existing conversation; verify a test that retry re-sends the conversation
- [x] 6.4 Implement blank-answer fallback (empty content + non-empty reasoning renders reasoning); verify a test with that fixture

## 7. On-device integration (Android)

- [ ] 7.1 Validate end-to-end against a live llama.cpp endpoint: a plain model streams token-by-token, and a qwen3 thinking model shows Waiting -> Thinking -> answer with reasoning hidden; verify by running on a connected Android device
- [ ] 7.2 Validate end-to-end against OpenRouter including a reasoning model; verify by running on a connected Android device
- [ ] 7.3 Exercise cancel, mid-stream error, retry, and blank-answer fallback on-device; verify each behaves per spec

## Workflow follow-up

- Run `flutter analyze && flutter test` and confirm green before requesting review.
- Archive the change after review requirements are satisfied; the `chat-streaming` spec then becomes project truth.
