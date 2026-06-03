# Retired Phase 1 Scope

This document is retired.

It described the old prototype phase based on `/usr/sbin/screencapture`, a separate editor window, deferred global shortcuts, and stale preferences. Those decisions no longer match the project direction.

Do not use this file to guide new work.

Use these instead:

- [../NEW_PRD.md](../NEW_PRD.md)
- [../tech-designs/tahoe-native-region-capture-alignment.md](../tech-designs/tahoe-native-region-capture-alignment.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)

## Replacement Scope

MVP now means:

- macOS Tahoe 26 only.
- Personal-use app.
- Region capture only.
- ScreenCaptureKit-first capture.
- App-owned AppKit overlay.
- Mouse-up immediately enters annotation mode.
- Lightshot-style toolbar after region selection.
- Toolbar tools: arrow, text, rectangle, draw, color, undo, stroke size, highlight, copy, save, close.
- Copy and Save are explicit separate actions.
- Copy/Save close on success.
- `Esc` cancels.
- No `Enter` default action.
- No blur/redaction tool.
- No window/full-screen capture.
- No public distribution, sandboxing, telemetry, or App Store work.

## Historical Notes

The following old Phase 1 decisions are superseded:

- `screencapture` as MVP capture path.
- Separate floating editor window as the annotation surface.
- Deferring global shortcut until after annotation core.
- Keeping `copyAfterSave`.
- Including ellipse as a core tool.
- Excluding overlay-first toolbar behavior.
- Treating the current scaffold QA checklist as MVP acceptance.
