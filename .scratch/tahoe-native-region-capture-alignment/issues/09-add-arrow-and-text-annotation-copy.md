# Add Arrow And Text Annotation Copy

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Complete the MVP annotation tool set by adding arrow and text creation to the overlay toolbar and exported PNG path. Text should be click-to-place and user-entered before commit; no sample text should be inserted automatically.

## Acceptance criteria

- [x] Arrow annotations can be created from drag start to drag end.
- [x] Text annotations can be placed, edited, and committed before export.
- [x] Color and stroke defaults apply sensibly to arrow annotations.
- [x] Color defaults apply sensibly to text annotations.
- [x] Undo removes the latest arrow or text annotation.
- [x] Copy output includes arrow and text annotations at the expected image-space positions.

## Blocked by

- [07-copy-annotated-rectangle-from-overlay.md](07-copy-annotated-rectangle-from-overlay.md)

## Resolved bugs

- Text annotations were not reliably committed into the annotation model.
- Repro was: select Text, place text, type content, then click another toolbar action or copy/save.
- Root cause: the mouse-up event for text placement ran the generic annotation commit path, which cleared the empty text draft before the text field could commit typed content.
- Fix: generic mouse-up/annotation commit now skips text drafts; text commits only through the active text-field commit path.
- Verified with `swift build` and manual user QA.

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
- Fixed text draft persistence by preventing the generic mouse-up commit path from clearing active text drafts before the text field commits.
- Verified with `swift build` and user-confirmed manual QA.
