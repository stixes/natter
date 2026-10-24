# Spec Delta

## REMOVED Requirements

### Requirement: Ephemeral conversation
**Reason**: Conversation history now persists committed turns in local on-device storage and
restores the most recent conversation at startup. Memory-only conversation was the first
streaming slice's limitation, not a lasting product rule.

**Migration**: No prior persisted conversation exists. The app starts with an empty history
and creates conversations as the user chats; the `conversation-history` capability owns
storage and restoration.
