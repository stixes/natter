# Spec Delta

## ADDED Requirements

### Requirement: Bounded silence from an unresponsive endpoint
The app SHALL NOT wait indefinitely for an endpoint to make progress. It SHALL bound the
wait for an endpoint to begin responding, and the silence once a stream has begun; when a
bound expires the request SHALL end as a failure surfaced with Retry. Receiving any bytes
on an open stream, including answer text, reasoning, or SSE keepalive comments, SHALL count
as progress and reset the silence bound. The bounds SHALL NOT be user-configurable.

#### Scenario: Endpoint never begins responding
- **WHEN** a send targets a base URL that establishes no usable connection, or opens one and
  never begins a response
- **THEN** within the bound the `Waiting` placeholder is replaced by a surfaced failure with
  Retry, and the conversation up to and including the user's message is unchanged

#### Scenario: Endpoint goes silent mid-reply
- **WHEN** a stream has delivered answer text and then delivers nothing for longer than the
  silence bound
- **THEN** the request ends as a surfaced failure with Retry, and the answer text already
  delivered is kept as the assistant reply rather than discarded

#### Scenario: Slow but alive endpoint is not punished
- **WHEN** an endpoint keeps the stream open and keeps producing bytes, however slowly
- **THEN** no bound expires and the reply continues to completion

#### Scenario: Cold start of a local server is tolerated
- **WHEN** a local endpoint is slow to begin responding because it is loading a model
- **THEN** the app waits at least the full bound for it to begin, and only then fails

#### Scenario: Bounds are not settings
- **WHEN** the user configures an endpoint
- **THEN** no timeout value is offered, and the bounds are the app's own
