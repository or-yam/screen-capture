import AppKit
import Testing
@testable import ScreenCaptureAll

/// Model-level coverage for the capture-display lock and annotation
/// selection / translation transaction in `RegionSelectionState`.
@MainActor
struct AnnotationSelectionMoveStateTests {

    // MARK: - Capture display lock

    @Test
    func canInteractSpansSnapshotsBeforeADisplayIsChosenAndLocksAfterwards() throws {
        let left = CGRect(x: -300, y: -200, width: 300, height: 200)
        let right = CGRect(x: 0, y: -200, width: 300, height: 200)
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: left, density: 2),
            try snapshot(frame: right, density: 1)
        ])

        #expect(state.captureDisplay == nil)
        #expect(state.canInteract(atScreen: CGPoint(x: -100, y: -100)))
        #expect(state.canInteract(atScreen: CGPoint(x: 100, y: -100)))
        #expect(!state.canInteract(atScreen: CGPoint(x: -100, y: 100)))

        state.beginSelection(at: CGPoint(x: 150, y: -50))
        #expect(state.captureDisplay?.frameInAppKitScreenSpace == right)
        #expect(state.canInteract(atScreen: CGPoint(x: 150, y: -100)))
        // The left display is now inert even though it was selectable before.
        #expect(!state.canInteract(atScreen: CGPoint(x: -100, y: -100)))

        // Points on the other display clamp to the capture display's edge.
        #expect(state.clampedScreenPoint(CGPoint(x: -100, y: -100)) == CGPoint(x: 0, y: -100))
        #expect(state.clampedScreenPoint(CGPoint(x: 900, y: -900)) == CGPoint(x: 300, y: -200))
    }

    @Test
    func initialSelectionAndReselectionStayOnTheLockedCaptureDisplay() throws {
        let left = CGRect(x: -300, y: -200, width: 300, height: 200)
        let right = CGRect(x: 0, y: -200, width: 300, height: 200)
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: left, density: 2),
            try snapshot(frame: right, density: 1)
        ])

        state.beginSelection(at: CGPoint(x: 150, y: -50))
        state.updateSelection(to: CGPoint(x: -100, y: -150))
        state.anchorSelection(at: CGPoint(x: -100, y: -150))
        let rect = try #require(state.selectionRect)
        #expect(rect.minX == 0)
        #expect(rect.maxX == 150)

        // A replacement selection started on the other display cannot move it.
        state.beginSelection(at: CGPoint(x: -100, y: -100))
        #expect(state.captureDisplay?.frameInAppKitScreenSpace == right)
        #expect(state.selectionRect == rect)
    }

    @Test
    func newAnnotationMustStartInsideTheSelectionAndOnTheCaptureDisplay() throws {
        let left = CGRect(x: -300, y: -200, width: 300, height: 200)
        let right = CGRect(x: 0, y: -200, width: 300, height: 200)
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: left, density: 2),
            try snapshot(frame: right, density: 1)
        ])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 50, y: -150, width: 200, height: 100))
        #expect(state.captureDisplay?.frameInAppKitScreenSpace == right)
        let canvas = try #require(state.annotationCanvas)

        // Start on the left display: rejected, even though the canvas includes it.
        state.beginAnnotation(tool: .arrow, at: canvas.point(fromScreen: CGPoint(x: -100, y: -100)), color: .red, lineWidth: 4)
        #expect(state.draftAnnotation == nil)

        // Start on the capture display but outside the capture frame: rejected.
        state.beginAnnotation(tool: .arrow, at: canvas.point(fromScreen: CGPoint(x: 10, y: -10)), color: .red, lineWidth: 4)
        #expect(state.draftAnnotation == nil)

        // Start inside both: accepted, and the mark records the capture display.
        state.beginAnnotation(tool: .arrow, at: canvas.point(fromScreen: CGPoint(x: 100, y: -100)), color: .red, lineWidth: 4)
        #expect(state.draftAnnotation != nil)
    }

    @Test
    func annotationsInheritTheCaptureDisplayFrameAndID() throws {
        let displayFrame = CGRect(x: 0, y: 0, width: 400, height: 300)
        var source = try snapshot(frame: displayFrame, density: 2)
        source.display.id = 42
        let state = RegionSelectionState(snapshots: [source])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 100, y: 100, width: 200, height: 150))
        let mark = try create(.arrow, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        #expect(mark.displayFrameInAppKitScreenSpace == displayFrame)
        #expect(mark.displayID == 42)
    }

    // MARK: - Selection

    @Test
    func selectAnnotationPicksTopmostAndEmptySpaceDeselects() throws {
        let state = try capturedState()
        let bottom = try create(.rectangle, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let top = try create(.rectangle, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))

        // Both edges overlap; the later (topmost) mark wins.
        state.selectAnnotation(at: CGPoint(x: 250, y: 125))
        #expect(state.selectedAnnotationID == top.id)
        #expect(state.selectedAnnotationID != bottom.id)

        // A rectangle's empty interior is not painted ink.
        state.selectAnnotation(at: CGPoint(x: 200, y: 125))
        #expect(state.selectedAnnotationID == nil)
    }

    // MARK: - Translation

    @Test(arguments: OverlayAnnotationTool.allCases, AnnotationDensityTests.densities)
    func moveAllToolsTransactsFromTheOriginalAndRestoresOnUndo(
        tool: OverlayAnnotationTool, density: AnnotationDensityTests.Density
    ) throws {
        let state = try capturedState(densityX: density.x, densityY: density.y)
        let original = try create(tool, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let grab = hitPoint(for: tool)

        state.beginAnnotationMove(at: grab)
        #expect(state.annotationMoveIsActive)
        #expect(state.selectedAnnotationID == original.id)

        let delta = CGSize(width: 30, height: 20)
        // Many incremental updates still equal one translation from the original.
        state.updateAnnotationMove(to: CGPoint(x: grab.x + 10, y: grab.y + 5))
        state.updateAnnotationMove(to: CGPoint(x: grab.x + delta.width, y: grab.y + delta.height))

        let preview = try #require(state.previewAnnotations.last)
        expectTranslated(preview, original, by: delta)
        // Committed geometry is untouched until the move commits.
        expectSameAnnotation(try #require(state.annotations.last), original)

        state.commitAnnotationMove()
        #expect(!state.annotationMoveIsActive)
        expectTranslated(try #require(state.annotations.last), original, by: delta)
        expectSameAnnotations(state.previewAnnotations, state.annotations)

        // Undo restores the original position but keeps identity and style.
        state.undoLastAnnotation()
        expectSameAnnotation(try #require(state.annotations.last), original)
    }

    @Test
    func undoAppliesCreateAndTranslationActionsInOrder() throws {
        let state = try capturedState()
        let a = try create(.arrow, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let grab = hitPoint(for: .arrow)
        let delta = CGSize(width: 20, height: 15)
        state.beginAnnotationMove(at: grab)
        state.updateAnnotationMove(to: CGPoint(x: grab.x + delta.width, y: grab.y + delta.height))
        state.commitAnnotationMove()
        expectTranslated(try #require(state.annotations.first), a, by: delta)

        let b = try create(.rectangle, in: state, from: CGPoint(x: 160, y: 110), to: CGPoint(x: 240, y: 170))
        #expect(state.annotations.map(\.id) == [a.id, b.id])

        state.undoLastAnnotation()
        #expect(state.annotations.map(\.id) == [a.id])

        state.undoLastAnnotation()
        expectSameAnnotation(try #require(state.annotations.first), a)

        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
    }

    @Test
    func cancelRevertsUnfinishedMoveAndClearSelectionCancelsIt() throws {
        let state = try capturedState()
        let original = try create(.arrow, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let grab = hitPoint(for: .arrow)

        state.beginAnnotationMove(at: grab)
        state.updateAnnotationMove(to: CGPoint(x: grab.x + 40, y: grab.y + 30))
        expectTranslated(try #require(state.previewAnnotations.last), original, by: CGSize(width: 40, height: 30))
        state.cancelAnnotationMove()
        #expect(!state.annotationMoveIsActive)
        #expect(state.selectedAnnotationID == original.id)
        expectSameAnnotations(state.previewAnnotations, state.annotations)
        expectSameAnnotation(try #require(state.annotations.last), original)

        state.beginAnnotationMove(at: grab)
        state.updateAnnotationMove(to: CGPoint(x: grab.x + 40, y: grab.y + 30))
        state.clearAnnotationSelection()
        #expect(state.selectedAnnotationID == nil)
        #expect(!state.annotationMoveIsActive)
        expectSameAnnotations(state.previewAnnotations, state.annotations)
        expectSameAnnotation(try #require(state.annotations.last), original)
    }

    @Test
    func zeroDeltaClickDoesNotMoveOrRecordHistory() throws {
        let state = try capturedState()
        let original = try create(.text, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 200, y: 130), text: "Move me")

        let grab = textHitPoint
        state.beginAnnotationMove(at: grab)
        state.updateAnnotationMove(to: grab)
        state.commitAnnotationMove()
        expectSameAnnotation(try #require(state.annotations.last), original)

        // The only history entry is the creation, so undo removes the mark.
        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
    }

    @Test
    func sharedModeChangeCancelsAnUnfinishedMove() throws {
        let state = try capturedState()
        let original = try create(.draw, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        state.interactionMode = .selectAnnotations
        state.beginAnnotationMove(at: CGPoint(x: 200, y: 125))
        state.updateAnnotationMove(to: CGPoint(x: 220, y: 145))
        state.interactionMode = .draw(.arrow)
        #expect(!state.annotationMoveIsActive)
        #expect(state.selectedAnnotationID == nil)
        expectSameAnnotation(try #require(state.previewAnnotations.first), original)
        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
    }

    @Test
    func draggingFartherPastAClampedEdgeAddsNoUndoAction() throws {
        let state = try capturedState()
        let original = try create(.draw, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        state.beginAnnotationMove(at: CGPoint(x: 200, y: 125))
        state.updateAnnotationMove(to: CGPoint(x: 1200, y: 125))
        state.commitAnnotationMove()
        let atEdge = try #require(state.annotations.first)
        #expect(abs(try #require(atEdge.pointsInCanvas.last).x - 399) < 0.001)
        let grab = try #require(atEdge.pointsInCanvas.first)
        state.beginAnnotationMove(at: grab)
        state.updateAnnotationMove(to: CGPoint(x: grab.x + 100, y: grab.y))
        state.commitAnnotationMove()
        expectSameAnnotation(try #require(state.annotations.first), atEdge)
        state.undoLastAnnotation()
        expectSameAnnotation(try #require(state.annotations.first), original)
        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
    }

    @Test
    func moveIsClampedToTheCaptureDisplayAtEveryEdge() throws {
        let displayFrame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let state = try capturedState(displayFrame: displayFrame)
        let original = try create(.arrow, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let bounds = try #require(state.annotationCanvas).rect(fromScreen: displayFrame)
        let grab = hitPoint(for: .arrow)

        var didMove = false
        for target in [CGPoint(x: 5_000, y: 1_000), CGPoint(x: -5_000, y: -1_000), CGPoint(x: 5_000, y: -1_000)] {
            state.beginAnnotationMove(at: grab)
            state.updateAnnotationMove(to: target)
            let moved = try #require(state.previewAnnotations.last)
            for point in moved.pointsInCanvas {
                #expect(point.x >= bounds.minX - 0.5 && point.x <= bounds.maxX + 0.5)
                #expect(point.y >= bounds.minY - 0.5 && point.y <= bounds.maxY + 0.5)
            }
            if moved.pointsInCanvas != original.pointsInCanvas { didMove = true }
            state.cancelAnnotationMove()
            expectSameAnnotation(try #require(state.annotations.last), original)
        }
        #expect(didMove)
    }

    @Test
    func oversizedTextClampsItsAnchorAndAZeroDeltaClickIsANoOp() throws {
        let displayFrame = CGRect(x: -400, y: -300, width: 400, height: 300)
        let state = try capturedState(displayFrame: displayFrame)
        let longLine = String(repeating: "W", count: 300)
        let original = try create(.text, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 200, y: 130), text: longLine)
        #expect(original.text == longLine)

        // A click on clipped text must not correct it.
        state.beginAnnotationMove(at: textHitPoint)
        state.updateAnnotationMove(to: textHitPoint)
        state.commitAnnotationMove()
        expectSameAnnotation(try #require(state.annotations.last), original)

        let bounds = try #require(state.annotationCanvas).rect(fromScreen: displayFrame)
        state.beginAnnotationMove(at: textHitPoint)
        state.updateAnnotationMove(to: CGPoint(x: textHitPoint.x + 5_000, y: textHitPoint.y + 5_000))
        let anchor = try #require(state.previewAnnotations.last?.textPositionInCanvas)
        #expect(anchor.x <= bounds.maxX + 0.5)
        #expect(anchor.y <= bounds.maxY + 0.5)
        state.commitAnnotationMove()
        state.undoLastAnnotation()
        expectSameAnnotation(try #require(state.annotations.last), original)
    }

    @Test
    func verticalLayoutsAndAnisotropicDensitiesTranslateByPointerDelta() throws {
        // Displays stacked vertically; the capture display is the top one.
        let bottom = CGRect(x: 0, y: 0, width: 400, height: 300)
        let top = CGRect(x: 0, y: 300, width: 400, height: 300)
        let vertical = RegionSelectionState(snapshots: [
            try snapshot(frame: bottom, density: 2),
            try snapshot(frame: top, density: 1)
        ])
        vertical.beginSelection(at: CGPoint(x: 100, y: 400))
        #expect(vertical.captureDisplay?.frameInAppKitScreenSpace == top)
        #expect(!vertical.canInteract(atScreen: CGPoint(x: 100, y: 100)))
        #expect(vertical.clampedScreenPoint(CGPoint(x: 100, y: 100)) == CGPoint(x: 100, y: 300))

        // Anisotropic density must not distort a screen-point translation.
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let state = try capturedState(displayFrame: frame, densityX: 2, densityY: 1.5)
        let original = try create(.draw, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let delta = CGSize(width: 12, height: 9)
        state.beginAnnotationMove(at: CGPoint(x: 200, y: 125))
        state.updateAnnotationMove(to: CGPoint(x: 200 + delta.width, y: 125 + delta.height))
        state.commitAnnotationMove()
        expectTranslated(try #require(state.annotations.last), original, by: delta)
    }

    @Test
    func resetClearsSelectionMoveStateAndHistory() throws {
        let state = try capturedState()
        _ = try create(.arrow, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        state.beginAnnotationMove(at: hitPoint(for: .arrow))
        state.updateAnnotationMove(to: CGPoint(x: 220, y: 160))

        state.reset()
        #expect(state.annotations.isEmpty)
        #expect(state.selectedAnnotationID == nil)
        #expect(!state.annotationMoveIsActive)
        #expect(state.previewAnnotations.isEmpty)
        #expect(state.captureDisplay == nil)
        #expect(state.interactionMode == .moveCapture)
        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
    }

    @Test
    func cropCannotSwitchToAnotherDisplayOrReplaceCommittedPixels() throws {
        let first = CGRect(x: -300, y: 0, width: 300, height: 200)
        let second = CGRect(x: 0, y: 0, width: 300, height: 200)
        let state = RegionSelectionState(snapshots: [try snapshot(frame: first, density: 1), try snapshot(frame: second, density: 2)])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: -250, y: 50, width: 100, height: 100))
        let image = try #require(state.capturedImage)
        let frame = state.capturedSelectionRect
        #expect(throws: ScreenshotCaptureError.self) {
            try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 50, y: 50, width: 100, height: 100))
        }
        #expect(state.capturedImage === image)
        #expect(state.capturedSelectionRect == frame)
        #expect(state.selectionRect == frame)
        #expect(state.captureDisplay?.frameInAppKitScreenSpace == first)
    }

    @Test(arguments: RegionSelectionResizeHandle.allCases)
    func tinyCaptureAtScreenCornersNeverResizesOutsideTheScreen(handle: RegionSelectionResizeHandle) throws {
        let display = CGRect(x: -400, y: -300, width: 400, height: 300)
        let source = try snapshot(frame: display, density: 2)
        for origin in [CGPoint(x: -400, y: -300), CGPoint(x: -1, y: -300), CGPoint(x: -400, y: -1), CGPoint(x: -1, y: -1)] {
            let state = RegionSelectionState(snapshots: [source])
            try state.setCapturedImageFromFrozenSnapshots(for: CGRect(origin: origin, size: CGSize(width: 1, height: 1)))
            let original = try #require(state.selectionRect)
            for target in [CGPoint(x: -1000, y: -1000), CGPoint(x: 1000, y: 1000)] {
                state.resizeAnchoredSelection(from: original, dragging: handle, to: target)
                let resized = try #require(state.selectionRect)
                #expect(display.contains(resized))
                #expect(resized.width > 0 && resized.height > 0)
            }
        }
    }

    @Test
    func reselectionCannotEraseExistingInkOrItsUndoHistory() throws {
        let state = try capturedState()
        let original = try create(.draw, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        let frame = state.selectionRect
        state.beginSelection(at: CGPoint(x: 20, y: 20))
        #expect(state.selectionRect == frame)
        expectSameAnnotation(try #require(state.annotations.first), original)
        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
    }

    @Test
    func repeatedMovesUndoIndividuallyAndFrameChangesDoNotEnterHistory() throws {
        let state = try capturedState()
        let original = try create(.draw, in: state, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 150))
        state.beginAnnotationMove(at: CGPoint(x: 200, y: 125))
        state.updateAnnotationMove(to: CGPoint(x: 210, y: 135))
        state.commitAnnotationMove()
        let firstMove = try #require(state.annotations.first)
        state.beginAnnotationMove(at: CGPoint(x: 210, y: 135))
        state.updateAnnotationMove(to: CGPoint(x: 220, y: 145))
        state.commitAnnotationMove()
        let frame = try #require(state.selectionRect)
        state.moveAnchoredSelection(from: frame, by: CGSize(width: 20, height: 0))
        let movedFrame = try #require(state.selectionRect)
        state.resizeAnchoredSelection(from: movedFrame, dragging: .topRight, to: CGPoint(x: movedFrame.maxX + 10, y: movedFrame.maxY + 10))
        let resizedFrame = state.selectionRect
        state.undoLastAnnotation()
        expectSameAnnotation(try #require(state.annotations.first), firstMove)
        state.undoLastAnnotation()
        expectSameAnnotation(try #require(state.annotations.first), original)
        #expect(state.selectionRect == resizedFrame)
        state.undoLastAnnotation()
        #expect(state.annotations.isEmpty)
        #expect(state.selectedAnnotationID == nil)
    }

    // MARK: - Helpers

    private var textHitPoint: CGPoint { CGPoint(x: 152, y: 103) }

    private func hitPoint(for tool: OverlayAnnotationTool) -> CGPoint {
        switch tool {
        case .arrow, .draw, .highlight:
            return CGPoint(x: 200, y: 125)
        case .rectangle:
            return CGPoint(x: 250, y: 125)
        case .text:
            return textHitPoint
        }
    }

    private func capturedState(
        displayFrame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300),
        densityX: CGFloat = 2,
        densityY: CGFloat? = nil
    ) throws -> RegionSelectionState {
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: displayFrame, density: densityX, densityY: densityY)
        ])
        let selection = CGRect(
            x: displayFrame.minX + displayFrame.width / 4,
            y: displayFrame.minY + displayFrame.height / 3,
            width: displayFrame.width / 2,
            height: displayFrame.height / 2
        )
        try state.setCapturedImageFromFrozenSnapshots(for: selection)
        return state
    }

    @discardableResult
    private func create(
        _ tool: OverlayAnnotationTool,
        in state: RegionSelectionState,
        from start: CGPoint,
        to end: CGPoint,
        text: String = "Hi"
    ) throws -> OverlayAnnotation {
        state.beginAnnotation(tool: tool, at: start, color: .red, lineWidth: 4, fontSize: 18)
        if tool == .text {
            state.updateDraftText(text)
            state.commitDraftText()
        } else {
            state.updateAnnotation(to: end)
            state.commitAnnotation()
        }
        return try #require(state.annotations.last)
    }

    private func snapshot(frame: CGRect, density: CGFloat, densityY: CGFloat? = nil) throws -> DisplaySnapshot {
        let width = Int((frame.width * density).rounded())
        let height = Int((frame.height * (densityY ?? density)).rounded())
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let display = DisplayGeometry(
            localizedName: "Synthetic", frameInDisplaySpace: frame,
            frameInAppKitScreenSpace: frame, backingScaleFactor: density
        )
        return DisplaySnapshot(display: display, image: try #require(context.makeImage()))
    }

    private func expectTranslated(_ actual: OverlayAnnotation, _ original: OverlayAnnotation, by delta: CGSize) {
        #expect(actual.id == original.id)
        #expect(actual.kind == original.kind)
        if let rect = original.rectInCanvas {
            #expect(actual.rectInCanvas == rect.offsetBy(dx: delta.width, dy: delta.height))
        }
        if !original.pointsInCanvas.isEmpty {
            #expect(actual.pointsInCanvas == original.pointsInCanvas.map {
                CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
            })
        }
        if let position = original.textPositionInCanvas {
            #expect(actual.textPositionInCanvas == CGPoint(x: position.x + delta.width, y: position.y + delta.height))
        }
        #expect(actual.text == original.text)
        #expect(actual.lineWidth == original.lineWidth)
        #expect(actual.fontSize == original.fontSize)
        #expect(actual.creationPixelSizeInCanvas == original.creationPixelSizeInCanvas)
        #expect(actual.displayFrameInAppKitScreenSpace == original.displayFrameInAppKitScreenSpace)
    }

    private func expectSameAnnotations(_ lhs: [OverlayAnnotation], _ rhs: [OverlayAnnotation]) {
        #expect(lhs.count == rhs.count)
        for (actual, expected) in zip(lhs, rhs) {
            expectSameAnnotation(actual, expected)
        }
    }

    private func expectSameAnnotation(_ actual: OverlayAnnotation, _ expected: OverlayAnnotation) {
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
}
