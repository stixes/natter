# Tasks

Depends on `add-streaming-spine` being archived (or its specs synced) so
`chat-streaming` exists under `openspec/specs/`; see that change's tasks.md
follow-up.

## 1. Ground the numbers before writing constants

- [x] 1.1 Time a cold model load against the live llama-swap: unload/idle the served model, then curl a streaming request and record how long until response headers arrive and until the first data line; write both numbers into design.md so the response-start constant is measured rather than guessed. Verify: the curl timings are pasted into design.md.
- [x] 1.2 Confirm on the same endpoint that SSE keepalive/comment lines actually arrive while a request is generating or loading (capture the raw stream with `curl -N`); if they do not, record that in design.md and note that the silence bound must therefore be sized for whole-generation gaps. Verify: a captured raw SSE sample referenced from design.md.

## 2. Bound the client

- [x] 2.1 Give `ChatCompletionsClient` its own `HttpClient` with `connectionTimeout` set, wired through the provider so one client is shared and disposed with the provider; verify a unit test where a refused connection fails in well under the budget, and `flutter analyze` stays clean.
- [x] 2.2 Add the response-start bound around `send()` plus the `The endpoint did not respond.` failure, and bound the HTTP >= 400 error-body read the same way; verify unit tests for a server that accepts the connection and never responds (a `dart:io` server in the test that opens the socket and stalls), and for a hung error body, both using an injected short budget.
- [x] 2.3 Add the silence bound on the SSE line stream plus the `The reply stopped arriving.` failure, mapping `TimeoutException` through the existing failure type and always cancelling the subscription; verify unit tests for a stream that stalls after some data, and that a keepalive/comment line resets the bound so an alive-but-slow stream completes.
- [x] 2.4 Make all three budgets injectable through optional named constructor parameters defaulting to the constants from task 1; verify a unit test that the defaults are the documented constants and that injection overrides them.

## 3. Make expiry visible without new UI

- [x] 3.1 On a silence-expiry failure, commit answer text that already reached the screen as the assistant turn (as cancel does), while other failures keep dropping the partial; verify unit tests for both branches, including that the committed turn is well-formed and the conversation stays sendable.
- [x] 3.2 Verify in a widget test that a timed-out request replaces the `Waiting` placeholder with the error banner carrying the right copy and a Retry that re-sends the existing conversation.
- [x] 3.3 Verify in the existing settings widget tests that configuration still exposes only base URL, API key, and model, so no timeout control has leaked into settings.

## 4. On-device confirmation

- [x] 4.1 Extend the `integration_test/` harness with a round against a black-holed endpoint (a port on the dev machine that the firewall drops rather than rejects, e.g. `http://<dev-box>:9/v1`) and assert the banner appears within the connect budget instead of `Waiting.` persisting; run it on the connected device and record the observed latency in a `validation.md` under this change.
- [x] 4.2 Add a stalled-stream variant to `integration_test/support/mock_reasoning_endpoint.py` (a few answer chunks, then silence past the bound) and assert on-device that the banner appears and the already-streamed text is kept as the reply; record the result in the same `validation.md`.

## 5. Wrap up

- [x] 5.1 Add the user-facing changelog entry under a new heading in CHANGELOG.md and verify the wording reads as behaviour, not implementation.

## Workflow follow-up

- Archive `add-streaming-spine` (or sync its specs) before applying this change.
- Run `flutter analyze && flutter test` green before requesting review.
- Archive this change after review so `chat-streaming` reflects the bounded-silence rule.
