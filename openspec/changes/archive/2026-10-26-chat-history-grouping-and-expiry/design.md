# Design

## Context

See `proposal.md` - Why. The history drawer renders a flat `ListView` driven by
`conversationListProvider`, which streams `ConversationSummary` objects sorted by
`updatedAt` descending. `ConversationRepository` reads from the Drift `AppDatabase`.
`main()` already restores the most recent conversation before `runApp`, but there is
no deletion path today.

## Goals / Non-Goals

**Goals:**
- Group the history list into four recency sections without changing the underlying
  data shape.
- Delete expired conversations once per app start, before the history list is first
  read.

**Non-Goals:**
- Archiving or soft-deleting expired chats.
- Background expiry while the app runs.
- A settings control for the retention period.
- Changing the database schema.

## Decisions

### Grouping is computed in the presentation layer
The repository keeps returning a flat, sorted list. A new pure helper in the UI layer
(`groupConversations(List<ConversationSummary>, DateTime now)`) partitions the list
into four buckets. `_HistoryDrawer` renders section headers and tiles from that
structure. Rationale: grouping depends on the current time and is purely
presentational; keeping it out of the repository avoids changing the storage seam and
makes the boundaries unit-testable without a database. Alternative considered: group
in the repository; rejected because the repository would need a clock and the grouping
has no storage meaning.

### Grouping boundaries use local calendar time
- **Today**: `updatedAt` falls on the same local calendar day as `now`.
- **Yesterday**: `updatedAt` falls on the previous local calendar day. Yesterday takes
  precedence even when it falls in the previous week.
- **This week**: `updatedAt` falls in the current local calendar week but not Today or
  Yesterday. The week starts on the locale's first day; the app uses the device locale.
- **Older**: everything else.

The helper takes `now` as a parameter so tests can fix the clock. Each section stays
sorted newest first.

### Expiry runs in `main()` before the first read
`main()` already awaits settings and history restoration before `runApp`. Add a call to
`conversationRepositoryProvider.deleteExpiredBefore(DateTime.now().subtract(const
Duration(days: 90)))` before `restoreMostRecent()`. Rationale: the spec requires expiry
before the history list is first read; running it in the startup path guarantees that
ordering. Alternative considered: run it lazily when `conversationListProvider` first
builds; rejected because the provider can rebuild and would repeat the deletion during
a session.

### Deletion is a single repository transaction
`ConversationRepository.deleteExpiredBefore` executes a Drift `delete` on
`Conversations` where `updatedAt` is older than the cutoff. The `Messages` table
declares `onDelete: KeyAction.cascade`, so deleting the conversation removes its turns
in the same statement when foreign keys are enforced. The generated database does not
show a `PRAGMA foreign_keys = ON` hook, so the implementation deletes messages for the
selected conversation IDs first, then the conversations, inside one transaction. The
method returns the number of deleted conversations for tests. A failure is caught by
the caller so startup continues.

### Startup failure is non-fatal
`main()` wraps the expiry call in a `try/catch`. A failed deletion does not stop the
app from starting or from reading the remaining history. The failure is not surfaced in
the UI in this change; the spec's "Expiry leaves the app usable when storage fails"
scenario only requires that the app opens and remains usable. Rationale: an expiry
failure is a maintenance failure, not a user action; a banner would add noise without
an actionable remedy.

## Risks / Trade-offs

- **Expiry only on start** -> A long-running app keeps expired chats until the next
  launch. Accepted for this change; background expiry is a separate proposal.
- **Irreversible deletion** -> Deleted chats cannot be recovered. Mitigation: the spec
  fixes the period at 90 days and the proposal excludes archiving; a future change that
  needs recovery would add a soft-delete column.
- **Grouping uses the device clock** -> Changing the device date or timezone shifts
  section boundaries. Accepted; the list is recency-oriented, not an audit trail.
- **Cascade assumption** -> If foreign keys are not enforced, a naive conversation
  delete would leave orphaned messages. Mitigation: delete messages explicitly in the
  same transaction, as described above.

## Migration Plan

No schema change. Existing conversations are kept. The first launch after the update
runs the expiry once; conversations older than 90 days are deleted at that point.
Rollback: reverting the code stops future expiry runs, but already-deleted
conversations cannot be restored. There is no data migration.

## UX and interaction

See `openspec/design-ux-guidelines.md`.

- **States**: The drawer already covers loading (`Loading...`), empty (`No
  conversations yet.`), error (`History unavailable.`), and data. Grouping adds section
  headers only in the data state; empty and error states are unchanged. Expiry is silent
  and has no separate loading state.
- **Motion**: No new motion. Section headers appear as static labels; no animation is
  added.
- **Accessibility**: Section headers use `Semantics(header: true)` and theme text styles
  so screen readers announce them as headings. The existing 48dp list-tile targets are
  unchanged. Contrast follows the Material 3 theme in light and dark.
- **Copy**: Section labels are exactly `Today`, `Yesterday`, `This week`, and `Older`.
  No new copy for expiry; deletion is silent.
- **Dark mode**: Header text uses the theme's `titleSmall` style and
  `colorScheme.onSurfaceVariant`; no hard-coded colors.
- **Not applicable**: Keyboard/focus order and streaming placeholder motion are
  unchanged by this feature.
