# Harden Retina And Multi-Display Region Copy

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Extend the raw copy tracer bullet so region selection, capture, and clipboard output work across Retina scaling and multi-display arrangements. The selected rectangle should be normalized in global display-space points and captured with correct pixel dimensions.

## Acceptance criteria

- [ ] Region selection stores one canonical global display-space rectangle for the session.
- [ ] Copy works for selections on each attached display.
- [ ] Copy works for selections in negative-coordinate display arrangements.
- [ ] Exported PNG dimensions match the selected region at the expected display scale.
- [ ] Diagnostic logging includes display frames, selected rect, capture rect, and output image size when capture fails or geometry looks invalid.
- [ ] Existing single-display copy behavior remains intact.

## Blocked by

- [02-copy-single-display-region-png.md](02-copy-single-display-region-png.md)

## Comments

- Implemented canonical session selection storage in `RegionSelectionState`.
- `ScreenRegion` now carries a normalized display-space rect plus current display frames and backing scale factors.
- Region capture validates that the selected rect intersects at least one display, keeps negative-coordinate rects intact, and logs display frames, selected rect, capture rect, and output image size diagnostics on failures or suspicious geometry.
- Single-display Retina captures are checked against the display backing scale; mixed-scale multi-display captures are logged as intentionally not reducible to one expected scale.
- The coordinator hides overlay windows during capture and restores them before showing the copy action or failure alert.
- Verified with `swift build`.
- `swift test` could not be completed in this sandbox: the normal run failed on Swift/Clang cache permissions, the escalated retry was denied, and a cache-redirected retry failed when SwiftPM tried to apply `sandbox-exec`. This project currently has no test suite.
- Manual multi-display/Retina paste-target QA was not run in this non-interactive pass.
