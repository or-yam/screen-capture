# Annotation Overflow Beyond the Capture Frame

Status: implemented on `feat/annotation-overflow-selection`; automated verification and signed-app manual QA tracked in [the QA notes](../annotation-selection-move/qa/README.md)

## Outcome

Allow every annotation tool—Text, Arrow, Rectangle, Draw, and Highlight—to extend visibly outside the capture frame while remaining confined to the session's capture display. Copy/Save must still include only pixels inside both the capture frame and capture display.

This follows [Text Annotation UX](../text-annotation-ux/spec.md). The owner requested overflow and [Select and Move Annotations](../annotation-selection-move/spec.md) together on one new branch, `feat/annotation-overflow-selection`, superseding the earlier separate-branch plan.

## Agreed behavior

- Follow the app-wide [one-screen-per-session rule](../../NEW_PRD.md#one-screen-per-capture-session). The initial selection chooses the capture display; initial/replacement selection, capture-frame Move/resize, and all annotation work stay there. Captures spanning displays are not supported. To use another screen, exit and start a new capture there.
- Draft and committed annotations remain visible beyond the capture frame.
- Neither drawing nor annotation movement can transfer an annotation to another display. Other display overlays cannot start annotations or switch the session's capture display.
- Capture bounds do not grow automatically. Copy/Save clips annotations to those bounds.
- Moving or resizing the capture frame never moves or rewrites annotations; previously excluded content can be included again.
- Preserve the stable canvas and each annotation's creation-time X/Y pixel basis.

## Interaction defaults

- Keep initial placement inside the selected region, preserving current click-to-place behavior. Once a drawing drag starts, it may continue across the capture edge to the originating display edge.
- Clamp pointer coordinates to that display during an active drag, including mouse-up outside the display. Returning the pointer must continue the same gesture without jumps.
- Text remains newline-only, grows right/down, and can exceed capture bounds. At a display edge, clip the editor and its painted text to that display; do not wrap, shrink, or move the text anchor to fit.
- Every annotation belongs to the session's fixed capture display. A display seam is a hard limit, not another capture edge to draw across.
- Retain existing Esc behavior: discard the draft and return to Move; Esc in Move closes the capture.

## Pre-implementation constraints (baseline)

- `RegionCaptureOverlayView.canvasPointForAnnotationEvent` currently rejects every drawing event outside the visible selected rectangle, including drag and release.
- `RegionCaptureOverlayView.draw` clips the entire selected-content pass to the capture frame.
- `Renderer.drawAnnotations` also clips to its destination rectangle. Removing only one of these clips will not enable overflow.
- `OverlayAnnotation` has stable canvas geometry but no originating-display identity yet. Overlay windows share `RegionSelectionState`.
- `RegionSelectionState` does not yet own a fixed capture display. Selection start/update/release do not enforce that rule; existing multi-display crop support must not determine what the user is allowed to select.
- The live text editor is a subview and already overflows during editing; committed text still uses the clipped renderer. The existing editor/export parity tests assume capture-clipped committed previews and must be adapted deliberately.

## Implementation plan

1. **Own the capture display and drag constraints in the model.** Record capture display identity and its frozen frame when initial region selection begins, then retain it until the session ends. Constrain initial/replacement selection and capture-frame Move/resize to that display; reject new placement/reselection from other display overlays. Each annotation inherits this display identity. Reuse frozen `DisplaySnapshot` geometry; do not infer ownership later from a moved capture frame or the pointer's current display. This session-wide enforcement is required before enabling overflow.
2. **Separate placement from drag continuation.** Keep the selected-region guard for a new annotation; after start, map updates/releases through the same canvas and clamp to the originating display, not the selection. Always complete/discard a gesture on mouse-up, even after leaving the frame.
3. **Separate preview clipping from export clipping.** Preserve the full selection-to-destination transform, but give annotation rendering an explicit capture-display clip for preview. Export clips to both the capture frame and capture display, including any stored text beyond the display edge. Do not reuse a display intersection as the destination transform; that would rescale or shift geometry.
4. **Draw outside-frame annotations above the dimmed frozen content.** Render the frozen selection/background as today, then render annotation ink clipped to its owner display. Keep capture border/handles and toolbars distinguishable; never export those affordances.
5. **Apply display confinement to live text.** Retain the same text layout/anchor and clip its editing surface to its originating display. Store the entire string, even when some text cannot fit onscreen. Do not alter font size, line breaks, or export placement.
6. **Update docs and QA expectations.** Make editing bounds, preview bounds, and output bounds explicit. Preserve export-size and pixel-quality guarantees.

Keep the preview/export clip choice at the renderer seam rather than duplicating annotation drawing in the overlay. Keep display constraint decisions in `RegionSelectionState` so shared overlays and tests use the same rules.

## Automated tests (Swift Testing)

- Parameterize all tools: start inside the selection, drag/type outside it, finish outside it; draft and committed geometry persist and preview ink is visible beyond the capture edge.
- Compare preview/export only inside the capture bounds. Independently assert overflow ink exists outside the frame in preview and that exported pixel dimensions stay unchanged.
- Verify pointer clamping at all four display edges, release outside a display, and leaving/re-entering a drag. No annotation appears in a neighboring display's preview.
- Cover negative display origins, horizontal/vertical display arrangements, and 1×/2×/fractional/independent X/Y densities using synthetic snapshots. Choose each display in separate sessions; attempted spanning selections must stop at the capture display edge.
- Verify initial selection, replacement selection, capture-frame Move/resize, and annotation placement stay on the fixed capture display. Clicking another display cannot change it, even without annotations; ending the session and starting another permits choosing that display.
- Verify output excludes annotation content beyond the capture display, including long text stored past a screen edge.
- Check multiline text/long-line overflow during editing and after commit; a display clip must not wrap text or shift its anchor.
- Regression: capture Move/resize, hidden-ink reveal, default Move, outside-click reselection restrictions, Undo, Esc, all Copy/Save paths, and unchanged base-image pixels.
- Use explicit expected screen/pixel geometry, not just two calls to the same renderer.

## Signed-app manual QA

Use the source-built diagnostic app and stable signing workflow in `AGENTS.md`. Use non-sensitive content; keep screenshots local.

- [ ] On each available display, draw every tool past each capture edge. Verify draft and committed overflow remain visible.
- [ ] Drag to a display seam and beyond; ink stays on the originating display. Repeat with negative-coordinate and vertical arrangements where available.
- [ ] Attempt initial selection, replacement selection, capture-frame Move/resize, and new annotation placement across screens. The capture display stays fixed; exit and reopen to capture the other screen.
- [ ] Test text near a display edge, multiline input, and long unwrapped lines; no automatic repositioning or wrapping.
- [ ] Copy/Save; inspect at 100% zoom. Output dimensions and capture-edge clipping are unchanged; no dimming, toolbar, border, or selection affordance leaks into output.
- [ ] Move/resize the capture frame to include/exclude annotations; ink remains anchored to frozen content.
- [ ] Verify fresh run-tagged capture/export events and PNG artifacts; record build identity, dimensions, observations, and unverified cases separately.

## Non-goals

- Selecting or moving existing annotations (next feature).
- Starting new annotations outside the capture frame.
- Spanning captures, switching the capture display within a session, cross-display annotation transfer, capture auto-expansion, soft wrapping, or changing export dimensions.
- Persistent annotation documents or migration of saved sessions; annotations currently live only within a capture session.

## Open questions

None blocking. New annotations still start inside the capture frame. This plan adds overflow within the capture display and enforces the session-wide display lock for selection, Move/resize, and annotation work.
