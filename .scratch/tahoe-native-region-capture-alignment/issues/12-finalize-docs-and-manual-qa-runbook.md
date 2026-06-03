# Finalize Docs And Manual QA Runbook

Status: needs-triage
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

After the native overlay flow exists, update the user-facing docs and manual QA checklist so they describe the actual Tahoe-native MVP behavior rather than the old prototype path.

## Acceptance criteria

- [ ] README describes the current native region capture, annotation, copy, and save flow accurately.
- [ ] Architecture docs match the implemented session, overlay, ScreenCaptureKit, annotation, and export boundaries.
- [ ] Legacy prototype docs are deleted or clearly marked as historical.
- [ ] Manual QA covers launch, menu capture, hotkey capture, single-display copy, multi-display copy, Retina dimensions, annotation copy, save, `Esc`, and permission denial.
- [ ] Docs do not advertise window capture, full-screen capture, auto-copy-after-save, or separate editor-window MVP behavior.

## Blocked by

- [04-start-region-copy-flow-from-global-hotkey.md](04-start-region-copy-flow-from-global-hotkey.md)
- [05-handle-screen-recording-denial-in-region-flow.md](05-handle-screen-recording-denial-in-region-flow.md)
- [09-add-arrow-and-text-annotation-copy.md](09-add-arrow-and-text-annotation-copy.md)
- [10-save-annotated-region-png.md](10-save-annotated-region-png.md)
- [11-clean-mvp-preferences-around-region-flow.md](11-clean-mvp-preferences-around-region-flow.md)

## Comments

