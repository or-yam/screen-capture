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

## Before You Start

This repo is an early scaffold, not a finished Lightshot-style app yet.

Important context before working on the code:

- Develop and test on macOS only. The app uses AppKit, SwiftUI, and `/usr/sbin/screencapture`.
- Run `swift build` first and fix compiler errors before adding features.
- The capture path intentionally starts with `/usr/sbin/screencapture`, not ScreenCaptureKit.
- Menu-bar capture is the current entry point.
- `GlobalShortcutManager.swift` is only stubbed; the global shortcut is not implemented yet.
- Annotation rendering/modeling is scaffolded, but drag-to-draw, selection, move/resize, delete, undo/redo, and real blur are not complete yet.
- Running with `swift run` gives a development executable, not a polished `.app` bundle.
- The Swift Package layout may not be the final app structure. A real Xcode app target will likely be useful for Info.plist, entitlements, signing, permissions, app icon, notarization, and packaging.
- If capture fails, check macOS Screen Recording permissions first.

Recommended first vertical slice:

1. Make `swift build` pass.
2. Run the menu-bar app locally.
3. Confirm capture opens the editor.
4. Confirm copy and save work.
5. Only then add annotation interactions or global shortcuts.

## Build And Run Locally

This is a native macOS Swift app. If you usually work in TypeScript, the closest mental model is:

- `Package.swift` is like `package.json` for Swift Package Manager.
- `swift build` is like `npm run build`.
- `swift run ScreenCaptureAll` is like `npm start` for this executable target.
- Xcode is optional for this scaffold, but useful for debugging and later packaging as a real `.app` bundle.

### Prerequisites

Install Xcode from the Mac App Store, or install only the command line tools:

```bash
xcode-select --install
```

Verify Swift is available:

```bash
swift --version
```

### Build

From the repo root:

```bash
swift build
```

Build outputs go into `.build/`, similar to `node_modules` or `dist` style generated output. This folder is gitignored.

### Run

```bash
swift run ScreenCaptureAll
```

The app runs as a menu-bar utility, so you should see a small camera icon in the macOS menu bar instead of a Dock icon.

### Stop The App

Use the menu-bar icon and choose `Quit`.

If needed, stop it from Terminal with `Control-C` in the `swift run` process.

## Local QA Checklist

Run this on macOS, not Linux. The app uses AppKit, SwiftUI, and `/usr/sbin/screencapture`, which are macOS-only.

1. Run `swift build` and confirm it completes without compiler errors.
2. Run `swift run ScreenCaptureAll`.
3. Confirm the camera icon appears in the menu bar.
4. Choose `Capture Area` from the menu.
5. Drag-select part of the screen using the native macOS screenshot selector.
6. Confirm the floating editor opens with the captured image.
7. Click `Copy`, then paste into Preview, Messages, Slack, or another image-capable app.
8. Click `Save`, then confirm a PNG appears in `~/Pictures/Screenshots`.
9. Open `Preferences` and change the save folder.
10. Save another screenshot and confirm it lands in the new folder.
11. Test `Capture Window` and `Capture Full Screen` from the menu.
12. Choose `Quit` and confirm the menu-bar icon disappears.

## macOS Permissions

The first capture may trigger macOS privacy prompts.

If capture does not work, check:

- `System Settings` -> `Privacy & Security` -> `Screen Recording`
- `System Settings` -> `Privacy & Security` -> `Accessibility`

For this MVP, capture is delegated to the native `screencapture` tool, so permission behavior may look like the built-in macOS screenshot flow.

## Current Limitations

- Global shortcut registration is scaffolded but not implemented yet.
- Annotation drawing interactions are not complete yet.
- Running with `swift run` does not produce a polished `.app` bundle.
- Packaging, signing, notarization, and auto-update are not set up yet.

For a polished app bundle, create an Xcode macOS app target from this package or migrate the sources into an Xcode project.
