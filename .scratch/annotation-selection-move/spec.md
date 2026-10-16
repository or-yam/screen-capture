# Select and Move Existing Annotations

Status: planned; not implemented
Depends on: [Annotation Overflow](../annotation-overflow/spec.md)

## Outcome

Add a dedicated **Select Annotations** toolbar button so an existing text, arrow, rectangle, drawing, or highlight can be picked and dragged without moving the capture frame.

Implement on a new feature branch after the overflow feature. Neither follow-up is implemented by the text-annotation UX branch.

## Agreed interaction

- Use a **pointer-arrow icon**, SF Symbol `cursorarrow`, for the new button. It must look distinct from the existing `arrow.up.right` annotation-drawing icon.
- Accessibility label: `Select Annotations`. Tooltip: `Select and move annotations`.
- Keep the existing hand-icon **Move** tool for moving/resizing the capture frame. Clarify its tooltip as `Move capture frame`; do not repurpose it to move annotations.
- In Select Annotations mode, click a visible annotation to select it and show a thin bounding outline. No resize handles.
- Drag the selected item from its visible hit area; preserve the initial pointer offset to avoid snapping its origin to the pointer.
- If visible items overlap, pick the topmost hit item (reverse paint order). Do not reorder it when selected/moved.
- Selection and dragging work on annotation portions outside the capture frame, anywhere on their originating display. Empty-space clicks deselect without moving/reselecting the capture frame.
- A move is translation only. Preserve identity, style, font, text, line breaks, creation-time X/Y basis, and stacking order.
- Dragging stays on the originating display; never transfer an item across a display seam.
- Esc clears selection and returns to the hand-icon Move tool. During an unfinished drag, revert that drag first, then exit; a later Esc in Move closes the capture.
- One completed, non-zero drag is one undoable action. Undoing a move restores position; it does not delete the annotation.

## Selection geometry and display constraints

- Hit-test painted geometry with a small screen-point tolerance so thin arrows/strokes are usable at all densities. Include arrowheads; don't treat a rectangle's empty interior as painted ink.
- For text, use the shared TextKit layout's line/text bounds, including multiline spacing. A text block is one item, not independently movable lines.
- Clip hit testing to the originating display. Invisible portions on another screen must not be selectable there.
- Show selection bounds around the item but clip the selection outline to its display. Selection UI is never part of Copy/Save.
- Clamp the translation using painted bounds (stroke extent and arrowheads included), not only the pointer. Normally the whole item's painted bounds must stay within its display.
- Oversized text/content cannot always fit. On an oversized axis, preserve the content and clamp its anchor within the display, clipping the excess; do not shrink, wrap, or make the item immovable. Record this exception in QA.

## Implementation plan

1. **Explicit tool mode.** Add Select Annotations as a mutually exclusive overlay mode, not an `OverlayAnnotationTool` kind. It creates no annotation. Keep capture Move, drawing tools, and item selection unambiguous. Switching tools commits any active text editor once before selecting an item.
2. **Centralize annotation geometry.** Introduce a small `AnnotationGeometry` module interface for bounds, hit testing, and translation in the stable canvas. Reuse the renderer's arrowhead/stroke geometry and `AnnotationTextLayout` text metrics rather than inventing approximate export-inconsistent hit boxes. Keep screen-point hit tolerance separate from creation-pixel stroke size.
3. **Model-owned drag transaction.** `RegionSelectionState` owns selected annotation ID and active translation state shared by all overlay windows. Begin from the original annotation and pointer; derive each update from that original, not accumulated deltas. Keep selected UI state separate from exportable geometry.
4. **Commit/cancel semantics.** Mouse-up commits one move. Esc/tool switch during dragging cancels the uncommitted translation before exiting/switching; no-op moves create no history. Copy/Save during a drag uses the last committed annotation position, consistent with the existing committed-frame policy during capture resizing.
5. **Operation-based annotation Undo.** Replace `annotations.popLast()` as the sole committed-undo behavior with annotation actions: creation and translation (before/after geometry). Preserve existing draft-first cancellation. Undo a move in place, retaining ID/style/order; Undo creation removes that item. Capture frame Move/resize remains outside annotation history. Clear history/selection/drag state on reset/new capture.
6. **Overlay interaction and presentation.** Route Select-mode mouse events before capture Move/reselection. Draw selection outline separately from annotation ink; use pointer/open-hand/closed-hand cursors as appropriate. Refresh every overlay after selection/move/undo, clearing stale selected IDs when their item disappears.
7. **Docs and diagnostic QA.** Explain the two distinct move tools and Undo behavior. Reuse diagnostic provenance/evidence collection; add event-level selection/move commit/cancel diagnostics without logging typed text.

The state/geometry interfaces are the test surface. Do not add a general-purpose editor framework, plugin interface, or separate fake interaction implementation.

## Automated tests (Swift Testing)

- Parameterize every annotation kind: hit, select, translate, and undo. Assert ID, content/style, creation basis, and stacking order stay unchanged.
- Hit tests: overlapping items choose topmost; rectangle interior misses; thin strokes and arrowheads hit; multiline text and blank-line spacing behave consistently; empty space deselects.
- Verify bounds/hits in negative-coordinate, uniform/fractional/independent X/Y density, and multi-display layouts. Screen-point hit tolerance must not shrink on Retina.
- Drag preserves initial pointer offset; many incremental updates equal one final translation from the original; no-op drags create no Undo entry.
- Clamp all four display edges, including painted stroke extents, oversized text, and attempted seam crossing. Overflow outside the capture remains selectable/movable on its owning display.
- History: create A → move A → create B → Undo B → Undo move A → Undo creation A. Repeated moves undo individually; capture Move/resize never enters annotation Undo history.
- Esc mid-drag restores original geometry, deselects, returns to Move, and does not close. Next Esc closes. Tool switch cancels incomplete movement; Copy/Save mid-drag exports committed geometry.
- Synthetic overlay input verifies button exclusivity, pointer-arrow selection action versus arrow drawing, capture frame immobility in Select mode, focus routing, and deselection on undo/reset.
- Rendering: live translated preview and committed export align inside capture bounds; outline never appears in output; Undo restores original output pixels. Use independent expected geometry as well as preview/export comparisons.
- Run the full `swift test` suite (README macro workaround if needed) plus release build and whitespace checks.

## Signed-app manual QA

Use the stable signed diagnostic app, non-sensitive content, and local-only evidence.

- [ ] Pointer-arrow button is recognizable and distinct from the Arrow drawing tool; labels/tooltips and active appearance are correct.
- [ ] Select/drag each tool's annotation, including text, marks partly/fully outside the capture frame, overlapping marks, and thin strokes.
- [ ] Capture frame stays fixed while an annotation moves; hand-icon Move still moves/resizes only the capture frame.
- [ ] Drag near all display edges/seams; marks stay on the originating display without wrapping, resizing, or losing pointer offset.
- [ ] Undo each move and creation in order; Esc cancels an unfinished drag without deleting ink or closing the capture.
- [ ] Copy/Save moved multiline text and shapes; compare preview/export at 100%, verify capture clipping, dimensions, and absence of selection outline.
- [ ] Repeat per real display and relevant arrangements; record build identity and run-tagged events/PNGs. Do not call synthetic multi-display tests a hardware QA pass.

## Non-goals

- Annotation resizing/rotation, per-point edits, text re-editing, multi-selection, group moves, keyboard nudging, or redo.
- New global shortcuts, cross-display transfer, drag-and-drop between apps, or persistent documents.

## Open questions

None blocking. `cursorarrow` is the planned pointer-arrow icon; confirm its visual distinction during toolbar QA.
