# Proposal

## Why

Natter sends the conversation to the endpoint with no steering at all, so a
model answers as if it were in a desktop web chat: long prose, heavy markdown,
and wide tables that break words on a phone (the table-width debt recorded in
`render-markdown-replies/validation.md` is one exhibit). A short system prompt
shipped with the app fits replies to a small phone chat by default, and an
editable setting keeps it the user's call (issue #11).

## What Changes

- The app ships a built-in default system prompt that asks for brief, direct,
  phone-readable replies with light formatting. With no action from the user,
  every request carries it.
- The settings screen gains one multi-line **System prompt** field, pre-filled
  with the prompt in effect, and a **Reset to default** action. The screen's
  title changes from `Endpoint` to `Settings`, since it no longer holds only
  endpoint fields.
- Saving the field unchanged keeps following the built-in default, so a better
  default in a later release reaches users who never edited it. An edited
  prompt is kept as written and survives restarts. A cleared field means no
  system message is sent at all.
- Every `chat/completions` request, including a retry and a new turn in a
  reopened conversation, carries the prompt in effect at send time as a single
  leading `role: system` message ahead of the conversation.
- The prompt is configuration, not conversation: it never appears in the
  transcript, is never written to conversation storage, and editing it changes
  only replies requested afterwards.

**Out of scope:** per-conversation prompts, a library of saved prompts or
presets, template variables (date, model name), a pre-message injected as a
user turn, and the Anthropic-native system field. Each would be its own
proposal. No non-goal from AGENTS.md is touched: the prompt is a request
parameter, not an agent, tool, or knowledge-base feature.

## Capabilities

### New Capabilities

- `system-prompt`: the built-in default prompt, the editable setting with
  reset and clear, its durability across restarts, its placement in every
  request, and its absence from the transcript and conversation storage.

### Modified Capabilities

- `chat-streaming`: "Streaming reply delivery" changes what goes on the wire -
  the request carries the system prompt in effect ahead of the conversation
  turns, instead of the conversation alone.

## Impact

- `lib/domain/`: a small system-prompt setting type with the built-in default
  text.
- `lib/data/`: a repository persisting the prompt in the existing plain
  settings store (`shared_preferences`), beside base URL and model.
- `lib/data/chat_completions_client.dart`: `ChatStreamService.stream` takes the
  prompt as its own parameter and prepends the system message when it is
  non-empty. `ChatMessage` and `ChatRole` stay user/assistant only, so a system
  turn cannot reach conversation storage.
- `lib/state/chat_providers.dart`: a provider for the prompt in effect, loaded
  at startup in `lib/main.dart`; the conversation controller passes it on send
  and retry.
- `lib/ui/settings_screen.dart`: the new field, reset action, and title.
- Tests: client payload shape, repository default/edited/cleared states,
  controller wiring, settings widget states; `test/support/test_support.dart`'s
  scripted service follows the new parameter.
- Acceptance suite: a new `integration_test/accept/system_prompt_accept_test.dart`.
- No new dependency, permission, or network destination: the prompt rides the
  existing request to the user's own endpoint.

## UX impact

The settings screen gains one field and one action; its title becomes
`Settings`. The chat screen is unchanged: no new control, no indicator, and
the prompt never shows in the transcript. The visible effect is in reply
shape - shorter, lighter-formatted answers by default. Empty, loading, error,
and cancel states of the chat screen are unchanged. See
`openspec/design-ux-guidelines.md`.
