# Spec Delta

## MODIFIED Requirements

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
