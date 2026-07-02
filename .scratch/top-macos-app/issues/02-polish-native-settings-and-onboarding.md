# Polish Native Settings And Onboarding

Status: ready-for-human
Type: Implementation

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Improve the settings, permission, and first-run surfaces so the app feels like a native macOS utility rather than an MVP debug panel.

Use the Glaze/Raycast-style reference captured in [../ui-direction.md](../ui-direction.md): compact grouped rows, direct controls, icon-led secondary actions, and restrained copy.

## Acceptance criteria

- [x] Settings copy, layout, and controls are reviewed for native macOS fit.
- [x] Settings is grouped into `Output`, `Annotations`, and `Capture` sections.
- [x] Save folder row shows path, `Change...`, reveal/open-folder action, and inline validation.
- [x] Default annotation color is presented as compact swatches.
- [x] Stroke width uses a compact visual control or stepped control with the selected value visible.
- [x] Capture shortcut is displayed clearly, but shortcut recording is not implemented in this slice.
- [x] Screen Recording permission denial explains what happened and how to recover.
- [x] Save-folder failure states give a clear recovery action.
- [ ] Manual QA covers light/dark mode and repeated settings opens.

## Recommended skills

- `tech-design` if the settings/onboarding shape is still unclear.
- `web-design-guidelines` as a UI quality checklist, adapted critically for native macOS rather than followed as web-specific law.
- `honest-review` for a blunt UX review before implementation.

## Reference Decision

As of 2026-07-02, the direction is approved: Glaze/Raycast-inspired, compact utility UI, but still native SwiftUI/AppKit. Shortcut recording remains out of scope for this slice.

## Blocked by

- [01-fix-config-menu-entrypoint.md](01-fix-config-menu-entrypoint.md)

## Proposed design note

### Current critique

- `PreferencesView` is too bare for a releasable Mac utility. It exposes values, but it does not explain what affects new captures, whether the save folder is usable, or how to recover from permission/save failures.
- The fixed-size settings window is acceptable for a tiny utility, but the content should be grouped and readable as a native settings pane instead of a single debug-style form.
- The shortcut row is the right restraint for now. A configurable shortcut editor would add scope and regression risk before the app has tests.
- Permission recovery is currently handled only after failure. That is not enough for a daily-driver app because users can open settings specifically to understand why capture is broken.

### Approved implementation direction

- Keep a single settings window. Do not add tabs/sidebar until there are at least three real sections.
- Replace the flat form with three grouped sections:
  - `Output`: save folder path, Choose button, Reveal/Open button, and validation status.
  - `Annotations`: default color swatches and stroke width.
  - `Capture`: show the current global shortcut as read-only, plus Screen Recording permission status and recovery action.
- Use native SwiftUI controls: `Form`, `Section`, `LabeledContent`, `ColorPicker`, segmented `Picker`, and standard bordered buttons.
- It is acceptable to replace the full `ColorPicker` with swatches for the default colors used by the overlay, as long as the selected value is obvious.
- Show save-folder validation inline. If the folder is missing or inaccessible, present a warning row and offer `Choose...`.
- Add a Screen Recording permission status row with an `Open System Settings` action. Do not show modal alerts from settings for normal status.
- Keep `Cmd-Shift-A` as the capture shortcut for now. Show it clearly; do not build shortcut recording yet.
- Keep copy restrained and functional. No marketing text, no tutorial prose, no large hero/onboarding screen.
- Manual QA must cover opening Preferences repeatedly from the status menu, changing color/stroke/folder, light and dark mode, denied Screen Recording, and a missing/inaccessible save folder.

### Out of scope

- User-editable shortcut recording.
- First-run wizard.
- Launch-at-login.
- Auto-update, telemetry, cloud upload, account concepts.
- Replacing the menu-bar utility model with a Dock-first app.

### Implementation notes

- `PreferencesView` currently uses `Binding(get:set:)` for color conversion. That is tolerable in the current code, but if the view grows, move conversion into a small binding helper or store SwiftUI-friendly values to keep `body` readable.
- Do not use hardcoded warning colors. Use semantic system colors and SF Symbols where status needs an icon.
- Prefer inline validation over modal alerts for settings. Reserve modal alerts for capture/save failures that require immediate interruption.

## Comments

### 2026-07-02

Implemented settings polish in `Sources/PreferencesView.swift`.

- Replaced the flat settings form with grouped `Output`, `Annotations`, and `Capture` sections.
- Added save-folder path display, `Change...`, Finder reveal action, and inline missing/inaccessible validation.
- Replaced the default annotation `ColorPicker` with compact swatches matching the overlay palette.
- Kept stroke width compact with segmented widths and the selected `px` value visible.
- Kept shortcut display read-only as `Cmd Shift A`; no shortcut recording added.
- Added Screen Recording status with inline denial copy and `Open System Settings`.

Verification:

- `swift build` passes.

Manual QA caveat:

- Light/dark mode, repeated settings opens, denied Screen Recording, and missing/inaccessible folder GUI checks were not run in this agent pass.
