# Save Annotated Region PNG

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Route Save through the same flattening pipeline as Copy so annotated captures can be written as PNG files from the overlay. Copy and Save must remain explicit, separate actions.

## Acceptance criteria

- [x] Save flattens the captured region plus visible annotations into PNG data.
- [x] `Cmd+S` saves the annotated PNG and closes on success.
- [x] Toolbar Save saves the annotated PNG and closes on success.
- [x] Saving does not copy to the pasteboard.
- [x] Saved output matches copied output for the same annotation state.
- [x] Save failure leaves the overlay open enough for retry or cancel.

## Blocked by

- [06-save-raw-selected-region-png.md](06-save-raw-selected-region-png.md)
- [07-copy-annotated-rectangle-from-overlay.md](07-copy-annotated-rectangle-from-overlay.md)

## Comments

- Save already routes through the same rendered PNG path as Copy in `RegionCaptureOverlayController`.
- Manual QA confirmed annotated Save works.
