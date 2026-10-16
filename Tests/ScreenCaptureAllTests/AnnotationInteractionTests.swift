import AppKit
import Testing
@testable import ScreenCaptureAll

/// Synthetic overlay-input coverage for the Select Annotations / Move
/// annotation feature (`annotation-selection-move/spec.md`) and the
/// display-confined overflow rules (`annotation-overflow/spec.md`).
///
/// Everything here runs against a detached `RegionCaptureOverlayView` with no
/// window, so local and AppKit screen coordinates coincide (`screenPoint(for:)`
/// falls back to `event.locationInWindow` when there is no window). No live
/// app, desktop, clipboard, or permission prompt is touched.
@MainActor
struct AnnotationInteractionTests {
    // MARK: - Pointer button and toolbar exclusivity

    @Test
    func selectAnnotationsButtonUsesAPointerSymbolDistinctFromTheArrowTool() throws {
        let (view, _) = try makeOverlay()
        let select = try button("Select Annotations", in: view)
        let arrow = try button("Arrow", in: view)

        let selectImage = try #require(select.image)
        let arrowImage = try #require(arrow.image)

        #expect(select.accessibilityLabel() == "Select Annotations")
        #expect(select.toolTip == "Select and move annotations")
        #expect(arrow.accessibilityLabel() == "Arrow")
        // The pointer button is a separate control from the arrow drawing tool
        // and does not reuse its glyph. NSButton does not expose the SF Symbol
        // name, so the exact `cursorarrow` glyph is confirmed in manual QA.
        #expect(selectImage !== arrowImage)
        #expect(select.accessibilityLabel() != arrow.accessibilityLabel())
    }

    @Test
    func toolbarModesAreMutuallyExclusiveAndMoveKeepsItsCaptureTooltip() throws {
        let (view, state) = try makeOverlay()
        let move = try button("Move", in: view)
        let select = try button("Select Annotations", in: view)

        #expect(move.toolTip == "Move capture frame")
        view.refreshState()
        #expect(move.isActive)
        #expect(!select.isActive)

        select.performClick(nil)
        view.refreshState()
        #expect(state.interactionMode == .selectAnnotations)
        #expect(select.isActive)
        #expect(!move.isActive)

        let arrow = try button("Arrow", in: view)
        arrow.performClick(nil)
        view.refreshState()
        #expect(state.interactionMode == .draw(.arrow))
        #expect(arrow.isActive)
        #expect(!select.isActive)
        #expect(!move.isActive)

        move.performClick(nil)
        view.refreshState()
        #expect(state.interactionMode == .moveCapture)
        #expect(move.isActive)
        #expect(!arrow.isActive)
        #expect(!select.isActive)
    }

    // MARK: - Selection and drag

    @Test(arguments: OverlayAnnotationTool.allCases)
    func selectModeDragsEveryToolWithoutMovingTheCapture(tool: OverlayAnnotationTool) throws {
        let (view, state) = try makeOverlay()
        let mark = try addOffCaptureMark(tool, to: state)
        let capture = try #require(state.selectionRect)
        let capturedSelection = try #require(state.capturedSelectionRect)

        view.refreshState()
        try button("Select Annotations", in: view).performClick(nil)

        let start = try annotationHitPoint(mark, in: state)
        let target = try dragTarget(fromScreen: start, canvasDelta: CGSize(width: 40, height: -30), in: state)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        #expect(state.selectedAnnotationID == mark.id)
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: target))
        #expect(state.annotationMoveIsActive)
        view.mouseUp(with: try mouse(.leftMouseUp, at: target))

        let moved = try #require(state.annotations.first { $0.id == mark.id })
        expectSameGeometry(moved, AnnotationGeometry.translated(mark, by: CGSize(width: 40, height: -30)))
        #expect(state.selectionRect == capture)
        #expect(state.capturedSelectionRect == capturedSelection)
        #expect(state.capturedImage != nil)
    }

    @Test
    func dragPreservesTheInitialPointerOffset() throws {
        let (view, state) = try makeOverlay()
        let mark = try addOffCaptureMark(.rectangle, to: state)
        let rect = try #require(mark.rectInCanvas)
        let canvas = try #require(state.annotationCanvas)

        view.refreshState()
        try button("Select Annotations", in: view).performClick(nil)

        // Grab the top edge well away from the rectangle's origin.
        let grab = CGPoint(x: rect.maxX - 10, y: rect.minY)
        let move = CGSize(width: 30, height: 10)
        let start = canvas.screenPoint(fromCanvas: grab)
        let end = canvas.screenPoint(fromCanvas: CGPoint(x: grab.x + move.width, y: grab.y + move.height))

        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: try mouse(.leftMouseUp, at: end))

        let moved = try #require(state.annotations.first { $0.id == mark.id })
        #expect(moved.rectInCanvas == rect.offsetBy(dx: move.width, dy: move.height))
    }

    @Test
    func annotationsStayCommittedUntilTheMoveIsReleased() throws {
        let (_, state) = try makeOverlay()
        let mark = try addOffCaptureMark(.arrow, to: state)
        state.interactionMode = .selectAnnotations

        let begin = try #require(mark.pointsInCanvas.first)
        let delta = CGSize(width: 30, height: -20)
        state.beginAnnotationMove(at: begin)
        #expect(state.selectedAnnotationID == mark.id)
        #expect(state.annotationMoveIsActive)

        // Incremental updates are derived from the original geometry.
        state.updateAnnotationMove(to: CGPoint(x: begin.x + 10, y: begin.y - 5))
        state.updateAnnotationMove(to: CGPoint(x: begin.x + delta.width, y: begin.y + delta.height))

        // Committed geometry is untouched; only the preview reflects the drag.
        expectSameGeometry(try #require(state.annotations.first), mark)
        expectSameGeometry(
            try #require(state.previewAnnotations.first { $0.id == mark.id }),
            AnnotationGeometry.translated(mark, by: delta)
        )

        state.commitAnnotationMove()
        #expect(!state.annotationMoveIsActive)
        expectSameGeometry(try #require(state.annotations.first), AnnotationGeometry.translated(mark, by: delta))
        expectSameGeometry(try #require(state.previewAnnotations.first), AnnotationGeometry.translated(mark, by: delta))
    }

    // MARK: - Hit testing

    @Test
    func rectangleInteriorMissesItsInkButItsEdgeHits() throws {
        let (_, state) = try makeOverlay()
        let rectangle = try addOffCaptureMark(.rectangle, to: state)
        let rectInCanvas = try #require(rectangle.rectInCanvas)
        state.interactionMode = .selectAnnotations

        // A rectangle's empty interior is not painted ink.
        state.beginAnnotationMove(at: CGPoint(x: rectInCanvas.midX, y: rectInCanvas.midY))
        #expect(state.selectedAnnotationID == nil)
        #expect(!state.annotationMoveIsActive)

        // Its stroke edge does hit.
        state.beginAnnotationMove(at: CGPoint(x: rectInCanvas.midX, y: rectInCanvas.minY))
        #expect(state.selectedAnnotationID == rectangle.id)
        state.cancelAnnotationMove()
        #expect(state.selectedAnnotationID == rectangle.id, "cancelling keeps the selection")
    }

    @Test
    func overlappingStrokesSelectTheTopmostWithoutReordering() throws {
        let (_, state) = try makeOverlay()
        let lower = try addOffCaptureMark(.draw, to: state)
        let upper = try addOffCaptureMark(.draw, to: state)
        let overlap = try #require(upper.pointsInCanvas.first)
        #expect(lower.pointsInCanvas.first == overlap)
        state.interactionMode = .selectAnnotations

        state.beginAnnotationMove(at: overlap)
        #expect(state.selectedAnnotationID == upper.id)
        // Selecting does not reorder the committed stack.
        #expect(state.annotations.map(\.id) == [lower.id, upper.id])
    }

    // MARK: - Escape and tool switching

    @Test
    func escapeMidDragRevertsTheTranslationThenClosesOnTheNextEscape() throws {
        var closeCount = 0
        let (view, state) = try makeOverlay(close: { closeCount += 1 })
        let mark = try addOffCaptureMark(.arrow, to: state)

        view.refreshState()
        try button("Select Annotations", in: view).performClick(nil)

        let start = try annotationHitPoint(mark, in: state)
        let target = try dragTarget(fromScreen: start, canvasDelta: CGSize(width: 50, height: -40), in: state)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: target))
        #expect(state.selectedAnnotationID == mark.id)
        #expect(state.annotationMoveIsActive)
        #expect(state.previewAnnotations.first { $0.id == mark.id }?.pointsInCanvas != mark.pointsInCanvas)

        view.keyDown(with: try escape())
        #expect(closeCount == 0)
        #expect(state.interactionMode == .moveCapture)
        #expect(state.selectedAnnotationID == nil)
        #expect(!state.annotationMoveIsActive)
        expectSameGeometry(try #require(state.annotations.first { $0.id == mark.id }), mark)
        #expect(state.previewAnnotations.first { $0.id == mark.id }?.pointsInCanvas == mark.pointsInCanvas)

        view.keyDown(with: try escape())
        #expect(closeCount == 1)
    }

    @Test
    func switchingToolsMidDragDiscardsTheUncommittedTranslation() throws {
        let (view, state) = try makeOverlay()
        let mark = try addOffCaptureMark(.arrow, to: state)
        let capture = try #require(state.selectionRect)

        view.refreshState()
        try button("Select Annotations", in: view).performClick(nil)

        let start = try annotationHitPoint(mark, in: state)
        let target = try dragTarget(fromScreen: start, canvasDelta: CGSize(width: 60, height: 0), in: state)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: target))
        #expect(state.annotationMoveIsActive)

        try button("Draw", in: view).performClick(nil)
        view.refreshState()
        #expect(state.interactionMode == .draw(.draw))
        #expect(state.selectedAnnotationID == nil)
        #expect(!state.annotationMoveIsActive)
        expectSameGeometry(try #require(state.annotations.first { $0.id == mark.id }), mark)
        #expect(state.previewAnnotations.first { $0.id == mark.id }?.pointsInCanvas == mark.pointsInCanvas)
        #expect(state.selectionRect == capture)
    }

    // MARK: - Export during a drag

    @Test(arguments: ["Copy", "Save", "c", "s"])
    func exportDuringDragUsesCommittedGeometry(path: String) throws {
        var exported: Data?
        let (view, state) = try makeOverlay(copy: { exported = $0 }, save: { exported = $0 })
        let mark = try addOffCaptureMark(.rectangle, to: state)
        let image = try #require(state.capturedImage)
        let canvas = try #require(state.annotationCanvas)
        let capturedSelection = try #require(state.capturedSelectionRect)
        let expected = try Renderer().renderPNG(
            baseImage: image, annotations: state.annotations, canvas: canvas, selectionRect: capturedSelection
        )

        view.refreshState()
        try button("Select Annotations", in: view).performClick(nil)
        let start = try annotationHitPoint(mark, in: state)
        let target = try dragTarget(fromScreen: start, canvasDelta: CGSize(width: 50, height: 40), in: state)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: target))
        #expect(state.annotationMoveIsActive)

        try triggerExport(path, in: view)

        #expect(exported == expected)
        expectSameGeometry(try #require(state.annotations.first { $0.id == mark.id }), mark)
    }

    @Test
    func selectionOutlineIsNotPartOfExportedBytes() throws {
        var exported: Data?
        let (view, state) = try makeOverlay(copy: { exported = $0 })
        let mark = try addOffCaptureMark(.arrow, to: state)
        let image = try #require(state.capturedImage)
        let canvas = try #require(state.annotationCanvas)
        let capturedSelection = try #require(state.capturedSelectionRect)
        let expected = try Renderer().renderPNG(
            baseImage: image, annotations: state.annotations, canvas: canvas, selectionRect: capturedSelection
        )

        view.refreshState()
        try button("Select Annotations", in: view).performClick(nil)
        let hit = try annotationHitPoint(mark, in: state)
        view.mouseDown(with: try mouse(.leftMouseDown, at: hit))
        view.mouseUp(with: try mouse(.leftMouseUp, at: hit))
        // The live view draws an outline around the selected item.
        #expect(state.selectedAnnotationID == mark.id)

        try button("Copy", in: view).performClick(nil)
        #expect(exported == expected)
    }

    // MARK: - Overflow and the one-screen rule

    @Test(arguments: AnnotationInteractionTests.drawingTools)
    func overflowDrawingStartsInsideThenFinishesOutsideTheCaptureFrame(tool: OverlayAnnotationTool) throws {
        let (view, state) = try makeOverlay()
        let canvas = try #require(state.annotationCanvas)
        let captureScreen = try #require(state.selectionRect)
        let captureCanvas = canvas.rect(fromScreen: captureScreen)

        view.refreshState()
        try button(Self.toolButtonLabel(tool), in: view).performClick(nil)

        let startCanvas = CGPoint(x: captureCanvas.midX, y: captureCanvas.midY)
        let outsideCanvas = CGPoint(x: captureCanvas.maxX + 40, y: captureCanvas.midY - 20)
        let startScreen = canvas.screenPoint(fromCanvas: startCanvas)
        let endScreen = canvas.screenPoint(fromCanvas: outsideCanvas)

        view.mouseDown(with: try mouse(.leftMouseDown, at: startScreen))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: endScreen))

        // Each tool exposes its own geometry, but the gesture must start inside
        // the frame and finish well past its edge.
        let draft = try #require(state.draftAnnotation)
        let draftBounds = AnnotationGeometry.paintedBounds(of: draft)
        #expect(draftBounds.minX < captureCanvas.maxX, "the draft starts inside the capture")
        #expect(draftBounds.maxX > captureCanvas.maxX + 10, "the draft finishes outside the capture")
        switch tool {
        case .arrow, .draw, .highlight:
            #expect(draft.pointsInCanvas.last == outsideCanvas)
        case .rectangle:
            #expect(draft.rectInCanvas?.maxX == outsideCanvas.x)
        case .text:
            break
        }

        view.mouseUp(with: try mouse(.leftMouseUp, at: endScreen))
        let committed = try #require(state.annotations.last)
        #expect(committed.id == draft.id)
        #expect(
            AnnotationGeometry.paintedBounds(of: committed) == draftBounds,
            "committing keeps the overflowing geometry"
        )
        #expect(AnnotationGeometry.paintedBounds(of: committed).maxX > captureCanvas.maxX)
        #expect(state.selectionRect == captureScreen, "the capture frame itself must not move")
    }

    @Test(arguments: AnnotationInteractionTests.drawingTools, AnnotationInteractionTests.DisplayEdge.allCases)
    func releaseOutsideTheDisplayClampsTheDraftToTheDisplayEdge(
        tool: OverlayAnnotationTool, edge: DisplayEdge
    ) throws {
        let (view, state) = try makeOverlay()
        let canvas = try #require(state.annotationCanvas)
        let display = try #require(state.captureDisplay)
        let displayCanvas = canvas.rect(fromScreen: display.frameInAppKitScreenSpace)
        #expect(displayCanvas == CGRect(x: 0, y: 0, width: 600, height: 500))

        // Explicit screen inputs and the geometry they must clamp to, per edge.
        let startScreen: CGPoint
        let dragScreen: CGPoint
        let releaseScreen: CGPoint
        let expectedStartCanvas: CGPoint
        let expectedEndCanvas: CGPoint
        let expectedRectangle: CGRect
        switch edge {
        case .right:
            startScreen = CGPoint(x: 200, y: 260)
            dragScreen = CGPoint(x: 450, y: 250)
            releaseScreen = CGPoint(x: 900, y: 220)
            expectedStartCanvas = CGPoint(x: 200, y: 240)
            expectedEndCanvas = CGPoint(x: displayCanvas.maxX, y: 280)
            expectedRectangle = CGRect(x: 200, y: 240, width: 400, height: 40)
        case .left:
            startScreen = CGPoint(x: 340, y: 260)
            dragScreen = CGPoint(x: 100, y: 250)
            releaseScreen = CGPoint(x: -300, y: 220)
            expectedStartCanvas = CGPoint(x: 340, y: 240)
            expectedEndCanvas = CGPoint(x: displayCanvas.minX, y: 280)
            expectedRectangle = CGRect(x: 0, y: 240, width: 340, height: 40)
        case .top:
            startScreen = CGPoint(x: 270, y: 200)
            dragScreen = CGPoint(x: 280, y: 400)
            releaseScreen = CGPoint(x: 300, y: 900)
            expectedStartCanvas = CGPoint(x: 270, y: 300)
            expectedEndCanvas = CGPoint(x: 300, y: displayCanvas.minY)
            expectedRectangle = CGRect(x: 270, y: 0, width: 30, height: 300)
        case .bottom:
            startScreen = CGPoint(x: 270, y: 240)
            dragScreen = CGPoint(x: 280, y: 60)
            releaseScreen = CGPoint(x: 300, y: -400)
            expectedStartCanvas = CGPoint(x: 270, y: 260)
            expectedEndCanvas = CGPoint(x: 300, y: displayCanvas.maxY)
            expectedRectangle = CGRect(x: 270, y: 260, width: 30, height: 240)
        }
        // The mouseup event is deliberately not the last drag event, so the
        // committed geometry must come from the release point, not the drag.
        #expect(releaseScreen != dragScreen)

        view.refreshState()
        try button(Self.toolButtonLabel(tool), in: view).performClick(nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: startScreen))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: dragScreen))
        view.mouseUp(with: try mouse(.leftMouseUp, at: releaseScreen))

        let committed = try #require(state.annotations.last)
        switch tool {
        case .rectangle:
            #expect(committed.rectInCanvas == expectedRectangle)
        case .arrow, .draw, .highlight:
            #expect(committed.pointsInCanvas.first == expectedStartCanvas)
            #expect(committed.pointsInCanvas.last == expectedEndCanvas)
        case .text:
            break
        }
    }

    @Test(arguments: AnnotationInteractionTests.drawingTools)
    func leavingAndReenteringTheDisplayKeepsOneDraftAndReturnsWithoutJumps(tool: OverlayAnnotationTool) throws {
        let (view, state) = try makeOverlay()
        let canvas = try #require(state.annotationCanvas)
        let display = try #require(state.captureDisplay)
        let displayCanvas = canvas.rect(fromScreen: display.frameInAppKitScreenSpace)

        let startCanvas = CGPoint(x: 270, y: 270)
        let leaveCanvas = CGPoint(x: displayCanvas.maxX, y: 300)
        let returnCanvas = CGPoint(x: 300, y: 220)
        let startScreen = canvas.screenPoint(fromCanvas: startCanvas)
        let leaveScreen = CGPoint(x: 2_000, y: 200)
        let returnScreen = canvas.screenPoint(fromCanvas: returnCanvas)

        view.refreshState()
        try button(Self.toolButtonLabel(tool), in: view).performClick(nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: startScreen))
        let draftID = try #require(state.draftAnnotation?.id)

        // The pointer leaves the display: still one draft, clamped to the edge.
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: leaveScreen))
        #expect(state.draftAnnotation?.id == draftID, "leaving the display must not start a new draft")
        switch tool {
        case .arrow:
            #expect(state.draftAnnotation?.pointsInCanvas == [startCanvas, leaveCanvas])
        case .rectangle:
            #expect(state.draftAnnotation?.rectInCanvas?.maxX == leaveCanvas.x)
        case .draw, .highlight:
            #expect(state.draftAnnotation?.pointsInCanvas.last == leaveCanvas)
        case .text:
            break
        }

        // Returning inside resumes the same gesture at the pointer, with no
        // residual edge offset.
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: returnScreen))
        #expect(state.draftAnnotation?.id == draftID)
        view.mouseUp(with: try mouse(.leftMouseUp, at: returnScreen))

        let committed = try #require(state.annotations.last)
        #expect(committed.id == draftID)
        switch tool {
        case .rectangle:
            #expect(committed.rectInCanvas == CGRect(x: 270, y: 220, width: 30, height: 50))
        case .arrow:
            #expect(committed.pointsInCanvas == [startCanvas, returnCanvas])
        case .draw, .highlight:
            #expect(committed.pointsInCanvas.first == startCanvas)
            #expect(committed.pointsInCanvas.last == returnCanvas)
        case .text:
            break
        }
    }

    @Test
    func newAnnotationsCannotStartOutsideTheCaptureFrame() throws {
        let (view, state) = try makeOverlay()
        view.refreshState()
        try button("Rectangle", in: view).performClick(nil)

        // (50, 50) is on the capture display but outside the capture frame.
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 90, y: 90)))
        view.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 90, y: 90)))

        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.isEmpty)
    }

    @Test
    func sessionCaptureDisplayCannotBeSwitchedEvenWithoutAnnotations() throws {
        let displayA = CGRect(x: 0, y: 0, width: 600, height: 500)
        let displayB = CGRect(x: 600, y: 0, width: 600, height: 500)
        let (view, state) = try makeOverlay(displays: [displayA, displayB])

        #expect(state.captureDisplay?.frameInAppKitScreenSpace == displayA)
        #expect(state.canInteract(atScreen: CGPoint(x: 300, y: 250)))
        #expect(!state.canInteract(atScreen: CGPoint(x: 700, y: 250)))

        // A replacement selection that is dragged onto the neighbouring display
        // stops at the capture display's edge.
        let before = try #require(state.selectionRect)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 700, y: 250)))
        view.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 700, y: 250)))

        let after = try #require(state.selectionRect)
        #expect(after != before)
        #expect(after.maxX <= displayA.maxX + 0.001)
        #expect(state.captureDisplay?.frameInAppKitScreenSpace == displayA)

        // A click on the other display is ignored entirely.
        let ignored = try #require(state.selectionRect)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 700, y: 250)))
        #expect(state.selectionRect == ignored)
    }

    // MARK: - Text commits once before selecting

    @Test
    func selectingAfterTextCommitsTheTextExactlyOnce() throws {
        let (view, state) = try makeOverlay()
        view.refreshState()
        try button("Text", in: view).performClick(nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 260)))
        let editor = try #require(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        editor.insertText("Once", replacementRange: NSRange(location: 0, length: 0))
        #expect(state.draftAnnotation != nil)

        try button("Select Annotations", in: view).performClick(nil)
        view.refreshState()

        #expect(state.annotations.count == 1)
        #expect(state.annotations.last?.text == "Once")
        #expect(state.draftAnnotation == nil)
        #expect(!view.subviews.contains { $0 is AnnotationTextEditor })
        #expect(state.interactionMode == .selectAnnotations)
        #expect(try button("Select Annotations", in: view).isActive)

        // The freshly committed text is immediately selectable.
        let text = try #require(state.annotations.last)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 260)))
        #expect(state.selectedAnnotationID == text.id)
    }

    @Test
    func liveTextEditorAtTheDisplayEdgeIsClippedByTheOverlayAndCommitsTheFullStringOnce() throws {
        // Detached overlay whose bounds are the owning display; nothing is
        // ordered onscreen and no window or desktop automation is involved.
        let (view, state) = try makeOverlay()
        let display = try #require(state.captureDisplay)
        let displayFrame = display.frameInAppKitScreenSpace
        #expect(view.bounds == CGRect(origin: .zero, size: displayFrame.size))
        // The editor grows past the capture frame but the owning view masks it.
        #expect(view.layer?.masksToBounds == true)

        // Park the capture frame at the display's right/bottom edge through the
        // real model, then commit the new crop.
        let initial = try #require(state.selectionRect)
        state.moveAnchoredSelection(
            from: initial,
            by: CGSize(width: displayFrame.maxX - initial.maxX, height: displayFrame.minY - initial.minY)
        )
        let moved = try #require(state.selectionRect)
        #expect(moved.maxX == displayFrame.maxX)
        #expect(moved.minY == displayFrame.minY)
        try state.setCapturedImageFromFrozenSnapshots(for: moved)

        view.refreshState()
        try button("Text", in: view).performClick(nil)
        let anchor = CGPoint(x: 560, y: 40)
        view.mouseDown(with: try mouse(.leftMouseDown, at: anchor))
        let editor = try #require(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        #expect(editor.superview === view)

        let draft = try #require(state.draftAnnotation)
        let creationBasis = draft.creationPixelSizeInCanvas
        #expect(creationBasis == CGSize(width: 1, height: 1))

        let longLine = String(repeating: "Wide ", count: 40)
        let fullString = longLine + "\n" + (1...10).map { "Line \($0)" }.joined(separator: "\n")
        editor.insertText(fullString, replacementRange: NSRange(location: 0, length: 0))

        // Unwrapped layout: the text keeps its newlines, never wraps, and spills
        // past both the right and bottom edges of the entire display.
        #expect(editor.string == fullString)
        #expect(editor.textContainer?.widthTracksTextView == false)
        #expect(editor.textContainer?.lineFragmentPadding == 0)
        #expect(editor.textContainerInset == .zero)
        #expect(editor.frame.maxX > displayFrame.maxX)
        #expect(editor.frame.minY < displayFrame.minY)
        // The anchor and the creation-time pixel basis never move.
        #expect(editor.frame.minX == anchor.x)
        #expect(editor.frame.maxY == anchor.y)
        #expect(state.draftAnnotation?.creationPixelSizeInCanvas == creationBasis)
        #expect(abs(editor.bounds.width * creationBasis.width - editor.frame.width) < 0.001)
        #expect(abs(editor.bounds.height * creationBasis.height - editor.frame.height) < 0.001)

        try button("Move", in: view).performClick(nil)
        #expect(state.annotations.count == 1)
        #expect(state.annotations.last?.text == fullString)
        #expect(state.annotations.last?.creationPixelSizeInCanvas == creationBasis)
        #expect(state.draftAnnotation == nil)
        #expect(!view.subviews.contains { $0 is AnnotationTextEditor })

        // A trailing end-editing notification must not commit a second copy.
        editor.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor))
        #expect(state.annotations.count == 1)
    }

    // MARK: - Helpers

    /// The four non-text drawing tools, driven through their real toolbar
    /// buttons. Text overflow is covered by the renderer and editor tests.
    nonisolated static let drawingTools: [OverlayAnnotationTool] = [.arrow, .rectangle, .draw, .highlight]

    /// The four display edges a live gesture can be clamped against.
    enum DisplayEdge: CaseIterable {
        case left
        case right
        case top
        case bottom
    }

    private static func toolButtonLabel(_ tool: OverlayAnnotationTool) -> String {
        switch tool {
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .draw: return "Draw"
        case .highlight: return "Highlight"
        case .text: return "Text"
        }
    }

    private func snapshot(frame: CGRect, scaleX: Int = 1) throws -> DisplaySnapshot {
        let width = Int(frame.width) * scaleX
        let height = Int(frame.height)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let display = DisplayGeometry(
            localizedName: "Synthetic", frameInDisplaySpace: frame,
            frameInAppKitScreenSpace: frame, backingScaleFactor: CGFloat(scaleX)
        )
        return DisplaySnapshot(display: display, image: image)
    }

    private func overlay(
        _ state: RegionSelectionState,
        close: @escaping () -> Void = {},
        copy: @escaping (Data) -> Void = { _ in },
        save: @escaping (Data) -> Void = { _ in },
        selectionCompleted: @escaping (CGRect) -> Void = { _ in }
    ) -> RegionCaptureOverlayView {
        RegionCaptureOverlayView(
            frame: CGRect(x: 0, y: 0, width: 600, height: 500), selectionState: state,
            close: close, copy: copy, save: save, selectionCompleted: selectionCompleted,
            defaultAnnotationColor: .red, defaultAnnotationStrokeWidth: 2, refresh: {}
        )
    }

    /// Builds a state with a committed `(150, 140, 240, 180)` selection on the
    /// first display, driven through the real overlay selection flow so the
    /// session capture display is chosen the way the app chooses it.
    private func makeOverlay(
        scaleX: Int = 1,
        displays: [CGRect] = [CGRect(x: 0, y: 0, width: 600, height: 500)],
        close: @escaping () -> Void = {},
        copy: @escaping (Data) -> Void = { _ in },
        save: @escaping (Data) -> Void = { _ in }
    ) throws -> (RegionCaptureOverlayView, RegionSelectionState) {
        // The Select-mode paths call NSCursor.set(); make sure an app exists.
        _ = NSApplication.shared
        let state = RegionSelectionState(snapshots: try displays.map { try snapshot(frame: $0, scaleX: scaleX) })
        let view = overlay(
            state, close: close, copy: copy, save: save,
            selectionCompleted: { rect in try? state.setCapturedImageFromFrozenSnapshots(for: rect) }
        )
        let start = CGPoint(x: 150, y: 140)
        let end = CGPoint(x: 390, y: 320)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: try mouse(.leftMouseUp, at: end))
        #expect(state.capturedImage != nil)
        return (view, state)
    }

    /// A mark that starts inside the capture frame and ends outside it, but
    /// still on the capture display.
    @discardableResult
    private func addOffCaptureMark(_ tool: OverlayAnnotationTool, to state: RegionSelectionState) throws -> OverlayAnnotation {
        state.beginAnnotation(tool: tool, at: CGPoint(x: 350, y: 300), color: .red, lineWidth: 4)
        if tool == .text {
            state.updateDraftText("Overflow")
            state.commitDraftText()
        } else {
            state.updateAnnotation(to: CGPoint(x: 450, y: 250))
            state.commitAnnotation()
        }
        return try #require(state.annotations.last)
    }

    private func annotationHitPoint(_ mark: OverlayAnnotation, in state: RegionSelectionState) throws -> CGPoint {
        let canvas = try #require(state.annotationCanvas)
        let point: CGPoint
        switch mark.kind {
        case .rectangle:
            let rect = try #require(mark.rectInCanvas)
            point = CGPoint(x: rect.midX, y: rect.minY)
        case .text:
            point = try #require(mark.textPositionInCanvas)
        case .arrow, .draw, .highlight:
            point = try #require(mark.pointsInCanvas.first)
        }
        return canvas.screenPoint(fromCanvas: point)
    }

    private func dragTarget(fromScreen start: CGPoint, canvasDelta: CGSize, in state: RegionSelectionState) throws -> CGPoint {
        let canvas = try #require(state.annotationCanvas)
        let begin = canvas.point(fromScreen: start)
        return canvas.screenPoint(fromCanvas: CGPoint(x: begin.x + canvasDelta.width, y: begin.y + canvasDelta.height))
    }

    private func expectSameGeometry(_ actual: OverlayAnnotation, _ expected: OverlayAnnotation) {
        #expect(actual.id == expected.id)
        #expect(actual.kind == expected.kind)
        #expect(actual.rectInCanvas == expected.rectInCanvas)
        #expect(actual.pointsInCanvas == expected.pointsInCanvas)
        #expect(actual.textPositionInCanvas == expected.textPositionInCanvas)
        #expect(actual.text == expected.text)
        #expect(actual.color == expected.color)
        #expect(actual.lineWidth == expected.lineWidth)
        #expect(actual.fontSize == expected.fontSize)
        #expect(actual.minimumArrowheadLength == expected.minimumArrowheadLength)
        #expect(actual.creationPixelSizeInCanvas == expected.creationPixelSizeInCanvas)
        #expect(actual.displayID == expected.displayID)
        #expect(actual.displayFrameInAppKitScreenSpace == expected.displayFrameInAppKitScreenSpace)
    }

    private func triggerExport(_ path: String, in view: RegionCaptureOverlayView) throws {
        switch path {
        case "c":
            view.keyDown(with: try command("c", keyCode: 8))
        case "s":
            view.keyDown(with: try command("s", keyCode: 1))
        default:
            try button(path, in: view).performClick(nil)
        }
    }

    private func button(_ label: String, in view: RegionCaptureOverlayView) throws -> SolidActionButton {
        try #require(view.subviews.compactMap { $0 as? SolidActionButton }.first { $0.accessibilityLabel() == label })
    }

    private func escape() throws -> NSEvent {
        try key("\u{1b}", keyCode: 53)
    }

    private func key(_ character: String, keyCode: UInt16, windowNumber: Int = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode
        ))
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
    }

    private func command(_ character: String, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode
        ))
    }
}
