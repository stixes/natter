# Spec Delta

## Purpose

Defines the chat screen's request and stream lifecycle against a user-configured OpenAI-compatible endpoint: the minimal single-endpoint configuration that drives it, streaming placeholder states, hidden reasoning capture, and streaming edge cases. This is the first thin vertical slice that proves the "point it at a base URL and chat" premise.

## ADDED Requirements

### Requirement: Single-endpoint configuration
The app SHALL provide a minimal configuration screen where the user sets one base URL, one API key, and one model name, and SHALL use that configuration for chat requests. The API key MUST be stored in secure, keystore-backed storage and MUST NOT be written to conversation storage, logs, or plain settings.

#### Scenario: Configure and use an endpoint
- **WHEN** the user enters a base URL, API key, and model name and returns to the chat screen
- **THEN** subsequent chat requests are sent to that base URL with that key and model

#### Scenario: API key is not persisted in the clear
- **WHEN** the app stores the configured API key
- **THEN** the key resides only in secure storage and does not appear in logs or conversation records

### Requirement: Streaming chat screen
The chat screen SHALL send the conversation to the configured endpoint as an OpenAI-compatible `chat/completions` request with streaming enabled and SHALL render the assistant reply incrementally as tokens arrive. The reply SHALL be rendered as plain text.

#### Scenario: Reply streams token by token
- **WHEN** the endpoint returns streamed completion chunks
- **THEN** the assistant message grows incrementally on screen rather than appearing only after the stream ends

#### Scenario: Answer shown as plain text
- **WHEN** an assistant answer contains markdown syntax
- **THEN** it is displayed as literal text without markdown rendering

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

#### Scenario: Mid-stream error
- **WHEN** the stream fails after some output
- **THEN** the failure is surfaced and prior messages remain intact

#### Scenario: Retry a failed reply
- **WHEN** the user retries after a failed reply
- **THEN** a new request is sent using the existing conversation

### Requirement: Ephemeral conversation
For this change the conversation SHALL live only in memory for the current app session and MUST NOT be written to persistent storage.

#### Scenario: Session restart clears the conversation
- **WHEN** the app is closed and reopened
- **THEN** the previous conversation is not restored
