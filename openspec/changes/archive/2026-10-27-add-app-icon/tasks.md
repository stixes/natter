# Tasks

No task touches the network path, so no live-endpoint round or `validation.md` is owed;
the on-device looks below are recorded in the task notes instead.

## 1. The mark in code

- [x] 1.1 Create `lib/ui/natter_mark.dart` with the 108-unit geometry constants block (bubble rect, corner radius, tail, tilt, eyes, blush, mouth, plus the launcher palette hex values) and `NatterMarkPainter`, which takes bubble, face, blush, and optional background colours and scales the grid to its size; verify a unit test in `test/natter_mark_test.dart` that the eye and mouth centres fall inside the safe-zone circle (radius 33 about 54,54) and that `shouldRepaint` is true only when a colour changes.
- [x] 1.2 Add the `NatterMark` widget that resolves `primaryContainer`, `onPrimaryContainer`, and reduced-opacity `tertiary` from `Theme.of(context).colorScheme` and paints at a given size (default 24); follow the existing pattern of reading scheme tokens in `_ErrorBanner`. Verify a widget test in `test/natter_mark_test.dart` pumps it under the light and the dark `ColorScheme.fromSeed(0xFF6750A4)` and asserts the painter's colours equal each scheme's tokens.

## 2. Chat screen title row

- [x] 2.1 In `lib/ui/chat_screen.dart`, replace `title: const Text('Natter')` with a `Row(mainAxisSize: MainAxisSize.min)` of `ExcludeSemantics(NatterMark(size: 24))`, an 8 dp gap, and `Flexible(Text('Natter', overflow: TextOverflow.ellipsis))`, leaving the leading hamburger and actions untouched. States implemented: the title row is identical in empty, streaming, cancelled, and error states. Verify new cases in `test/chat_screen_test.dart`: the `AppBar` contains one `NatterMark` before the title text in the empty state and while a reply streams; `find.bySemanticsLabel('Natter')` finds exactly one node; the mark has no `GestureDetector`/`InkWell` ancestor below the `AppBar`; and the `Scaffold` still opens the drawer from the leading button.
- [x] 2.2 Add a large-text case to `test/chat_screen_test.dart` pumping with `MediaQuery(textScaler: TextScaler.linear(2.0))` on a 360 dp-wide surface; verify no overflow exception is reported and the Endpoint action remains hittable.
- [x] 2.3 Run `flutter analyze && flutter test` in the devcontainer; verify both pass.
- [x] 2.4 On the emulator on `<dev-box>` (or `<device>` as a fallback), open the chat screen in light then dark mode, and with TalkBack swipe across the app bar; verify the mark repaints on theme switch with eyes and mouth readable, and TalkBack reads the menu control, "Natter" once, and "Endpoint". Check against `openspec/design-ux-guidelines.md` and note any exception in this task.
  - Done on the `<dev-box>` emulator (API 36). Switching night mode with the chat screen open repainted the mark in the dark scheme with no restart; eyes and mouth read in both themes.
  - Exception: TalkBack is not installed on the Google-APIs emulator image, so the accessibility tree was read with `uiautomator dump` instead: "Open navigation menu", then one "Natter" node whose bounds span the mark and the title, with nothing separate for the mark. The Endpoint button is exposed as a Flutter tooltip, which `uiautomator` does not dump; that is unchanged by this change and covered by the widget test's `find.byTooltip('Endpoint')`.
  - Guideline note: in the light theme the `primaryContainer` bubble sits close to the app bar surface, so the bubble edge is faint at 24 dp while the face stays clear. Kept as designed (Material's container pair); a bolder light-theme bubble would be a small follow-up if it reads too pale.

## 3. Launcher icon

- [x] 3.1 Add `android/app/src/main/res/values/ic_launcher_background.xml` (colour `#6750A4`), `drawable/ic_launcher_foreground.xml` transcribing the 108-unit geometry with a rotation group about 54,54, `drawable/ic_launcher_monochrome.xml` (bubble silhouette, eyes and mouth cut out with even-odd fill, no blush), and `mipmap-anydpi-v26/ic_launcher.xml` declaring background, foreground, and monochrome; verify `flutter build apk --debug` succeeds in the devcontainer and each XML coordinate matches a named constant in `natter_mark.dart`.
- [x] 3.2 Write `tool/render_launcher_icons_test.dart`, which uses `NatterMarkPainter` with the launcher palette and a rounded-square background to write `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` at 48/72/96/144/192 px; run it with `flutter test tool/render_launcher_icons_test.dart` and verify `file android/app/src/main/res/mipmap-*/ic_launcher.png` reports the five sizes and plain `flutter test` does not run the script.
- [x] 3.3 Install the debug build on the emulator on `<dev-box>` and verify on the home screen and app drawer: the mark appears under a circle and a rounded-square icon shape with nothing clipped; with themed icons on (Android 13+) the tinted silhouette shows the face; the icon reads on a light and a dark wallpaper; and it matches the app bar mark side by side. If an API 23 to 25 image is available, check the legacy PNG there too, otherwise inspect the xxxhdpi PNG on the host and say so in this task.
  - Done on the `<dev-box>` emulator (API 36, Pixel launcher). Circle mask in the light app drawer: face and tail fully visible. Themed icons on, home screen on the dark default wallpaper: the tinted silhouette shows both eyes and the mouth cut out. The design matches the app bar mark. Themed icons were switched back off afterwards.
  - Exception: this launcher build offers no icon-shape option, so the rounded-square mask was not seen. Every adaptive mask contains the circle mask, and the circle mask clipped nothing, so a rounded square cannot clip more; the safe-zone unit test covers the face.
  - No API 23 to 25 image is available; the xxxhdpi `ic_launcher.png` was inspected on the host instead (rounded purple square, the mark centred and uncropped).

## 4. Docs

- [x] 4.1 Add a `## add-app-icon` entry to `CHANGELOG.md` in user-facing words (Natter has its own icon on the home screen and beside its name, and it follows themed icons on newer Android); verify the entry sits at the top and contains no commit-speak or host names.

## Workflow follow-up

- Run the publishable scan on the commit (placeholders only, no hostnames or devices).
- `openspec validate add-app-icon --strict`, then archive so `openspec/specs/app-identity/` is created.
- Separate follow-up worth proposing: correct the manifest's lowercase `android:label="natter"`.
