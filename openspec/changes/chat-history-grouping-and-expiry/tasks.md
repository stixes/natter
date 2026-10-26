# Tasks

## 1. Grouping helper

- [x] 1.1 Implement a pure `groupConversations(List<ConversationSummary>, DateTime now)` helper that returns Today, Yesterday, This week, and Older buckets using local calendar time. Verify with `flutter test test/history_grouping_test.dart`, covering each boundary and the Yesterday-overlaps-previous-week case.
- [x] 1.2 Add unit tests for an empty conversation list and for conversations with identical timestamps staying newest first. Verify with the same test file.

## 2. Repository expiry

- [x] 2.1 Add `deleteExpiredBefore(DateTime cutoff)` to `ConversationRepository`, deleting messages for expired conversations first and then the conversations inside one transaction. Verify with `flutter test test/conversation_repository_test.dart`, asserting the row counts before and after.
- [x] 2.2 Add a repository test that a deletion failure leaves the database readable and throws without corrupting remaining rows. Verify with the same test file.

## 3. Startup wiring

- [x] 3.1 Call `deleteExpiredBefore(DateTime.now().subtract(const Duration(days: 90)))` in `main()` before `restoreMostRecent()`, catching failures so startup continues. Verify by running the app against a seeded test database on `<dev-box>` and observing that expired rows are gone and the app opens.

## 4. History drawer UI

- [x] 4.1 Render the grouped list in `_HistoryDrawer` with `Today`, `Yesterday`, `This week`, and `Older` headers. Verify with widget tests in `test/chat_screen_test.dart` covering the data state.
- [x] 4.2 Keep loading (`Loading...`), empty (`No conversations yet.`), and error (`History unavailable.`) states unchanged. Verify with widget tests in the same file.
- [x] 4.3 Add header semantics and verify contrast in light and dark themes. Verify with widget tests and an on-device look on `<dev-box>` (or `<device>` as fallback).

## 5. Changelog

- [x] 5.1 Add a user-facing changelog entry for grouped history and 90-day expiry. Verify the entry reads as user-facing prose and names both behaviors.

## Workflow follow-up

- Archive the change after review and validation.
