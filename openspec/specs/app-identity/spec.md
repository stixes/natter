# app-identity Specification

## Purpose

Defines how Natter presents itself: the Android launcher icon and the in-app brand mark on the chat screen, including their theming and accessibility expectations.

## Requirements

### Requirement: Natter mark
Natter SHALL have one brand mark: a speech bubble with a face (two eyes, blush cheeks, and a small open mouth). The launcher icon and the in-app mark MUST depict the same design. The mark MUST stay recognisable at 24 dp and as a single-colour silhouette.

#### Scenario: Same design on launcher and chat screen
- **WHEN** the user compares the home-screen icon with the mark in the chat screen's app bar
- **THEN** both show the same speech bubble with a face

#### Scenario: Readable at small size
- **WHEN** the mark is rendered at 24 dp
- **THEN** the bubble outline, both eyes, and the mouth remain distinguishable

### Requirement: Adaptive launcher icon
On Android 8.0 and later the app SHALL provide an adaptive launcher icon with separate background and foreground layers, keeping the face within the adaptive-icon safe zone so no launcher mask crops it.

#### Scenario: Circle and squircle masks
- **WHEN** the launcher shapes the icon as a circle or a rounded square
- **THEN** both eyes and the mouth are fully visible and the bubble is not clipped

### Requirement: Themed launcher icon
On Android 13 and later the app SHALL provide a monochrome icon layer, so that with themed icons enabled the launcher shows the mark tinted to the system palette rather than a generic or blank icon.

#### Scenario: Themed icons enabled
- **WHEN** the user turns on themed icons on Android 13 or later
- **THEN** Natter's icon appears as a tinted silhouette of the speech bubble with its face cut out

### Requirement: Legacy launcher icon
On Android versions before 8.0 that the app supports, the app SHALL show a bitmap launcher icon of the mark at every standard screen density instead of the stock Flutter icon.

#### Scenario: Pre-adaptive device
- **WHEN** Natter is installed on Android 6.0 to 7.1
- **THEN** the launcher shows the Natter mark, not the Flutter logo

### Requirement: Mark in the chat screen title
The chat screen's app bar SHALL show the mark immediately before the "Natter" title. The leading History control MUST remain unchanged and the mark MUST NOT be a tap target. Per openspec/design-ux-guidelines.md the mark is decorative: screen readers MUST announce the title once and MUST NOT announce the mark separately.

#### Scenario: Title row with an empty conversation
- **WHEN** the chat screen opens with no messages
- **THEN** the app bar shows the History control, then the mark followed by "Natter"

#### Scenario: Title row while streaming or after an error
- **WHEN** a reply is streaming, has been cancelled, or has failed with an error banner
- **THEN** the mark and title are shown unchanged and the mark does not animate or change state

#### Scenario: Screen reader
- **WHEN** a screen-reader user moves focus across the app bar
- **THEN** they hear the History control, the title "Natter" once, and the Endpoint settings control, with no separate announcement for the mark

#### Scenario: Large text
- **WHEN** Android font scaling is set to its largest value
- **THEN** the mark and the title fit in the app bar without clipping or overlapping the actions

### Requirement: Mark follows the app theme
The in-app mark SHALL take its colours from the active colour scheme so it meets the guidelines' contrast expectations in both themes, and MUST switch with the theme without restarting the app.

#### Scenario: Dark theme
- **WHEN** the system switches between light and dark mode while the chat screen is open
- **THEN** the mark repaints in the new theme's colours and its face stays distinguishable from the bubble
