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

The checked-in Swift package is a migration scaffold, not the target MVP. New work should align it with the ScreenCaptureKit overlay flow described below and in the planning docs.

## Planning Docs

Read these first:

- [NEW_PRD.md](NEW_PRD.md)
- [tech-designs/tahoe-native-region-capture-alignment.md](tech-designs/tahoe-native-region-capture-alignment.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Build And Run

This is currently a Swift Package scaffold.

```bash
swift build
swift run ScreenCaptureAll
```

The app currently runs as a menu bar utility. A real `.app` bundle may be needed as the native overlay, permissions, and launch behavior mature.

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
