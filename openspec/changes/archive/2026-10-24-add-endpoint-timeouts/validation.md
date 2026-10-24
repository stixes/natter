# Validation

## Environment

- Unit/widget tests: devcontainer (Flutter 3.29.3, Dart 3.7.2). `flutter analyze`
  is clean and `flutter test` is 76/76 passing.
- Live endpoint: llama-swap on the dev host, model `gemma4-26b-a4b`, reachable
  at the usual OpenAI-compatible base URL. Hosts and devices are placeholders
  per AGENTS.md "Publishing hygiene".

## Task 1.1 - cold-load measurement

The served model was unloaded (`POST /api/models/unload`) and then a streaming
`chat/completions` request was made. Measured with `curl -N`:

- Response headers: **12.28 s** (`time_starttransfer` = 12.283974 s).
- First SSE `data:` line: **12.50 s** (12.502 s measured by the client).
- Total request: **12.57 s**.

Recorded in `design.md`, with the 120 s response-start constant left roughly
10x above the measured cold load.

## Task 1.2 - keepalive behaviour

The cold-load stream was captured with `curl -N`. No SSE comment/keepalive
lines (`:` lines) arrived while the model loaded or generated; the first bytes
after the headers were a `data:` chunk. Recorded in `design.md`, which now
sizes the silence bound for whole-generation gaps rather than keepalive
heartbeats.

## Unit and widget coverage

- A refused connection fails under the connection budget.
- A server that accepts but never responds hits the response-start bound.
- A hung HTTP >= 400 error body hits the response-start bound.
- A stalled SSE stream hits the silence bound after some data.
- A keepalive/comment line resets the silence bound.
- The three budgets default to the documented constants and are injectable.
- A silence failure commits the partial answer and leaves the conversation
  sendable; other failures still drop the partial.
- A timed-out request replaces `Waiting` with the error banner and Retry
  re-sends the existing conversation.
- Settings still expose exactly base URL, API key, and model.

## On-device rounds - passed

Both rounds ran on a physical Android device (`<device>` over wireless adb,
Android 17 / API 37) against the dev box on the LAN. The app was built and
installed by the integration harness; the two cases filtered with
`--plain-name "timeout:"` both passed.

### Black-holed endpoint

Target: a port whose packets are dropped rather than refused
(`http://<black-hole-host>:9/v1`). The app's socket phase hit the 15 s connect
budget.

- Observed latency: **16,227 ms** from Send to the banner (15 s connect
  budget plus app/build overhead).
- The screen went `Waiting.` -> `Waiting..` -> `Waiting...` ->
  `The endpoint did not respond.` + `Retry`; no assistant turn was committed.
- The `Waiting` placeholder was gone after the failure.

### Stalled stream

Target: the `/stall` variant of
`integration_test/support/mock_reasoning_endpoint.py`, which streams a few
answer chunks and then goes silent past the silence bound.

- Observed latency: **61,927 ms** from Send to the banner (60 s silence bound
  plus overhead).
- The already-streamed text was kept as the assistant reply:
  `This answer starts normally. Then the stream goes silent. Keep this text
  after the timeout.`
- The screen showed `The reply stopped arriving.` + `Retry`, and the `Waiting`
  placeholder was gone.

### How it was run

```bash
python3 integration_test/support/mock_reasoning_endpoint.py 8010 &
adb connect <device>:<port>
flutter test integration_test/streaming_spine_test.dart \
  -d <device>:<port> --plain-name "timeout:" \
  --dart-define=NATTER_BLACK_HOLE_URL=http://<black-hole-host>:9/v1 \
  --dart-define=NATTER_STALL_URL=http://<dev-box>:8010/v1/stall \
  --dart-define=NATTER_PLAIN_MODEL=<model-tag>
```

Substitute the real host, device, and model; angle brackets are not shell-safe.
