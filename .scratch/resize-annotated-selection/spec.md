# Resize annotated selections

Date: 2026-10-15
State: Implemented and verified; see `qa/README.md` for live evidence and limits.

## Goal

Allow selection-edge and corner resizing after annotations exist, without moving
or stretching annotations relative to the frozen screen content. Also make the
Move tool keep annotations anchored to that same content.

“Resize” changes the selected screen bounds, revealing or excluding frozen
content. It does not scale the captured image. No new Crop tool or replacement
selection behavior is included. Internally, producing the selected image still
uses the existing snapshot-cropping implementation.

## Confirmed decisions

- Resize after annotations using the existing handles and Move tool.
- Keep annotations anchored to frozen screen content during both resize and Move.
  This intentionally changes current Move behavior, which carries annotations
  with the selection.
- Clip annotations outside the selection in preview/export; retain their full
  geometry in session memory. Expanding or moving back reveals them again.
- Cmd-Z and the Undo button affect annotations only, never selection geometry.
  Hidden annotations remain in creation order and can be undone.
- Use a stable, session-wide annotation canvas, independent of selection bounds.
- Existing annotations retain their screen-space size if output density changes.
  Their exported pixel sizes adapt to the output density.

## Non-goals

- Replacement selection after annotations; retain its existing restriction.
- Scaling the image, annotation selection/editing, or moving individual marks.
- Resize/Move history, redo, or a general-purpose editing-history module.
- Changes to capture acquisition, permissions, shortcuts, preferences storage,
  save/clipboard delivery, signing, or unrelated UI.
- Persisting annotations beyond the capture session.

## Current implementation and risks

- `Sources/RegionCaptureOverlayController.swift` contains `RegionSelectionState`,
  `OverlayAnnotation`, the annotation input code, and selection interactions.
- `OverlayAnnotation` currently stores crop-relative image-pixel geometry.
- `canResizeRegion` and `canReselectRegion` both reject existing annotations;
  only the resizing restriction should be removed.
- `beginSelection` and `anchorSelection` clear annotations. Do not route annotated
  resize/Move through those methods.
- Resize/Move update screen bounds during dragging, then regenerate the selected
  image from frozen snapshots on release. Single-display output can align those
  bounds to source pixels; spanning output can change density.
- `Sources/Renderer.swift` shares drawing between preview and export, but currently
  maps annotations using the cropped image dimensions. Enabling handles alone
  would stretch annotations during resize and misalign them after release.
- `reset()` clears the session; starting a capture constructs fresh selection
  state. New canvas state must follow the same lifecycle.

## Architecture

### Stable canvas

Use an immutable, top-left-origin canvas in AppKit screen-point units for each
capture session. Its origin is the top-left of the frozen snapshots' bounding
rectangle, including layouts with negative display origins.

- Convert screen input to canvas coordinates once when creating/updating marks.
- Store all annotation geometry and size measurements in canvas units, with names
  that explicitly distinguish them from image pixels and local view coordinates.
- Keep annotation IDs, order, color, full paths, and text unchanged when bounds
  change. Resize/Move must not translate or rescale stored annotations.
- Preserve current initial annotation appearance when converting existing
  pixel-valued tool settings into canvas units. Do not silently reinterpret saved
  widths or font sizing as screen points. Include arrowheads, sampling thresholds,
  and minimum geometry sizes in that audit, not just point positions.
- Retain each mark's creation-time X/Y pixel basis for brush, arrowhead, and glyph
  proportions when the measured snapshot density is anisotropic. This basis is
  immutable across selection changes; the text editor uses it too.
- Commit active text using the existing tool-switch behavior before starting a
  Move/resize. Draft geometry must use the same canvas as committed geometry.

### Shared coordinate mapping

Introduce a small value-type mapping module, tentatively
`Sources/AnnotationCanvas.swift`, for screen/canvas/selection-image transforms.
Keep mapping knowledge out of individual annotation-tool branches.

Its interface should accept the immutable canvas frame, the actual selection
frame, and destination dimensions/frame. It should support input conversion and
the transform needed by the shared renderer, without introducing a protocol or
alternative renderer hierarchy.

- Preview uses the current selection bounds, including during dragging, without
  depending on the old captured image's size.
- Export uses the committed, pixel-aligned selection frame and actual image
  width/height. Use effective X/Y scale rather than assuming a Retina factor.
- Both paths draw complete annotations through the same renderer and clip to the
  selection. Per-display clipping must not redefine the canvas or selection frame.
- Crop alignment changes only the mapping, never stored annotation coordinates.
- Keep the existing direct-source crop/composite resolution policy. Do not add a
  full-desktop raster allocation merely to establish a stable coordinate system.
- Composite background placement must use the same effective X/Y output density
  as annotations. Integral source crops are drawn at their real expanded screen
  extent and clipped to the requested intersection, not squeezed into it.

## Implementation sequence

### 1. Establish mapping and state invariants

- Add the canvas/mapping value type and focused conversion tests.
- Establish its immutable frame when the capture session receives snapshots.
- Migrate annotation geometry and draft input to canvas coordinates, updating
  field names and call sites together rather than retaining two competing models.
- Cover offset/negative origins, fractional density, independent X/Y scale, and
  forward/reverse coordinate conversion.
- Keep annotations visually unchanged in a selection that has not been moved or
  resized, and preserve existing annotation-only undo behavior.

### 2. Integrate shared preview/export rendering

- Update `Renderer` to draw canvas annotations through an explicit mapping.
- Update overlay drawing, pointer conversion, and text-field placement/font
  sizing to use that mapping.
- Update export preparation to supply the committed selection frame and image
  size; leave downstream save and clipboard contracts unchanged.
- Preserve clipping, text orientation, arrowheads, highlight alpha, and caller
  graphics-state restoration.
- Keep existing preview/export tests passing and extend them for the new model.

### 3. Enable resizing and content-anchored Move

- Remove the annotation-presence condition from resize availability only.
- Retain Move-tool, active-tool, and text-editing interaction guards.
- Preserve existing minimum selection size, display constraints, cursor feedback,
  and handle interaction behavior.
- During resize/Move, render marks over their original frozen content. On release,
  regenerate the selected image and apply the actual aligned frame without
  rewriting marks or changing their screen-space size.
- Keep retained hidden annotations from accidentally enabling replacement
  selection. Undoing all annotations restores existing no-annotation behavior.
- Ensure copy/save cannot combine a stale selected image with a different
  annotation mapping during an active interaction; use a consistent committed
  image/frame pair. Do not add selection history to solve export consistency.

### 4. Verify lifecycle and document the behavior

- Clear canvas/draft/annotation state on cancel and start each capture cleanly.
- Preserve current Esc behavior and error recovery; no new drag-cancel behavior.
- Update user-facing documentation to explain resizing, content-anchored Move,
  hidden annotations, and annotation-only undo.
- Record signed-app QA observations and build identity separately from expected
  behavior and unverified hypotheses.

## Acceptance and automated verification

Extend `Tests/ScreenCaptureAllTests/RendererTests.swift` and add focused
canvas/selection-state test files as needed, using Swift Testing.

1. All five tools remain over the same content through every resize edge/corner;
   preview during drag, preview after release, and export agree.
2. Partial/full exclusion clips marks without mutating them. Re-expansion restores
   full paths, text, and arrowheads, not reconstructed fragments.
3. Move away/back hides/restores marks at their original content locations.
4. Resize/Move do not affect annotation order, IDs, or undo. Cmd-Z removes the last
   annotation even if hidden; the selection stays unchanged.
5. Annotations created after resizing/moving use the same canvas as earlier marks.
6. Existing annotation sizes remain stable across density transitions. Preview
   and export agree at 1x, 2x, and 5/3x, with mixed-density spanning selections,
   negative origins, and a selection partly visible in each overlay.
7. Repeated resize/Move and pixel alignment cause no cumulative annotation drift
   or unintended crop growth.
8. Draft text, tool switching, no-annotation resizing/reselection, and export
   clipping remain correct. Cancel/new capture leaks no marks or canvas state.
9. Unannotated base pixels retain the existing capture-quality guarantees.

Run `swift test`, using the documented `TestingMacros` workaround only for its
specific missing-plugin error; also run `swift build -c release` and
`git diff --check`. Synthetic/offscreen tests do not validate live displays.

## Manual QA

Use the source-built, stably signed diagnostic app and the launch/evidence
workflow in `AGENTS.md` and `README.md`; do not overwrite the installed app or
change permissions/signing without consent.

- Use non-sensitive sharp text as background and exercise every annotation tool.
- Resize from every handle; compare during dragging and after release.
- Shrink through marks, expand, Move away/back, then undo a hidden annotation.
- Add new marks after resizing and repeat copy/save checks.
- Exercise each real display and mixed-density spanning selections. Verify
  dimensions, direct crop/composite quality, and exported placement at 100% zoom.
- Verify Esc, active text, new capture, and existing no-annotation interactions.
- Check fresh diagnostics and PNG evidence; keep private artifacts local. Record
  unavailable display configurations as unverified, not passed.

## Scope and estimate

Medium-sized change concentrated in selection state, coordinate mapping,
annotation rendering, and tests. Budget roughly 4–7 engineering days including
the confirmed Move behavior change and real mixed-display QA. This is a planning
estimate, not a delivery commitment; unavailable QA hardware can delay validation.

## Unresolved questions

None currently. Ask the user before changing confirmed behavior, replacing the
stable-canvas architecture, broadening scope, or selecting a new product policy.
