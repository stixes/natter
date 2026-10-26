# Proposal

## Why

The conversation history currently renders as one flat, ever-growing list. As the
number of saved chats increases, finding a recent conversation gets slower and
less obvious. Nothing ever removes old chats, so storage and the list only grow.
Grouping the list by recency and expiring conversations after a fixed period
keeps history fast to scan and bounded on disk.

## What Changes

- Group the history drawer into four sections: `Today`, `Yesterday`, `This week`,
  and `Older`.
- Permanently delete conversations whose `updatedAt` is more than 90 days in the
  past. The expiry runs once when the app starts, before the history list is
  first read. The 90-day period is fixed; there is no setting.
- Leave the conversation titles, the chat screen, and the streaming path
  unchanged.

**Out of scope:** archiving expired chats, a user-facing retention setting,
background expiry while the app is running, and grouping on anything other than
`updatedAt`.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `conversation-history`: the "Conversation list and switching" requirement gains
  section headers; a new requirement covers the 90-day expiry and its startup
  trigger. "Local conversation storage" is unaffected in its storage guarantees,
  but the spec gains a deletion behavior.

## Impact

- `lib/data/conversation_repository.dart`: add a bulk delete for conversations
  older than 90 days.
- `lib/state/chat_providers.dart`: run the expiry once on app start.
- `lib/ui/chat_screen.dart`: `_HistoryDrawer` renders section headers around the
  grouped list.
- Tests: repository deletion, grouping boundaries, empty and error states.
- No new dependency, permission, or network destination. No database schema
  change; rows are deleted with existing Drift queries.

## UX impact

The change touches the history drawer only. The chat screen is unchanged. Section
headers are static labels; empty, loading, and error states in the drawer keep
their current copy. See `openspec/design-ux-guidelines.md`.
