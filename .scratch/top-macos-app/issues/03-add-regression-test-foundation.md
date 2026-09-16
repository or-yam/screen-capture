# Add Regression Test Foundation

Status: ready-for-agent
Type: AFK

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Create the first automated regression test foundation around stable non-overlay seams so future app-shell, preferences, geometry, annotation, and export changes are safer.

## Acceptance criteria

- [ ] Add a test target or equivalent test setup that can run in local development.
- [ ] Cover preferences defaults and persistence behavior.
- [ ] Cover region geometry/scaling logic where it is separable from AppKit overlay windows.
- [ ] Cover annotation state transitions and undo behavior where practical.
- [ ] Document what remains manual QA-only, especially full overlay interaction.

## Recommended skills

- `tdd` for the red-green-refactor workflow and test seam selection.
- `improve-codebase-architecture` if current types are too coupled to test without awkward scaffolding.
- `diagnose` only if test setup exposes build/toolchain failures.

## Before picking

Create a brief test plan before writing tests. Identify the first three seams to cover and avoid broad refactors unless a seam is genuinely untestable.

## Blocked by

None - can start immediately, but coordinate with the config bug fix if it changes settings seams.

## Test Plan

### Test stack

- Use Swift Testing for model/service seams that do not need app launch.
- Use XCTest UI tests for packaged-app smoke tests through `XCUIApplication` and Accessibility where possible.
- Keep full overlay drawing/click precision in a manual QA matrix until a stable native automation harness exists.

### First automated seams

1. Preferences persistence.
   - Defaults: save folder, color, stroke width, save confirmation, menu bar icon visibility.
   - Writes survive a fresh `PreferencesStore` using an injected `UserDefaults` suite.
   - Invalid save-folder state is reported without modal UI.

2. Region geometry.
   - Selection normalization from drag direction.
   - Display-space to image-space conversion for Retina scale.
   - Multi-display and negative-coordinate display arrangements.
   - Move/resize clamps and recrops from frozen snapshots.

3. Annotation state.
   - Tool begin/update/commit for rectangle, arrow, draw, highlight, text.
   - Undo removes draft first, then latest committed annotation.
   - Annotations remain aligned when selected region moves.

4. Export.
   - Renderer produces PNG data for representative annotations.
   - SaveService writes timestamped PNG to an injected temp folder.
   - ClipboardService remains adapter-tested only if pasteboard isolation is reliable.

### E2E coverage

1. App-shell E2E.
   - Launch packaged `ScreenCaptureAll.app`.
   - Verify accessory app starts, status item exists, Preferences opens, repeated Preferences focuses existing window.
   - Toggle settings and confirm persistence after relaunch.

2. Permission E2E.
   - Fresh app identity first launch.
   - Screen Recording denied path shows recovery UI.
   - Screen Recording allowed path can enter capture.

3. Capture-flow E2E.
   - Use an automation-only mode or launch argument to inject deterministic frozen display snapshots.
   - Drive region selection, select each annotation tool, copy/save, and inspect output PNG dimensions/content.
   - Do not depend on live desktop pixels for CI; live ScreenCaptureKit remains local manual QA.

4. Release E2E.
   - Run `Scripts/package_app.sh`.
   - Verify `Info.plist` bundle ID, `LSMinimumSystemVersion=26.0`, `LSUIElement=true`.
   - Verify ad-hoc code signature.
   - Unzip release artifact and launch the unzipped app.

### Required app changes to support E2E

- Add dependency injection for frozen snapshots and output adapters.
- Add launch arguments for UI tests, for example `--ui-testing`, `--mock-snapshots`, `--save-folder <path>`, and `--reset-preferences`.
- Split pure geometry/annotation state out of `RegionCaptureOverlayController.swift` so tests do not need AppKit windows.
- Add stable accessibility identifiers to Preferences controls, menu-triggered windows, overlay buttons, and alerts.
