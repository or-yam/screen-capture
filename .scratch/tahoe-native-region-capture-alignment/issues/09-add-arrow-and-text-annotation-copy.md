# Add Arrow And Text Annotation Copy

Status: doing
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Complete the MVP annotation tool set by adding arrow and text creation to the overlay toolbar and exported PNG path. Text should be click-to-place and user-entered before commit; no sample text should be inserted automatically.

## Acceptance criteria

- [x] Arrow annotations can be created from drag start to drag end.
- [ ] Text annotations can be placed, edited, and committed before export.
- [x] Color and stroke defaults apply sensibly to arrow annotations.
- [x] Color defaults apply sensibly to text annotations.
- [x] Undo removes the latest arrow or text annotation.
- [ ] Copy output includes arrow and text annotations at the expected image-space positions.

## Blocked by

- [07-copy-annotated-rectangle-from-overlay.md](07-copy-annotated-rectangle-from-overlay.md)

## Known bugs

- Text annotations are not reliably committed into the annotation model.
- Repro: select Text, place text, type content, then click another toolbar action or copy/save.
- Expected: typed text remains visible and is included in copied/saved PNG output.
- Actual: typed text disappears or is missing from copy/save output.
- Prior attempted fix committed active text before toolbar actions and mapped Size to font size, but QA confirmed the real persistence bug remains.
- Arrow annotation behavior is still considered implemented.

## Comments

- Arrow-only slice implemented.
- Added Arrow toolbar action in the region overlay.
- Arrow annotations are stored as stable image-space start/end points and can be undone through the existing annotation stack.
- Preview and rendered PNG export both draw arrowheads using the selected color and stroke width.
- Verified with `swift build`.
- Added Text toolbar action in the region overlay.
- Text annotations are click-to-place with an empty focused text field; no sample text is inserted automatically.
- Text remains editable before commit, commits on Enter/focus loss/copy/save when non-empty, and Esc/Cmd+Z cancels the active draft.
- Text annotations use the selected color, stable image-space top-left positions, and a fixed image-space font size for preview/export consistency.
- Preview and rendered PNG export both draw committed text annotations.
- Verified with `swift build`.
