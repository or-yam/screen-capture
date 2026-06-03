# Screen Capture All

A personal macOS Tahoe screenshot utility inspired by Lightshot.

`NEW_PRD.md` is the product source of truth. The current Swift code is an early prototype scaffold, not the target MVP architecture.

## Target Flow

```text
global hotkey -> drag region -> annotate in place -> copy/save -> disappear
```

The MVP is region capture only. Window capture, full-screen capture, history, upload, OCR, public distribution, sandboxing, telemetry, and App Store concerns are out of scope.

## Current Direction

The app is being realigned around:

- macOS Tahoe 26 only.
- Native macOS APIs wherever practical.
- ScreenCaptureKit-first region capture.
- AppKit overlay windows for selection, annotation, keyboard handling, and toolbar behavior.
- `NSPasteboard` PNG copy.
- PNG save to a local folder.
- A compact Lightshot-style toolbar shown only after region selection.

MVP toolbar:

```text
Arrow | Text | Rectangle | Draw | Color | Undo | Stroke size | Highlight | Copy | Save | Close
```

## Current Scaffold Status

The checked-in app currently contains a prototype path:

- Menu bar app.
- `/usr/sbin/screencapture`-based area/window/full-screen capture.
- Separate floating editor window.
- Scaffolded annotation model and renderer.
- Clipboard and save services.
- Preferences for old behavior such as `defaultAction`, `copyAfterSave`, and `showFloatingToolbar`.

That prototype is useful for learning and salvageable pieces, but it is deprecated as product direction. New work should not extend the `screencapture` flow or the separate editor-window workflow.

Known scaffold gaps:

- `GlobalShortcutManager` is a stub.
- Capture is not ScreenCaptureKit-based.
- Selection is owned by macOS `screencapture`, not this app.
- Annotation happens in a separate editor window, not on the capture surface.
- Annotation identity is unstable in the current model.
- The code still exposes stale tools and settings that are not MVP scope.

## Planning Docs

Read these first:

- [NEW_PRD.md](NEW_PRD.md)
- [tech-designs/tahoe-native-region-capture-alignment.md](tech-designs/tahoe-native-region-capture-alignment.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

Retired context:

- [docs/PHASE1-SCOPE.md](docs/PHASE1-SCOPE.md)

## Build And Run Prototype

This is currently a Swift Package prototype.

```bash
swift build
swift run ScreenCaptureAll
```

The app runs as a menu bar utility.

This run path is for current scaffold validation only. A real `.app` bundle may be needed as the native overlay, permissions, and launch behavior mature.

## Local QA For Current Prototype

Use this only to check the existing scaffold:

1. Run `swift build`.
2. Run `swift run ScreenCaptureAll`.
3. Confirm the menu bar icon appears.
4. Use `Capture Area`.
5. Confirm the separate editor window opens.
6. Confirm `Copy` writes PNG data to the clipboard.
7. Confirm `Save` writes a PNG file.

Do not treat this checklist as MVP acceptance criteria.

## MVP Acceptance Direction

The actual MVP should satisfy:

1. Global shortcut starts region selection.
2. App-owned transparent overlay covers active displays.
3. Dragging selects a rectangular region.
4. Mouse-up immediately enters annotation mode.
5. Floating toolbar appears after selection.
6. Arrow, text, rectangle, draw, highlight, color, stroke size, and undo work.
7. `Cmd+C` or toolbar Copy copies final PNG and closes.
8. `Cmd+S` or toolbar Save saves final PNG and closes.
9. `Esc` cancels and closes.
10. Output is correct on Retina and multi-display setups.

## Permissions

Screen Recording permission is required for native screenshot capture.

Accessibility permission should be avoided unless the final global hotkey or event strategy proves it is required.
