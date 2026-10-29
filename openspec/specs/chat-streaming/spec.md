# chat-streaming Specification

## Purpose

Defines the chat screen's request and stream lifecycle against a user-configured OpenAI-compatible endpoint: the minimal single-endpoint configuration that drives it, streaming placeholder states, hidden reasoning capture, and streaming edge cases. This is the first thin vertical slice that proves the "point it at a base URL and chat" premise.

## Requirements

### Requirement: Single-endpoint configuration
The app SHALL provide a minimal configuration screen where the user sets one base URL, one API key, and one model name, and SHALL use that configuration for chat requests. The API key MUST be stored in secure, keystore-backed storage and MUST NOT be written to conversation storage, logs, or plain settings. The API key SHALL be optional: an endpoint that requires no authentication MUST be usable.

#### Scenario: Configure and use an endpoint
- **WHEN** the user enters a base URL, API key, and model name and returns to the chat screen
- **THEN** subsequent chat requests are sent to that base URL with that key and model

#### Scenario: An endpoint that needs no key
- **WHEN** the user sets a base URL and a model name and leaves the API key empty
- **THEN** the endpoint counts as configured, Send is enabled, and the request carries no `Authorization` header at all

#### Scenario: API key is not persisted in the clear
- **WHEN** the app stores the configured API key
- **THEN** the key resides only in secure storage and does not appear in logs or conversation records

### Requirement: Assistant placeholder states
While an assistant reply is not yet producing visible answer text, the app SHALL show an animated placeholder. The placeholder label SHALL be `Waiting` before the first answer or reasoning token arrives and SHALL change to `Thinking` while a reasoning stream is active and no answer text has begun. A role-only or empty delta MUST NOT end the waiting state.

#### Scenario: Waiting before any token
- **WHEN** the request has been sent and no answer or reasoning token has arrived
- **THEN** an animated `Waiting` placeholder is shown

#### Scenario: Switch to Thinking on reasoning output
- **WHEN** the first streamed token is a reasoning token and no answer text has begun
- **THEN** the placeholder changes to an animated `Thinking`

#### Scenario: Straight to answer when no reasoning
- **WHEN** the first streamed token is answer text and no reasoning was seen
- **THEN** the placeholder is replaced by the streaming answer

### Requirement: Reasoning capture without display
The app SHALL capture reasoning output when present, whether delivered in a `reasoning_content` or a `reasoning` field, and SHALL retain it for the current session. The app MUST NOT render reasoning text in the assistant message.

#### Scenario: Reasoning from reasoning_content
- **WHEN** the stream delivers reasoning in a `reasoning_content` field
- **THEN** the reasoning is retained and not shown in the answer

#### Scenario: Reasoning from reasoning field
- **WHEN** the stream delivers reasoning in a `reasoning` field
- **THEN** the reasoning is retained and not shown in the answer

### Requirement: Blank-answer fallback
If the stream ends with empty answer text but non-empty captured reasoning, the app SHALL display the reasoning as the answer instead of an empty message.

#### Scenario: Answer lands entirely in reasoning
- **WHEN** the stream ends with empty answer content and non-empty reasoning
- **THEN** the reasoning is displayed as the assistant answer

### Requirement: Streaming edge cases
The app SHALL let the user cancel an in-flight stream, SHALL surface an error and preserve prior conversation state when a stream fails mid-flight, and SHALL let the user retry a failed reply.

#### Scenario: Cancel mid-stream
- **WHEN** the user cancels while a reply is streaming
- **THEN** streaming stops and the partial state does not corrupt the conversation

#### Scenario: Cancel before any answer text arrives
- **WHEN** the user cancels while only reasoning has streamed
- **THEN** no assistant turn is committed and the conversation is unchanged, because half a chain of thought is not an answer

#### Scenario: Mid-stream error
- **WHEN** the stream fails after some output
- **THEN** the failure is surfaced and prior messages remain intact

#### Scenario: Retry a failed reply
- **WHEN** the user retries after a failed reply
- **THEN** a new request is sent using the existing conversation

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

### Requirement: Durable endpoint configuration
The app SHALL write the configured base URL and model name to durable on-device settings
and restore them when the app starts, so an endpoint configured once remains in use after
a restart. The API key MUST NOT be written to that settings store; it SHALL continue to
reside only in secure, keystore-backed storage.

#### Scenario: Configuration survives a restart
- **WHEN** the user saves a base URL and model name, closes the app, and opens it again
- **THEN** the endpoint counts as configured and chat requests use the saved base URL and
  model without the user entering them again

#### Scenario: The API key stays out of plain settings
- **WHEN** the user saves an endpoint that includes an API key
- **THEN** the key is present only in secure storage and absent from the durable plain
  settings that hold the base URL and model

#### Scenario: A keyless endpoint survives a restart
- **WHEN** the user saves a base URL and model name with no API key and restarts the app
- **THEN** the base URL and model are restored, the endpoint still counts as configured,
  and requests carry no `Authorization` header

#### Scenario: First launch after the upgrade
- **WHEN** the app starts with an API key already in secure storage but no saved base URL
  or model
- **THEN** the endpoint counts as unconfigured until the user saves a base URL and model,
  after which both persist across later restarts

### Requirement: Streaming reply delivery
The chat screen SHALL send the conversation to the configured endpoint as an
OpenAI-compatible `chat/completions` request with streaming enabled, preceded
by the system prompt in effect as defined by the `system-prompt` capability,
and SHALL show the assistant reply growing as tokens arrive. How the reply is
presented is defined by the `reply-rendering` capability, not here.

#### Scenario: Reply streams token by token
- **WHEN** the endpoint returns streamed completion chunks
- **THEN** the assistant message grows incrementally on screen rather than appearing only after the stream ends

#### Scenario: Request carries the prompt ahead of the conversation
- **WHEN** a message is sent with a non-empty system prompt in effect
- **THEN** the request's messages are the system prompt first, then the
  conversation's user and assistant turns in order
