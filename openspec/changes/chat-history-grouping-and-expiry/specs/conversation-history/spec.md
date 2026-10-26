# Spec Delta

## MODIFIED Requirements

### Requirement: Conversation list and switching
The app SHALL show saved conversations newest first and SHALL let the user open a saved conversation or start a new one. Opening SHALL load the stored turns. Starting a new chat SHALL keep earlier conversations stored. Switching while a reply streams SHALL stop the reply and keep the answer text already received. The history list SHALL group conversations into Today, Yesterday, This week, and Older sections based on each conversation's last update time.

#### Scenario: Newest conversation first
- **WHEN** the user has more than one saved conversation
- **THEN** the history list shows the most recently updated conversation first

#### Scenario: Open a saved conversation
- **WHEN** the user selects a saved conversation from the history list
- **THEN** its stored turns are loaded into the chat screen in order

#### Scenario: New chat preserves earlier conversations
- **WHEN** the user starts a new chat and sends a message
- **THEN** the previous conversation remains available in the history list

#### Scenario: Switch mid-stream
- **WHEN** the user opens another conversation or starts a new chat while a reply is streaming
- **THEN** the reply stops, the answer text already received, if any, is kept as the assistant turn in the conversation being left, and the selected conversation loads

#### Scenario: Empty conversation is not listed
- **WHEN** the user starts a new chat and sends nothing
- **THEN** no empty conversation appears in the history list

#### Scenario: History grouped by recency
- **WHEN** the history list renders conversations with different last update times
- **THEN** conversations appear under Today, Yesterday, This week, or Older section headers matching their last update time

#### Scenario: Empty section is not shown
- **WHEN** no conversation falls into a grouping period
- **THEN** that section header does not appear in the history list

## ADDED Requirements

### Requirement: History expiry
The app SHALL permanently delete conversations whose last update time is more than 90 days in the past. The expiry SHALL run once when the app starts, before the history list is first read. It SHALL NOT run when the history list is opened. The 90-day period SHALL be fixed and SHALL NOT be user-configurable.

#### Scenario: Expired conversations are removed on app start
- **WHEN** the app starts and a saved conversation's last update time is more than 90 days in the past
- **THEN** that conversation and its stored turns are deleted from the device and do not appear in the history list

#### Scenario: Recent conversations are kept
- **WHEN** the app starts and a saved conversation's last update time is 90 days ago or more recent
- **THEN** the conversation remains stored and appears in the history list

#### Scenario: Opening history does not trigger expiry
- **WHEN** the user opens the history list during a running app session
- **THEN** no conversation is deleted by that action

#### Scenario: Expiry leaves the app usable when storage fails
- **WHEN** the app starts and deleting an expired conversation fails
- **THEN** the app opens with the history it can read and remains usable, and the failed deletion does not stop new chats or replies
