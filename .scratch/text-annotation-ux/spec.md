# Text Annotation UX: Transparent Field, Multi-line, Esc Exit

Status: implemented; automated checks passed; user UX accepted
Type: AFK
Branch: `feature/text-annotation-ux`

## Problem

1. The live text-annotation editor draws an opaque bezel/background (`NSColor.textBackgroundColor` at 0.9 alpha), so the annotation looks like a black box while typing. It should be invisible except for the caret and the typed glyphs.
2. `Esc` in text mode does nothing. `Enter` commits instead of inserting a newline.
3. The original `AnnotationTextField.keyDown` handled Esc/Enter on the control, but AppKit's shared field editor receives typing while editing. That made the key handler unreliable. The original end-editing delegate committed text; no signed-app routing trace was collected for the old behavior.

## Decisions (locked)

- Editor is fully transparent: no background, no border, no bezel. Caret + glyphs only.
- `Enter` inserts a newline. No soft wrapping; lines break only where the user presses Enter.
- `Esc` discards the in-progress draft and returns to Move mode. The overlay stays open.
- Commit remains on click-away / `Cmd-C` / `Cmd-S` / tool switch. No dedicated commit key.
- One feature branch for all of it.
- Long lines visibly overflow the selection while editing; export still clips to the capture bounds.
- Discard on Esc is silent, including non-empty drafts. Esc exits a selected annotation tool even before a draft is placed. In Move mode, Esc closes the capture.
- Changes were initially left uncommitted for review. After user UX acceptance, the user authorized committing, merging, and pushing to main if checks passed.

## Scope

- Replace `AnnotationTextField` with a plain `AnnotationTextEditor` (`NSTextView`) for transparency, multi-line editing, and native responder routing.
- Text-field sizing/anchoring for multiple lines.
- Esc path in `RegionCaptureOverlayController`.
- Doc/spec updates where the old behavior is stated.

## Non-goals

- Rich text, styling, font picker.
- Committing the text tool automatically after a successful commit (current behavior: tool stays active) — unchanged.
- Changing committed-annotation storage format beyond allowing `\n` in `text`.

## Implementation (including corrections to the initial outline)

1. Use `AnnotationTextEditor`, a plain `NSTextView`, rather than adapting `NSTextField` and its shared field editor. Passing Enter through the field-editor delegate does not guarantee newline insertion. A non-field-editor text view handles newlines natively; `cancelOperation(_:)` routes Esc to `exitAnnotationMode()`.
2. Disable background, rich text, container padding/insets, automatic substitutions, and spelling/grammar decorations. Measure TextKit layout on each edit and grow right/down from the click, preserving creation-time X/Y scaling. Trailing newlines get an extra line fragment for the caret. No soft wrapping or selection-edge clamping.
3. Share font attributes and unwrapped TextKit layout via `Sources/AnnotationTextLayout.swift`; draw export from the same top-left layout instead of anchoring a multi-line `NSString.draw(at:)` to a single font-size offset. This is necessary for live-editor/export parity.
4. Clear editor ownership and mark completion before removing it, preventing focus-loss reentrancy from committing discarded drafts or double-committing text. Ignore AppKit end-editing notifications for detached views (AppKit emits these on programmatic edits without a window).
5. Overlay Esc exits a selected annotation tool and discards its draft. With no active tool/editor it closes the capture. Existing click-away, focus-loss, tool switch, Copy/Save, and annotation Undo paths remain.

## Test plan

The offscreen harness drives the overlay with synthetic events in `Tests/ScreenCaptureAllTests/OverlayInteractionTests.swift`. A never-ordered AppKit window additionally validates first-responder input and actual focus loss; it does not capture the desktop or need Accessibility. Toolbar state is refreshed explicitly because the test refresh callback is otherwise a no-op.

New tests:

- T1 Transparent plain editor; no inset/padding; long lines grow width without growing height or wrapping, explicit Return grows height downward without moving the top-left anchor.
- T2 Esc through both editor command routing and overlay fallback discards only the draft and returns to Move; repeated completion does not mutate committed ink. Second Esc closes. Also test Text selected with no editor yet.
- T3 A hidden window makes the editor first responder; synthetic Return inserts a newline without committing, real focus loss commits once, and Esc on a second editor discards its draft and focuses the overlay.
- T4 Multi-line commit: `updateDraftText("a\nb\nc")` + `commitDraftText()` preserves inner newlines; outer whitespace still trimmed (extends `RegionSelectionStateTests.draftTextUndoAndResetDoNotLeakIntoAnotherCapture`).
- T5 Compare actual live `NSTextView.draw` pixels against exported PNG, plus committed preview/export footprints: single line, three lines, blank middle line, non-ASCII text, and overflow, at 1×, 2×, anisotropic 2×/1×, and fractional 5/3×/2× density. Independently assert adding lines keeps the first line fixed and places further ink below it.
- T6 Regression: `annotationInputAfterMoveUsesCanvasAndTextCommitsOnToolSwitch` and `textEditorUsesTheDraftsAnisotropicGlyphBasis` still pass; update the latter if field auto-sizing changes the asserted `bounds`/`frame`.
- T7 Esc in Move mode (no active annotation tool/editor) still closes the overlay.
- T8 Multi-line commit exactly once through click-away, Move, Arrow, Copy/Save buttons, and Cmd-C/Cmd-S. Cmd-Z discards only the draft and retains the Text tool; a subsequent Cmd-Z still undoes the latest committed annotation.

Run: `swift test` (use the `-load-plugin-library` workaround from `README.md:69` if `TestingMacros` discovery fails).

## Manual QA plan

Use the source-built diagnostic app per `AGENTS.md` (`Scripts/run_capture_diagnostics.sh`), single display first, then extended.

1. Text tool → click → empty field shows only the blinking caret over the frozen region; no box/bezel.
2. Contrast: type over a dark region and a light region; confirm glyphs remain legible with no scrim.
3. WYSIWYG baseline: type one line, commit via tool switch, `Cmd-C`; at 100% zoom confirm glyph position/size matches what the field showed (bezel removal + line height are the risks).
4. `Enter` inserts a newline, the field grows downward, caret moves to the new line.
5. `Esc` discards the draft and returns to Move mode (Move highlighted), overlay stays open; a second `Esc` closes it without output.
6. Long single line (no Enter) exceeding the selection width: record the field behavior and compare to export.
7. Commit paths: click-away, `Cmd-C`, `Cmd-S`, tool switch all commit. Esc itself must not remove previously committed annotations. Cmd-Z with a draft discards only that draft; without a draft it retains normal annotation Undo behavior.
8. Copy/Save a multi-line annotation; inspect the export at 100% zoom and check pixel dimensions; confirm fresh rows in `.build/capture-diagnostics/evidence/events.log` and new PNGs.
9. Repeat on the non-main display in extended mode.

## Risks

- R1 Live and exported multiline placement could differ. Mitigated by shared TextKit layout and T5, which draws the real editor rather than comparing the renderer to itself. Native blinking-caret appearance still needs signed-app QA.
- R2 Multi-line field must keep the anisotropic `setBoundsSize` basis or glyphs resize on screen.
- R3 Text wider than the selection is clipped on export (`Renderer.drawAnnotations` clips to `destinationRect`) but may overflow visibly in the field.
- R4 Input routing: replaced the shared field editor with a direct responder and tested Return/Esc in a hidden window. Manual step 5 still validates interaction in the actual capture app.
- R5 Removing the `keyDown` branches must not change any non-text behavior.
- R6 Doc drift: `README.md:222`, `docs/ARCHITECTURE.md:114,160`, `docs/CURRENT-QA-NOTES.md:34`, issue `09` line 44, issue `06` line 74.

## Validation / QA status

- Automated test results and remaining manual QA are recorded in [qa.md](qa.md).
- After the user quit the installed app, the signed diagnostic build was launched successfully. Current-run capture/export events and a 1306×936, 185111-byte exported PNG were subsequently verified. The user reported that the feature "looks good overall." See the QA record for evidence identity and coverage limits; extended-display hardware QA remains unverified.

## Follow-ups (separate features; not implemented here)

- [Annotation Overflow](../annotation-overflow/spec.md): draft and committed ink may extend past the capture frame but not its originating display; export still clips to capture bounds.
- [Select and Move Annotations](../annotation-selection-move/spec.md): pointer-arrow toolbar button, topmost-item selection/dragging, and action-based move Undo.

## Open questions

None. Exhaustive manual cases and extended-display hardware coverage remain unverified; this is not a claim of an extended-display QA pass.
