# system-prompt Specification

## Purpose

Shapes every reply to a small phone chat by sending a system prompt with each
request: a built-in default that works with no setup, which the user can edit,
reset, or clear in settings.

## Requirements

### Requirement: Built-in default prompt
The app SHALL ship a built-in default system prompt that asks for brief, direct
replies with light, phone-readable formatting. Until the user saves an edited
or cleared prompt, the built-in default SHALL be the prompt in effect, with no
setup required.

#### Scenario: Fresh install uses the default
- **WHEN** the user configures an endpoint on a fresh install and sends a
  message without opening the prompt setting
- **THEN** the request carries the built-in default prompt

#### Scenario: The default is visible where it is set
- **WHEN** the user opens settings without having edited the prompt
- **THEN** the system prompt field shows the full built-in default text

### Requirement: Editable prompt setting
The settings screen SHALL offer one multi-line system prompt field showing the
prompt in effect. Saving SHALL make the field's text the prompt in effect for
every later request. Saving text identical to the built-in default SHALL keep
following the built-in default rather than storing a copy of it.

#### Scenario: An edited prompt takes effect
- **WHEN** the user replaces the prompt text, saves, and sends a message
- **THEN** the request carries the edited text instead of the default

#### Scenario: Leaving without saving changes nothing
- **WHEN** the user edits the prompt field and leaves settings without saving
- **THEN** the prompt in effect is unchanged and reopening settings shows it

#### Scenario: Saving untouched text follows the default
- **WHEN** the user saves settings without changing the pre-filled default
  prompt, and a later release ships a different built-in default
- **THEN** the later release's default is the prompt in effect

### Requirement: Reset to default
The settings screen SHALL offer a reset action that replaces the field's text
with the built-in default. The reset SHALL take effect when the user saves,
like any other edit to the field, and SHALL be operable by touch and by screen
reader per `openspec/design-ux-guidelines.md`.

#### Scenario: Reset restores the default
- **WHEN** the user has an edited prompt, uses reset, and saves
- **THEN** the field shows the built-in default and later requests carry it

#### Scenario: Reset is reachable without sight
- **WHEN** a screen-reader user moves focus through the settings screen
- **THEN** the reset action is announced with a label that says what it does,
  and its touch target is at least 48x48 dp

### Requirement: Cleared prompt sends no system message
A prompt that is empty or only whitespace when saved SHALL mean no system
prompt: requests SHALL carry no system message at all, and the setting SHALL
stay empty rather than reverting to the default, until the user enters text or
uses reset.

#### Scenario: Clearing the prompt
- **WHEN** the user clears the field, saves, and sends a message
- **THEN** the request carries only the conversation turns, with no system
  message

#### Scenario: A cleared prompt stays cleared
- **WHEN** the user has cleared the prompt and restarts the app
- **THEN** the field is still empty and requests still carry no system message

### Requirement: Durable prompt setting
The app SHALL keep a saved prompt, edited or cleared, in durable on-device
settings and restore it when the app starts. The prompt SHALL NOT be stored
with conversations, and SHALL NOT be stored in or alongside the secure storage
that holds the API key.

#### Scenario: An edited prompt survives a restart
- **WHEN** the user saves an edited prompt, closes the app, and opens it again
- **THEN** the field shows the edited prompt and requests carry it

### Requirement: Prompt placement in requests
Every `chat/completions` request, including a retry and a turn in a reopened
conversation, SHALL carry the prompt in effect at the moment it is sent as one
`system` message placed before all conversation turns. A changed prompt SHALL
apply from the next request on, without altering stored turns.

#### Scenario: System message comes first
- **WHEN** a request is sent with a non-empty prompt in effect
- **THEN** its first message has role `system` and the prompt as content, and
  exactly one such message is present

#### Scenario: A retry uses the current prompt
- **WHEN** a reply fails, the user changes the prompt in settings, and then
  retries
- **THEN** the retried request carries the changed prompt

#### Scenario: A reopened conversation gets the current prompt
- **WHEN** the user reopens a saved conversation and sends a new turn
- **THEN** the request carries the prompt in effect now, ahead of the stored
  turns

### Requirement: Prompt stays out of the conversation
The system prompt SHALL NOT appear in the transcript, SHALL NOT be written to
conversation storage, and SHALL NOT influence the conversation's title.

#### Scenario: Transcript shows only the exchange
- **WHEN** a reply completes for a request that carried a system prompt
- **THEN** the transcript shows the user turn and the reply only, with no
  bubble or label for the prompt

#### Scenario: History holds no prompt
- **WHEN** the user reopens a conversation whose requests carried a prompt
- **THEN** the restored turns are the user and assistant messages only
