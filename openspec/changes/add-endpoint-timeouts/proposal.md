# Proposal

## Why

On a real device an endpoint that never answers leaves the app waiting forever. During
on-device validation for `add-streaming-spine`, a base URL whose hostname did not
resolve left the reply slot at `Waiting.` for more than two minutes and surfaced
nothing at all; a stream that opens and then goes silent is equally invisible. For a
BYO-endpoint app, a dead, sleeping, or mistyped endpoint is the single most likely
failure a user hits, and the app currently has no way to admit it. Fixing it is a
one-line-ish change, and it is the difference between "the app is broken" and "the app
told me what to check".

## What Changes

- Bound how long a chat request may go without progress: one budget for the endpoint to
  start answering, one idle budget once a stream has started.
- When a budget expires, end the request as a failure shown in the existing error banner,
  with the existing Retry affordance. Prior conversation state is untouched, which the
  spec already requires for mid-stream failures.
- SSE comments and keepalives count as progress, so an alive-but-quiet endpoint is not
  killed.
- Thresholds are fixed constants in the client, tuned against a live llama.cpp-family
  server during implementation. They are not user-facing settings.
- Error copy distinguishes the two cases plainly: the endpoint never started answering,
  versus it stopped answering mid-reply.

Deliberately out of scope: user-configurable timeouts, retry/backoff policies or automatic
retries, preflight endpoint checks such as `GET /models` or a connectivity probe,
connection pooling or warm-up behaviour, any limit on how long a model may *think* (the
idle budget bounds silence between bytes, never thinking time, and keepalives reset it),
and richer diagnostics such as latency display.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `chat-streaming`: the streaming edge-cases requirement gains bounded silence. The app
  MUST NOT wait indefinitely on an endpoint that is not producing anything, and the
  timeout failures land in the same surface-and-retry path as other stream failures.

Sequencing: `chat-streaming` is not yet under `openspec/specs/`; it lands when
`add-streaming-spine` (18/18 tasks, validated) is archived or its specs are synced. This
delta is written against that archived requirement text, so archive or sync first.

## Impact

- `lib/data/chat_completions_client.dart`: wraps the existing `send` and the SSE line
  stream with timeouts, and adds two failure messages. The failure type and the
  key-redaction rule (a failure message can never carry the API key) are unchanged.
- `lib/state/chat_providers.dart`, `lib/ui/chat_screen.dart`: no new UI. Timeouts reuse
  the error banner and Retry that already exist.
- Tests: unit tests drive expired budgets through the scripted seam with short values; the
  client gains injectable budgets for tests only, defaulting to the production constants.
- No new dependencies, no new permissions, no network destination beyond the
  user-configured base URL (the existing `INTERNET` permission already covers it).
- On-device: the harness under `integration_test/` already has an unreachable-endpoint
  round; the timeout rounds extend it (a black-holed port and a stalled mock stream).
- Changelog: one user-facing line - Natter gives up on an endpoint that stops answering
  and says which case it was.
