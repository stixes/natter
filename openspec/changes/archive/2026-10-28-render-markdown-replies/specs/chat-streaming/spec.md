# Spec Delta

## REMOVED Requirements

### Requirement: Streaming chat screen
**Reason**: Its rendering claim, "The reply SHALL be rendered as plain text",
and its `Answer shown as plain text` scenario are withdrawn: an assistant reply
now renders as markdown, governed by the new `reply-rendering` capability. The
requirement's request and incremental-rendering behavior is unchanged and is
carried by `Streaming reply delivery`, added in this change.
**Migration**: Nothing to do for stored data or configuration. Anyone reading
the old requirement looks to `Streaming reply delivery` in `chat-streaming` for
the request and incremental rendering contract, and to `reply-rendering` for
how the reply is presented.

## ADDED Requirements

### Requirement: Streaming reply delivery
The chat screen SHALL send the conversation to the configured endpoint as an
OpenAI-compatible `chat/completions` request with streaming enabled, and SHALL
show the assistant reply growing as tokens arrive. How the reply is presented is
defined by the `reply-rendering` capability, not here.

#### Scenario: Reply streams token by token
- **WHEN** the endpoint returns streamed completion chunks
- **THEN** the assistant message grows incrementally on screen rather than appearing only after the stream ends
