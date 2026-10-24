# Spec Delta

## Purpose

Keeps conversations and their turns in local on-device storage so a chat survives closing
the app and can be reopened from a history list.

## ADDED Requirements

### Requirement: Local conversation storage
The app SHALL store committed conversation turns in local on-device storage and restore the
most recent conversation when it starts. A user turn SHALL be stored when it is sent and an
assistant turn when it is committed. An in-flight reply draft MUST NOT be stored.

#### Scenario: Conversation restored after a restart
- **WHEN** the user sends a few turns, closes the app, and opens it again
- **THEN** the most recent conversation is shown with its turns in their original order

#### Scenario: User turn survives a mid-reply exit
- **WHEN** the app is force-stopped while a reply is streaming
- **THEN** reopening the app shows the user turn that was already sent, the incomplete
  assistant reply is absent, and the conversation remains usable

#### Scenario: In-flight draft is not stored
- **WHEN** a reply is streaming and the on-device storage is inspected
- **THEN** no assistant turn for that in-flight reply exists yet

### Requirement: Conversation list and switching
The app SHALL show saved conversations newest first and SHALL let the user open a saved
conversation or start a new one. Opening SHALL load the stored turns. Starting a new chat
SHALL keep earlier conversations stored. Switching while a reply streams SHALL stop the
reply and keep the answer text already received.

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
- **THEN** the reply stops, the answer text already received, if any, is kept as the assistant
  turn in the conversation being left, and the selected conversation loads

#### Scenario: Empty conversation is not listed
- **WHEN** the user starts a new chat and sends nothing
- **THEN** no empty conversation appears in the history list

### Requirement: Conversation titles
The app SHALL title a conversation from its first user message, shortened for display,
without contacting the endpoint to generate the title. Later messages MUST NOT change the
title.

#### Scenario: Title from the first message
- **WHEN** the user sends the first message of a new conversation
- **THEN** the history list shows a title derived from that message

#### Scenario: Long first message is shortened
- **WHEN** the first user message is longer than the display limit
- **THEN** the title is shortened for the list rather than overflowing

#### Scenario: No separate title request
- **WHEN** a conversation is created and titled
- **THEN** no request is sent to the endpoint beyond the chat request itself

### Requirement: History stays on the device
The app SHALL keep conversation history on the device. It MUST NOT send history to any
network destination except the configured endpoint when the user sends a message. Android
Auto Backup SHALL be disabled for app data so history does not leave the device through the
OS backup service.

#### Scenario: Opening history makes no network request
- **WHEN** the user opens the history list or opens a saved conversation
- **THEN** no request is sent to the endpoint or any other network destination

#### Scenario: Auto Backup is disabled
- **WHEN** the installed app's merged manifest is inspected
- **THEN** Android Auto Backup is disabled for app data

### Requirement: History failures keep the conversation usable
If saving a turn fails, the app SHALL keep the turn visible in the current conversation and
SHALL tell the user it was not saved. If loading a conversation fails, the app SHALL remain
usable and SHALL tell the user the conversation could not be loaded.

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
- **THEN** the app opens with an empty conversation, shows a warning that history could not be
  loaded, and remains usable

#### Scenario: Load failure when opening a conversation
- **WHEN** opening a saved conversation fails
- **THEN** the current conversation stays usable and a warning says the selected conversation
  could not be loaded
