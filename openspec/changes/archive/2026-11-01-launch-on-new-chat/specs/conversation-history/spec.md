# Spec Delta

## MODIFIED Requirements

### Requirement: Local conversation storage
The app SHALL store committed conversation turns in local on-device storage. A
user turn SHALL be stored when it is sent and an assistant turn when it is
committed. An in-flight reply draft MUST NOT be stored. When the app starts, it
SHALL open a new chat rather than any stored conversation; opening a stored
conversation SHALL happen only through the history list.

#### Scenario: Conversation restored after a restart
- **WHEN** the user sends a few turns, closes the app, and opens it again
- **THEN** the chat screen shows a new, empty conversation, not the most recent
  one, with the chat screen's Empty state (composer and short prompt, per
  `openspec/design-ux-guidelines.md`), and the stored conversations appear in
  the history list and open with their turns in their original order

#### Scenario: User turn survives a mid-reply exit
- **WHEN** the app is force-stopped while a reply is streaming and the user
  later opens the history list
- **THEN** the user turn that was already sent is present in that conversation,
  the incomplete assistant reply is absent, and the conversation opens usable

#### Scenario: In-flight draft is not stored
- **WHEN** a reply is streaming and the on-device storage is inspected
- **THEN** no assistant turn for that in-flight reply exists yet

#### Scenario: Backgrounded app keeps its conversation
- **WHEN** the app is moved to the background while its process stays alive and
  the user returns to it
- **THEN** the conversation the user was in is shown exactly as it was left,
  including any in-flight reply state visible on screen

### Requirement: History failures keep the conversation usable
If saving a turn fails, the app SHALL keep the turn visible in the current
conversation and SHALL tell the user it was not saved. If loading a conversation
fails, the app SHALL remain usable and SHALL tell the user the conversation
could not be loaded.

#### Scenario: Save failure warns and keeps the turn
- **WHEN** a history write fails while a turn is being committed
- **THEN** the turn stays visible in the current conversation and a warning says it was not
  saved to history

#### Scenario: Save failure does not stop the reply
- **WHEN** a history write fails while the user sends a message
- **THEN** the chat request still runs and its reply appears, while the warning says the turn
  was not saved

#### Scenario: Load failure at startup
- **WHEN** saved history cannot be read while the app starts
- **THEN** the app opens with a new empty conversation, and the failure does
  not stop new chats or replies; when the history list is opened it reports
  that history is unavailable

#### Scenario: Load failure when opening a conversation
- **WHEN** opening a saved conversation fails
- **THEN** the current conversation stays usable and a warning says the selected conversation
  could not be loaded
