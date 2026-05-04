# Screen Capture All

A tiny personal macOS screenshot utility inspired by Lightshot and the native Screenshot app.

Primary flow:

1. Trigger capture from the menu bar or global shortcut.
2. Select an area, window, or full screen.
3. Annotate the image in a lightweight floating editor.
4. Copy, save, or save-and-copy, then disappear.

## MVP Strategy

This project starts with the lowest-risk native path:

- SwiftUI for app shell and preferences
- AppKit for menu bar and floating editor panel
- `/usr/sbin/screencapture` for capture
- CoreGraphics/AppKit rendering for PNG export
- `NSPasteboard` for clipboard output
- `FileManager` and `UserDefaults` for local save behavior

## Current Scaffold

The app currently includes:

- Menu bar app with capture commands
- Interactive `screencapture -i` area/window capture and full-screen capture
- Floating editor window
- Vector annotation model
- PNG renderer
- Clipboard service
- Save service
- Preferences window for default action, copy-after-save, toolbar visibility, and save folder

The drawing interactions are intentionally not complete yet. The first implemented output path is capture -> preview/editor -> copy/save.

## Build

```bash
swift build
```

Run from source:

```bash
swift run ScreenCaptureAll
```

For a polished app bundle, create an Xcode macOS app target from this package or migrate the sources into an Xcode project.
