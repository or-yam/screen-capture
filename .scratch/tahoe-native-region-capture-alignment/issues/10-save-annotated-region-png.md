# Save Annotated Region PNG

Status: needs-triage
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Route Save through the same flattening pipeline as Copy so annotated captures can be written as PNG files from the overlay. Copy and Save must remain explicit, separate actions.

## Acceptance criteria

- [ ] Save flattens the captured region plus visible annotations into PNG data.
- [ ] `Cmd+S` saves the annotated PNG and closes on success.
- [ ] Toolbar Save saves the annotated PNG and closes on success.
- [ ] Saving does not copy to the pasteboard.
- [ ] Saved output matches copied output for the same annotation state.
- [ ] Save failure leaves the overlay open enough for retry or cancel.

## Blocked by

- [06-save-raw-selected-region-png.md](06-save-raw-selected-region-png.md)
- [07-copy-annotated-rectangle-from-overlay.md](07-copy-annotated-rectangle-from-overlay.md)

## Comments

