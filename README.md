# Screen Capture All

A personal macOS screenshot utility inspired by Lightshot.

The app is currently a Swift Package menu-bar utility. It implements the native region-capture MVP flow:

```text
menu or Cmd-Shift-A -> frozen screen overlay -> drag region -> annotate in place -> copy/save -> disappear
```

The MVP is region capture only. Window capture, full-screen capture, history, upload, OCR, public distribution, sandboxing, telemetry, notarization, auto-update, and App Store concerns are out of scope.

## Current Behavior

- Launches as a menu-bar accessory app.
- Exposes `Capture Region`, `Open Screenshot Folder`, `Preferences`, and `Quit` from the status menu.
- Registers a hardcoded global shortcut: `Cmd-Shift-A`.
- Starts each capture session by taking frozen ScreenCaptureKit snapshots of active displays.
- Shows app-owned borderless AppKit overlay windows over active displays.
- Lets the user drag a rectangular region, then keeps that region anchored for annotation.
- Shows the annotation toolbar only after a valid region exists.
- Supports Arrow, Text, Rectangle, Draw, Highlight, Color, Stroke size, Undo, Copy, Save, and Close.
- Copies flattened annotated PNG data to `NSPasteboard`.
- Saves flattened annotated PNG files to the configured screenshot folder.
- Handles Screen Recording permission denial with a targeted alert and an Open System Settings action.

Current preferences:

- Default annotation color.
- Default stroke size.
- Save folder.
- Shortcut display only; the shortcut is not configurable yet.

Legacy prototype note: `ScreenshotEditorView`, `ScreenshotEditorWindowController`, and the old SwiftUI annotation model remain in the source tree as historical scaffold code. The current MVP region flow does not open or depend on the separate editor window.

## Planning Docs

Read these first:

- [NEW_PRD.md](NEW_PRD.md)
- [tech-designs/tahoe-native-region-capture-alignment.md](tech-designs/tahoe-native-region-capture-alignment.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Build And Run

This is currently a Swift Package app.

```bash
swift build
swift run ScreenCaptureAll
```

The app currently runs as a menu bar utility. A real `.app` bundle may be needed as the native overlay, permissions, and launch behavior mature.

The package currently declares `.macOS(.v13)` in `Package.swift`, while the capture implementation requires macOS 15.2+ at runtime because it uses `SCScreenshotManager.captureImage(in:)`. The broader product direction remains Tahoe-native, but the package manifest has not been raised to a Tahoe-specific spelling.

## MVP Acceptance Status

The current MVP is expected to satisfy:

1. Global shortcut starts region selection.
2. App-owned snapshot-backed overlay covers active displays.
3. Dragging selects a rectangular region.
4. Mouse-up immediately enters annotation mode.
5. Floating toolbar appears after selection.
6. Arrow, text, rectangle, draw, highlight, color, stroke size, and undo work.
7. `Cmd+C` or toolbar Copy copies final PNG and closes.
8. `Cmd+S` or toolbar Save saves final PNG and closes.
9. `Esc` cancels and closes.
10. Output is correct on Retina and multi-display setups.

The latest manual QA pass is recorded in [docs/CURRENT-QA-NOTES.md](docs/CURRENT-QA-NOTES.md).

## Permissions

Screen Recording permission is required for native screenshot capture.

Accessibility permission should be avoided unless the final global hotkey or event strategy proves it is required.
