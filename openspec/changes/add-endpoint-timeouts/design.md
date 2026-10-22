# Design

## Context

See proposal.md - Why. The relevant current state:

- `ChatCompletionsClient.stream` (lib/data/chat_completions_client.dart) has two
  unbounded waits: `await _http.send(request)` (DNS + TCP + TLS + response headers) and
  `await for (final line in lines)` over the SSE body. Neither has a deadline.
- The error body read on HTTP >= 400 (`response.stream.bytesToString()`) is unbounded too.
- On Android, `dart:io`'s `HttpClient` (which backs `package:http`'s `IOClient`) has no
  read timeout, and `connectionTimeout` is unset by default. Unlike OkHttp there is no
  platform stack supplying sane defaults for us.
- Failure handling already exists: `_fail` (lib/state/chat_providers.dart) drops the
  partial draft, keeps prior messages, and the `_ErrorBanner` in lib/ui/chat_screen.dart
  already offers Retry and dismiss. No new UI is needed.
- Observed on-device: an unresolvable hostname left the reply slot at `Waiting.` for over
  two minutes with no error; an unreachable LAN port failed immediately with
  `No route to host`. So the socket layer sometimes reports fast, and sometimes never
  reports at all. A bound is what makes it deterministic either way.

## Goals / Non-Goals

**Goals:**

- Every chat request has a deadline for making progress, and expiry is visible to the
  user through the existing banner and Retry.
- Bounds are strict enough that a dead endpoint stops waiting in seconds, and loose
  enough that a cold local model load and a slow-but-alive stream are never punished.
- Timeouts are testable without a network or fake clocks.

**Non-Goals:**

- No new UI, no countdown, no progress meter, no latency display.
- No automatic retry, backoff, or failover; no endpoint preflight or health probe.
- No user-facing or profile-level timeout settings.
- No change to how long a model may think: the bound is on bytes, not on thinking.

## Decisions

**Three bounds, each aimed at a distinct failure mode, enforced in the client.**

1. Socket phase: `HttpClient.connectionTimeout = 15s`, set by constructing the client as
   `http.IOClient(HttpClient()..connectionTimeout = ...)`. Bounds DNS + TCP + TLS. This
   is what fixes the observed indefinite hang, because a mistyped or black-holed host
   never reaches the response phase at all. Alternative considered: rely on
   `Future.timeout` around `send()` alone - rejected, it would have to be generous enough
   for cold model loads, so a mistyped hostname would still hang for minutes.
2. Response start: `send().timeout(120s)`. Bounds the wait for response headers, which a
   local server can delay while it loads a model. Alternatives: no bound here (rejected: a
   connection that opens and then says nothing is exactly the observed failure), or a tight
   bound here (rejected: it aborts cold loads, which is worse than the hang being fixed).
3. Silence once streaming: `lines.timeout(60s)`. `Stream.timeout` applies per event, which
   is precisely idle-between-bytes semantics, and it resets on any line - including SSE
   comment/keepalive lines, which `sseData` already discards downstream. So a quiet but
   alive endpoint is not killed. Alternative: a single all-in request deadline (rejected:
   cannot distinguish "slow" from "dead").

**Keep the streamed text when silence kills the stream.** If the silence bound expires
after answer text has already reached the screen, that text is committed as the assistant
turn the way cancel commits it, instead of being dropped by `_fail`. Rationale: the user
watched it arrive; the app decided to give up, so the app should not also destroy the
evidence. Alternatives: keep today's drop-partial behaviour for timeouts too (rejected:
harsher than the hang it replaces), or apply keep-partial to every stream failure
(more consistent, but it changes behaviour the current spec describes for endpoint errors,
so it is deferred; if wanted it should be its own requirement).

**Two distinct failure messages, neither of which echoes the base URL.**
`The endpoint did not respond.` for bounds 1 and 2, `The reply stopped arriving.` for
bound 3. Not echoing the URL keeps the existing invariant that a failure message can never
carry a secret, which matters because users sometimes smuggle credentials into URLs.

**Injectable budgets for tests, production defaults in the client.** Optional named
constructor parameters defaulting to the constants, so unit tests use 40-80 ms budgets and
stay deterministic. Alternative: inject a clock and use fake async (rejected: more
machinery than the behaviour under test deserves).

**Errors map to the existing `ChatRequestFailure`** with a flag marking a silence failure so
the controller can decide to commit the partial. Alternative: a separate failure type
(rejected: the controller and UI already branch on one type, and the UI copy is data).

## Risks / Trade-offs

- A local model that takes longer than 120s to load fails with "the endpoint did not
  respond", which reads like a dead endpoint. Mitigation: measure a cold load on the live
  llama-swap during implementation and set the constant from the measurement, not from
  this document; the message tells the user to check the server.
- A gateway that buffers and sends no keepalives could be killed at 60s of silence.
  Mitigation: 60s is far beyond token gaps; the on-device stalled-stream round exercises
  it, and Retry is one tap.
- `Stream.timeout` throws inside `await for` and can leave the subscription live.
  Mitigation: catch `TimeoutException` in the same try that maps `ClientException`, and
  route through the existing `_stop`/`_fail` path so the subscription is always cancelled.
- Owning an `HttpClient` for bound 1 adds a lifecycle the client must close. Mitigation:
  one long-lived client per app, created in the provider wiring, closed on dispose.

## Open Questions

- Whether the response-start bound should measure the first SSE event rather than response
  headers. Implementation detail: both are currently bounded, and tightening it later does
  not change the spec or the tasks.
