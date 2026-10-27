# Design

## Context

See proposal.md - Why. The relevant current state:

- The launcher icon is Flutter's stock `ic_launcher.png` at five densities
  (48 to 192 px). There is no `mipmap-anydpi-v26/`, so no adaptive or themed icon.
- `minSdk = 23` (android/app/build.gradle.kts), so Android 6.0 to 7.1 still need bitmap
  icons; adaptive icons need API 26 and the monochrome layer is read from API 33.
- `ChatScreen`'s `AppBar` has `title: const Text('Natter')`. The `Scaffold` has a
  `drawer`, so Flutter supplies the leading hamburger that opens History; actions hold the
  Endpoint settings button.
- `NatterApp` themes from `ColorScheme.fromSeed(0xFF6750A4)` in light and dark. Widgets
  already take colours from the scheme (`errorContainer`, `tertiaryContainer`).
- `pubspec.yaml` declares no assets and no image or icon package. The devcontainer has
  the Flutter SDK but no rasteriser (no Inkscape, rsvg, or ImageMagick).

## Goals / Non-Goals

**Goals:**

- One geometry for the mark, used by both the in-app widget and the legacy PNGs, so the
  two cannot drift; the Android vector layers are the only hand transcription.
- No new dependency and no new devcontainer tool.
- The in-app mark is theme-aware and decorative to accessibility services.

**Non-Goals:**

- No asset pipeline or generator for future artwork; the render script handles exactly
  the launcher PNGs.
- No `ic_launcher_round` variant: the manifest does not reference one, and Android 7.1
  round-icon launchers fall back to `ic_launcher`.
- No golden-image tests; the repo has none, and an on-device look covers the visual check.

## Decisions

**The mark is drawn in code on a 108-unit grid.**
Shapes are primitives on the adaptive-icon canvas (108 x 108 units, safe zone a circle of
radius 33 centred at 54,54): a rounded-rectangle bubble with a short tail at its lower
left, the whole bubble rotated about -8 degrees for the quirky tilt; two round eyes, one a
touch larger than the other; two soft oval blush cheeks; and a small rounded "o" mouth
slightly off-centre, as if mid-word. Everything except the bubble's outer edge sits inside
the safe zone. The coordinates live in one constants block in `lib/ui/natter_mark.dart`,
and the painter scales the grid to whatever size it is given.
Alternatives: an SVG master rendered with `flutter_svg` (a new dependency for one
picture), or a PNG asset in the app bar (fixed colours, so it cannot follow the dark
theme, and it adds the first `assets:` entry). Both rejected.

**One painter, colours passed in.**
`NatterMarkPainter` takes the geometry plus four colours: bubble, face (eyes and mouth),
blush, and an optional background. `NatterMark`, the widget, resolves them from the active
`ColorScheme`: bubble `primaryContainer`, face `onPrimaryContainer`, blush `tertiary` at
reduced opacity, and no background. The render script passes the fixed launcher palette
instead, so the in-app mark and the legacy PNGs are the same code path.

**Launcher palette comes from the seed's tonal palette.**
The launcher cannot read the Flutter theme, so it uses fixed colours from the 0xFF6750A4
seed: background `#6750A4` (primary 40), bubble `#EADDFF` (primary 90), face `#21005D`
(primary 10), blush `#EFB8C8` (tertiary 80). The light bubble on the saturated background
keeps the silhouette readable in both light and dark launchers. The values are recorded
beside the constants block and in `ic_launcher_background.xml`.

**Adaptive and themed layers are Android vector drawables.**
`mipmap-anydpi-v26/ic_launcher.xml` declares `<background>` (a colour resource),
`<foreground>` (`drawable/ic_launcher_foreground.xml`), and `<monochrome>`
(`drawable/ic_launcher_monochrome.xml`). The foreground transcribes the 108-unit grid
directly, since vector drawables use the same viewport; the tilt is a `<group
android:rotation>` about 54,54. The monochrome layer is the bubble silhouette with the
eyes and mouth cut out (even-odd fill) and no blush, so the system tint reads as a face.
Alternative: `flutter_launcher_icons` as a dev dependency; rejected because it needs a
raster master, adds a package, and still leaves the monochrome layer to hand-tune.

**Legacy PNGs are rendered by a dev-only Flutter test file.**
`tool/render_launcher_icons_test.dart` paints the launcher palette (rounded-square
background, mark scaled to the legacy 48 dp keyline) with `NatterMarkPainter` through
`PictureRecorder`, encodes PNG via `Image.toByteData`, and writes the five
`mipmap-*/ic_launcher.png` files. It lives in `tool/`, so the default `flutter test`
(which runs `test/`) never executes it; it runs only when invoked by path. The generated
PNGs are committed, like Drift's generated code. Alternative: add a rasteriser to the
devcontainer image; rejected as a heavier change than one script.

**App bar title is a row, the mark excluded from semantics.**
`title:` becomes a `Row(mainAxisSize: MainAxisSize.min)` of `ExcludeSemantics(child:
NatterMark(size: 24))`, an 8 dp gap, and `Flexible(child: Text('Natter'))`. The leading
hamburger and the actions are untouched. The mark is not wrapped in any gesture detector.

## UX and interaction

Per `openspec/design-ux-guidelines.md`:

- **States**: the mark is static and identical in empty, loading, streaming, error,
  offline, cancel, and retry states; none of those states changes. The launcher icon has
  no states.
- **Motion**: none. The mark does not animate, so reduced-motion settings need nothing.
- **Accessibility**: the mark is decorative and excluded from semantics; the title "Natter"
  is announced once. It adds no touch target, so the 48 dp rule does not apply to it. At
  the largest font scale the mark stays 24 dp and the title text may ellipsise before it
  overlaps the actions; "Natter" is short enough that this is a guard, not an expected
  path. Recognition does not rely on colour alone: the face is a shape cut-out in the
  monochrome icon.
- **Copy**: no copy changes; the title stays "Natter".
- **Dark mode**: the in-app mark uses scheme tokens only, no hard-coded colours, and is
  checked on the emulator in both themes. The launcher palette is fixed and is checked on
  a light and a dark wallpaper.

## Risks / Trade-offs

- [The vector drawables are a hand transcription of the Dart geometry and can drift] →
  The constants block in `natter_mark.dart` names every coordinate the XML uses, and the
  on-device task puts the launcher icon and the app bar mark side by side.
- [`onPrimaryContainer` eyes on a `primaryContainer` bubble might read faint at 24 dp] →
  Both are the scheme's designed container pair, which Material 3 tunes for text
  contrast; the on-device look checks it in both themes.
- [Blush in `tertiary` at reduced opacity could fall below 3:1 against the bubble] → Blush
  is decoration, not identity: the spec requires eyes and mouth to be distinguishable, not
  the cheeks.
- [Test-renderer PNG output differs slightly between Flutter versions] → The PNGs are
  committed artefacts; regenerating them is a deliberate step, not part of CI.

## Migration Plan

Ship in a normal build. Launchers cache icons, so an existing install may show the old
icon until the launcher refreshes; reinstalling or restarting the launcher clears it.
Rollback is reverting the commit, which restores the stock PNGs.
