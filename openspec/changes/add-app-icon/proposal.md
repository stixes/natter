# Proposal

## Why

Natter still ships Flutter's stock launcher icon, and the chat screen's app bar says
"Natter" in plain text. The polish bar in AGENTS.md is the ChatGPT app, and an app that
looks like a template on the home screen reads as unfinished before the first message is
sent. A small, recognisable mark, shown both on the launcher and beside the title, gives
Natter a face without adding a single control.

## What Changes

- Add the Natter mark: a chunky, slightly tilted speech bubble with a face (two dot eyes,
  blush cheeks, and a small open "mid-sentence" mouth). Cute and a little quirky, but
  simple enough to read at 24 dp and as a single-colour silhouette.
- Replace the stock Android launcher icon with the mark: an adaptive icon (background,
  foreground, and a monochrome layer for Android 13+ themed icons) plus legacy PNGs for
  Android 6.0 to 7.1, which the app's `minSdk = 23` still supports.
- Show the mark in the chat screen's app bar immediately before the "Natter" title. The
  History hamburger stays as the leading control; how History opens does not change.
- The in-app mark takes its colours from the active Material 3 colour scheme, so it reads
  in light and dark themes without hard-coded colours.

Out of scope: a splash screen or launch-background artwork, the Settings screen's app bar,
the History drawer header, any animation of the mark, a Play Store feature graphic, and
correcting the manifest's lowercase `android:label="natter"` (a separate one-line change).
No product non-goal is touched: the change adds no network call, no telemetry, and no
new screen.

## User-facing surface and UX impact

Two surfaces change, both visual only (per `openspec/design-ux-guidelines.md`):

- **Android launcher**: the home-screen and app-drawer icon, including themed-icon mode
  on Android 13+.
- **Chat screen app bar**: the title row gains a small decorative mark before "Natter".
  No interaction state (empty, loading, streaming, error, offline, cancel, retry) changes,
  no new tap target is added, and screen readers keep announcing the title once.

## Capabilities

### New Capabilities
- `app-identity`: how Natter presents itself: the launcher icon (adaptive, themed, and
  legacy forms) and the in-app brand mark on the chat screen, including its theming and
  accessibility expectations.

### Modified Capabilities
<!-- none: chat-streaming's requirements cover request and stream behaviour, not the
     app bar's look; the title row is owned by app-identity. -->

## Impact

- `lib/ui/natter_mark.dart` (new): the mark as a theme-aware `CustomPainter` widget, the
  single source of the in-app artwork.
- `lib/ui/chat_screen.dart`: the `AppBar` title becomes a row of the mark and "Natter".
- `android/app/src/main/res/`: new `mipmap-anydpi-v26/ic_launcher.xml`, vector drawables
  for the adaptive foreground, background, and monochrome layers, and regenerated legacy
  `ic_launcher.png` files at all five densities.
- `tool/` (new, dev-only): a script that rasterises the mark into the legacy PNGs using the
  Flutter test renderer, so no image tool is added to the devcontainer.
- Tests: a widget test for the app bar title row and its semantics; a check that the mark
  paints in both themes.
- No new dependency, no new permission, no new network destination. No `pubspec.yaml`
  asset entry, since the in-app mark is drawn in code.
- Changelog: one user-facing line about Natter's new icon.
