# Validation

## Automated checks

Run in the devcontainer against Flutter 3.29.3 / Dart 3.7.2.

- `flutter analyze` — no issues.
- `flutter test` — 153 tests pass.

Coverage added by this change:

- `test/history_grouping_test.dart` — each bucket boundary; the
  Yesterday-overlaps-previous-week case; empty list; equal timestamps stay
  newest first.
- `test/conversation_repository_test.dart` — `deleteExpiredBefore` removes
  expired conversations and their messages while newer rows survive; a
  deletion failure (forced by a `RAISE(ABORT)` trigger) rolls back inside the
  transaction and leaves the database readable with rows intact.
- `test/chat_screen_test.dart` — drawer renders `Today`, `Yesterday`,
  `This week`, and `Older` headers above the right conversations in visual
  order; header rows carry `Semantics(header: true)`; `Loading...`, empty,
  and error states unchanged.
- `test/history_header_contrast_test.dart` — header color
  (`onSurfaceVariant`) meets WCAG AA against the drawer surface
  (`surfaceContainerLow`) in light and dark themes.

## On-device round (tasks 3.1 and 4.3) — ran on the remote emulator

Ran 2026-10-26 on the always-on Android emulator on `<dev-box>` (Android 16,
API 36, device serial `<dev-box>:5555`), from the devcontainer's adb client
(`adb connect <dev-box>:5555`).

Delivery note: fat debug APK pushes over the remote adb link kept arriving
corrupted, so the round uses the split-per-ABI artifact
(`build/app/outputs/flutter-apk/app-x86_64-debug.apk`): `adb push` to
`/data/local/tmp`, compare md5 host-vs-device, then `pm install -r`.

Seeding: `build/natter_seed.sql` (throwaway fixture, deleted after the round)
was applied with `adb shell run-as dev.natter.app sqlite3` against
`/data/data/dev.natter.app/app_flutter/natter.sqlite`. Five conversations,
one message each, timestamped from the device clock (`adb shell date +%s`):
now (today), now-1d (yesterday), now-3d (this week; device day was Saturday),
now-30d, and now-95d (past the 90-day cutoff, so expired).

Steps and results:

1. Launched the app. On startup, the expired conversation and its message
   were deleted; the other four conversations and their messages were
   untouched, and the app opened normally. (An instrumented debug build of
   the startup path logged exactly one conversation removed; the final clean
   build was then reinstalled and a relaunch confirmed the expired row stays
   gone, startup logs are silent, and `restoreMostRecent()` still restored
   the newest conversation.)
2. Opened the history drawer and dumped the accessibility tree. Visual order:
   `Today` / Today chat / `Yesterday` / Yesterday chat / `This week` / This
   week chat / `Older` / Month old chat. All four section headers rendered
   with the right membership; a screenshot was pulled for the visual look
   (header color matches the contrast test's theme tokens).
3. Cleaned up: seeded rows deleted from the device database, pushed fixtures
   and staged APK removed from `/data/local/tmp`.

## Findings worth keeping

- Drift 2.29.0's INTEGER date-time codec round-trips `DateTime` as epoch
  **seconds**, not milliseconds. A hand-seeded SQL fixture using
  `millisecondsSinceEpoch` reads back as year +58781 and lands in the Older
  bucket. Seed fixtures must use epoch seconds.
- Two confusing intermediate reads during the round were environmental, not
  product: an older stale installed APK, and an emulator host reboot from a
  stale snapshot that wiped app data and rewound the device clock. Re-seeding
  relative to `adb shell date +%s` keeps a round self-consistent regardless
  of host clock skew.

## Debt

None. Every task's specified on-device and automated verification was
completed; nothing was descoped.
