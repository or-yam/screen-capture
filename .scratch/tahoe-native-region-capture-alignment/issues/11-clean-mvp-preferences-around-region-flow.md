# Clean MVP Preferences Around Region Flow

Status: needs-triage
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Remove stale prototype preferences from the active settings surface and wire the remaining MVP defaults into region capture, annotation, and save behavior.

## Acceptance criteria

- [ ] Settings no longer expose `defaultAction`, `copyAfterSave`, or `showFloatingToolbar`.
- [ ] Settings keep or add save folder, default color, and default stroke size.
- [ ] New region sessions use the configured default color and stroke size for annotation tools.
- [ ] Save uses the configured/default save folder.
- [ ] Copy and Save remain explicit actions; no preference auto-copies after save.
- [ ] Existing obsolete stored defaults do not break app launch or region capture.

## Blocked by

- [08-add-draw-highlight-color-and-stroke-controls.md](08-add-draw-highlight-color-and-stroke-controls.md)
- [10-save-annotated-region-png.md](10-save-annotated-region-png.md)

## Comments

