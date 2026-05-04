# Architecture

## Product Principle

The app is output-first, not editor-first.

Capture, mark, copy/save, disappear. Avoid account systems, upload flows, asset libraries, or a heavy design-tool surface area.

## Components

- `MenuBarController`: owns the menu-bar icon and app menu actions.
- `GlobalShortcutManager`: reserved integration point for Option-Shift-4.
- `CaptureCoordinator`: orchestrates capture and opens the editor.
- `ScreencaptureService`: wraps `/usr/sbin/screencapture` for MVP-native capture.
- `ScreenshotEditorWindowController`: owns the floating AppKit editor panel.
- `ScreenshotEditorView`: SwiftUI editor shell and toolbar.
- `AnnotationModel`: vector annotation state.
- `Renderer`: combines base screenshot and annotation layers into final PNG data.
- `ClipboardService`: writes PNG data to `NSPasteboard`.
- `SaveService`: writes PNG data to the configured screenshots folder.
- `PreferencesStore`: stores local preferences in `UserDefaults`.

## Capture Strategy

MVP uses `screencapture` because it gives native-feeling capture with very little custom machinery.

Area capture:

```bash
/usr/sbin/screencapture -i /tmp/capture.png
```

Window capture:

```bash
/usr/sbin/screencapture -i -w /tmp/capture.png
```

Full-screen capture:

```bash
/usr/sbin/screencapture /tmp/capture.png
```

ScreenCaptureKit should only replace this once a custom overlay becomes necessary.

## Annotation Strategy

Annotations stay vector-based until export.

This preserves undo, selection, recoloring, resizing, and clean rendering. The bitmap is only modified when exporting final PNG data.

## MVP Roadmap

1. Finish annotation interactions: drag-to-draw arrow, ellipse, rectangle, pen, and blur regions.
2. Add selected annotation movement, resizing, deletion, and undo/redo.
3. Add global shortcut registration for Option-Shift-4.
4. Add save-and-reveal, recent screenshots, and numbered markers.
5. Consider custom overlay and ScreenCaptureKit only if system capture becomes too limiting.
