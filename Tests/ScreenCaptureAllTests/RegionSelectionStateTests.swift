import AppKit
import Testing
@testable import ScreenCaptureAll

@MainActor
struct RegionSelectionStateTests {
    @Test
    func canvasUsesFrozenDisplayUnionBeforeThereIsASelection() throws {
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: CGRect(x: -240, y: -80, width: 240, height: 180), density: 1),
            try snapshot(frame: CGRect(x: 0, y: 20, width: 240, height: 180), density: 2)
        ])
        let canvas = try #require(state.annotationCanvas)
        #expect(canvas.point(fromScreen: CGPoint(x: -240, y: 200)) == .zero)
        #expect(canvas.point(fromScreen: CGPoint(x: 30, y: -20)) == CGPoint(x: 270, y: 220))
        #expect(canvas.screenPoint(fromCanvas: CGPoint(x: 270, y: 220)) == CGPoint(x: 30, y: -20))
        #expect(state.selectionRect == nil)
        #expect(state.capturedSelectionRect == nil)
        #expect(state.capturedImage == nil)
        #expect(RegionSelectionState().annotationCanvas == nil)
    }

    @Test(arguments: OverlayAnnotationTool.allCases, RegionSelectionResizeHandle.allCases)
    func everyHandlePreservesCanvasMarksAndCommitsAlignedBounds(
        tool: OverlayAnnotationTool,
        handle: RegionSelectionResizeHandle
    ) throws {
        let density: CGFloat = 5 / 3
        let state = try selection(density: density)
        let original = try #require(state.selectionRect)
        let committedImage = try #require(state.capturedImage)
        let committedPNG = try #require(state.capturedPNG)
        let canvas = try #require(state.annotationCanvas)
        try addAnnotation(tool, to: state)
        let mark = try #require(state.annotations.first)
        assertOriginalContentLocation(mark, tool: tool)

        let requested = expandedRect(original, handle: handle)
        state.resizeAnchoredSelection(from: original, dragging: handle, to: resizePoint(original, handle: handle))
        #expect(state.selectionRect == requested)
        #expect(state.capturedSelectionRect == original)
        #expect(state.capturedImage === committedImage)
        #expect(state.capturedPNG == committedPNG)
        #expect(state.annotations.count == 1)
        expectUnchanged(try #require(state.annotations.first), mark)

        try state.setCapturedImageFromFrozenSnapshots(for: requested)
        let aligned = alignedRect(requested, density: density)
        expectRect(try #require(state.selectionRect), aligned)
        expectRect(try #require(state.capturedSelectionRect), aligned)
        let image = try #require(state.capturedImage)
        #expect(image.width == Int((aligned.width * density).rounded()))
        #expect(image.height == Int((aligned.height * density).rounded()))
        #expect(state.annotations.count == 1)
        expectUnchanged(try #require(state.annotations.first), mark)
        #expect(state.annotationCanvas?.frameInAppKitScreenSpace == canvas.frameInAppKitScreenSpace)
        #expect(try #require(state.annotationCanvas).point(fromScreen: CGPoint(x: 50, y: 100))
            == canvas.point(fromScreen: CGPoint(x: 50, y: 100)))

        // Recropping aligned bounds must not grow by another source pixel.
        for _ in 0..<5 {
            try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
            expectRect(try #require(state.capturedSelectionRect), aligned)
            #expect(state.capturedImage?.width == image.width)
            #expect(state.capturedImage?.height == image.height)
            expectUnchanged(try #require(state.annotations.first), mark)
        }
    }

    @Test(arguments: OverlayAnnotationTool.allCases)
    func partialAndFullExclusionRetainCompleteGeometryAndUndoHiddenMarkOnly(tool: OverlayAnnotationTool) throws {
        let state = try selection()
        let original = try #require(state.selectionRect)
        try addAnnotation(.rectangle, to: state)
        try addAnnotation(tool, to: state)
        let marks = state.annotations
        #expect(marks.count == 2)

        state.resizeAnchoredSelection(from: original, dragging: .right, to: CGPoint(x: 75, y: 72))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        for (actual, expected) in zip(state.annotations, marks) { expectUnchanged(actual, expected) }

        // Restore, then exclude both marks entirely (all their X coordinates are 50...100).
        try state.setCapturedImageFromFrozenSnapshots(for: original)
        state.resizeAnchoredSelection(from: original, dragging: .left, to: CGPoint(x: 120, y: 72))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(state.hasCommittedOrDraftAnnotations)
        #expect(state.annotations.map(\.id) == marks.map(\.id))
        let hiddenFrame = try #require(state.selectionRect)
        let hiddenImage = try #require(state.capturedImage)
        let hiddenPNG = state.capturedPNG
        state.undoLastAnnotation()
        #expect(state.annotations.map(\.id) == [marks[0].id])
        #expect(state.selectionRect == hiddenFrame)
        #expect(state.capturedSelectionRect == hiddenFrame)
        #expect(state.capturedImage === hiddenImage)
        #expect(state.capturedPNG == hiddenPNG)

        state.resizeAnchoredSelection(from: hiddenFrame, dragging: .left, to: original.origin)
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(state.selectionRect == original)
        expectUnchanged(try #require(state.annotations.first), marks[0])
        state.undoLastAnnotation()
        #expect(!state.hasCommittedOrDraftAnnotations)
        #expect(state.selectionRect == original)
    }

    @Test(arguments: OverlayAnnotationTool.allCases)
    func movingAwayAndBackAndRepeatedFractionalMovesDoNotCarryOrGrowMarks(tool: OverlayAnnotationTool) throws {
        let state = try selection(density: 5 / 3)
        let original = try #require(state.selectionRect)
        try addAnnotation(tool, to: state)
        let mark = try #require(state.annotations.first)
        state.moveAnchoredSelection(from: original, by: CGSize(width: 180, height: 0))
        let away = try #require(state.selectionRect)
        #expect(away.minX == 180)
        #expect(state.capturedSelectionRect == original)
        try state.setCapturedImageFromFrozenSnapshots(for: away)
        expectUnchanged(try #require(state.annotations.first), mark)
        state.moveAnchoredSelection(from: away, by: CGSize(width: -180, height: 0))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        expectRect(try #require(state.selectionRect), original)

        let width = state.capturedImage?.width
        let height = state.capturedImage?.height
        for _ in 0..<12 {
            state.moveAnchoredSelection(from: try #require(state.selectionRect), by: CGSize(width: 0.37, height: 0.37))
            try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
            state.moveAnchoredSelection(from: try #require(state.selectionRect), by: CGSize(width: -0.37, height: -0.37))
            try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
            expectRect(try #require(state.selectionRect), original)
            #expect(state.capturedImage?.width == width)
            #expect(state.capturedImage?.height == height)
            expectUnchanged(try #require(state.annotations.first), mark)
        }
    }

    @Test(arguments: OverlayAnnotationTool.allCases)
    func marksCreatedAfterMoveAndResizeUseTheOriginalCanvas(tool: OverlayAnnotationTool) throws {
        let state = try selection(density: 2)
        try addAnnotation(tool, to: state)
        let original = try #require(state.annotations.first)
        state.moveAnchoredSelection(from: try #require(state.selectionRect), by: CGSize(width: 20, height: 12))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        state.resizeAnchoredSelection(
            from: try #require(state.selectionRect), dragging: .topRight, to: CGPoint(x: 240, y: 210)
        )
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        try addAnnotation(tool, to: state)
        let added = try #require(state.annotations.last)
        assertOriginalContentLocation(added, tool: tool)
        #expect(added.id != original.id)
        #expect(added.rectInCanvas == original.rectInCanvas)
        #expect(added.pointsInCanvas == original.pointsInCanvas)
        #expect(added.textPositionInCanvas == original.textPositionInCanvas)
        #expect(added.lineWidth == original.lineWidth)
        #expect(added.fontSize == original.fontSize)
        expectUnchanged(try #require(state.annotations.first), original)
    }

    @Test(arguments: [1.0, 2.0, 5.0 / 3.0])
    func mixedDensityCommitPreservesOldSizesAndConvertsNewPixelToolSettings(density: Double) throws {
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: CGRect(x: -240, y: 0, width: 240, height: 180), density: 1),
            try snapshot(frame: CGRect(x: 0, y: 0, width: 240, height: 180), density: density)
        ])
        // Start near the right edge of the left display and grow within it.
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: -220, y: 20, width: 20, height: 120))
        for tool in OverlayAnnotationTool.allCases {
            try addAnnotation(tool, to: state, start: CGPoint(x: -180, y: 100), end: CGPoint(x: -130, y: 70))
        }
        let oldMarks = state.annotations
        let original = try #require(state.selectionRect)
        state.resizeAnchoredSelection(from: original, dragging: .right, to: CGPoint(x: 0, y: 80))
        #expect(state.capturedImage?.width == 20)
        #expect(state.capturedSelectionRect == original)
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(state.capturedImage?.width == 220)
        #expect(state.capturedImage?.height == 120)
        for (actual, expected) in zip(state.annotations, oldMarks) { expectUnchanged(actual, expected) }

        let image = try #require(state.capturedImage)
        let frame = try #require(state.capturedSelectionRect)
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        for tool in OverlayAnnotationTool.allCases {
            try addAnnotation(tool, to: state, start: CGPoint(x: -180, y: 100), end: CGPoint(x: -130, y: 70))
            let mark = try #require(state.annotations.last)
            if tool == .text {
                #expect(abs(mark.fontSize - 18 / scaleY) < 0.000001)
            } else {
                #expect(abs(mark.lineWidth - (tool == .highlight ? 12 : 4) / scaleX) < 0.000001)
            }
            if tool == .arrow {
                #expect(abs(mark.minimumArrowheadLength - 10 / scaleX) < 0.000001)
            }
        }
        #expect(state.annotations.prefix(5).map(\.id) == oldMarks.map(\.id))
    }

    @Test
    func creationUsesIndependentCommittedXAndYDensity() throws {
        let state = RegionSelectionState(snapshots: [try snapshot(
            frame: CGRect(x: -120, y: -60, width: 480, height: 360), density: 2, densityY: 5 / 3
        )])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 0, y: 0, width: 180, height: 144))
        try addAnnotation(.arrow, to: state)
        let arrow = try #require(state.annotations.last)
        #expect(arrow.lineWidth == 2)
        #expect(arrow.minimumArrowheadLength == 5)
        try addAnnotation(.text, to: state)
        #expect(abs(try #require(state.annotations.last).fontSize - 18 / (5 / 3)) < 0.000001)
    }

    @Test(arguments: [1.0, 2.0, 5.0 / 3.0])
    func samplingAndMinimumGeometryRetainLegacyPixelThresholds(density: Double) throws {
        let state = try selection(density: density)
        let start = CGPoint(x: 170, y: 200)
        for tool in [OverlayAnnotationTool.draw, .highlight] {
            state.beginAnnotation(tool: tool, at: start, color: .red, lineWidth: 4)
            state.updateAnnotation(to: CGPoint(x: start.x + 0.75 / density, y: start.y))
            #expect(state.draftAnnotation?.pointsInCanvas == [start])
            let next = CGPoint(x: start.x + 1.25 / density, y: start.y)
            state.updateAnnotation(to: next)
            #expect(state.draftAnnotation?.pointsInCanvas == [start, next])
            state.commitAnnotation()
        }
        for tool in [OverlayAnnotationTool.arrow, .rectangle] {
            let before = state.annotations.count
            state.beginAnnotation(tool: tool, at: start, color: .red, lineWidth: 4)
            state.updateAnnotation(to: CGPoint(x: start.x + 0.5 / density, y: start.y + 0.5 / density))
            state.commitAnnotation()
            #expect(state.annotations.count == before)
            state.beginAnnotation(tool: tool, at: start, color: .red, lineWidth: 4)
            state.updateAnnotation(to: CGPoint(x: start.x + 1.25 / density, y: start.y + 1.25 / density))
            state.commitAnnotation()
            #expect(state.annotations.count == before + 1)
        }
    }

    @Test(arguments: RegionSelectionResizeHandle.allCases)
    func unannotatedSelectionsStillResizeWithoutReplacingTheCanvas(handle: RegionSelectionResizeHandle) throws {
        let state = try selection()
        let original = try #require(state.selectionRect)
        state.resizeAnchoredSelection(from: original, dragging: handle, to: resizePoint(original, handle: handle))
        #expect(state.selectionRect == expandedRect(original, handle: handle))
        #expect(!state.hasCommittedOrDraftAnnotations)
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(state.capturedSelectionRect == state.selectionRect)
        #expect(try #require(state.annotationCanvas).point(fromScreen: CGPoint(x: -120, y: 300)) == .zero)
    }

    @Test(arguments: RegionSelectionResizeHandle.allCases)
    func resizeCannotCrossDisplayBoundaries(handle: RegionSelectionResizeHandle) throws {
        let state = RegionSelectionState(snapshots: [
            try snapshot(frame: CGRect(x: -120, y: -60, width: 480, height: 360), density: 2),
            try snapshot(frame: CGRect(x: 600, y: -60, width: 480, height: 360), density: 2)
        ])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 0, y: 0, width: 180, height: 144))
        let original = try #require(state.selectionRect)
        // Drag far past the seam into the second display.
        let farPoint = CGPoint(
            x: handle.movesLeftEdge ? original.minX - 900 : handle.movesRightEdge ? original.maxX + 900 : original.midX,
            y: handle.movesBottomEdge ? original.minY - 900 : handle.movesTopEdge ? original.maxY + 900 : original.midY
        )
        state.resizeAnchoredSelection(from: original, dragging: handle, to: farPoint)
        let result = try #require(state.selectionRect)
        // The edge stays within the first display's bounds.
        #expect(result.minX >= -120)
        #expect(result.maxX <= 360)
        #expect(result.minY >= -60)
        #expect(result.maxY <= 300)
    }

    @Test
    func draftTextUndoAndResetDoNotLeakIntoAnotherCapture() throws {
        let state = try selection(density: 2)
        try addAnnotation(.draw, to: state)
        let frame = try #require(state.selectionRect)
        let canvas = try #require(state.annotationCanvas)
        state.beginAnnotation(tool: .text, at: canvas.point(fromScreen: CGPoint(x: 60, y: 110)), color: .red, lineWidth: 4, fontSize: 18)
        state.updateDraftText("  Aa\nBb\n\nCc\n")
        #expect(state.draftAnnotation?.textPositionInCanvas == CGPoint(x: 180, y: 190))
        state.commitDraftText()
        #expect(state.annotations.last?.text == "Aa\nBb\n\nCc")
        #expect(state.draftAnnotation == nil)
        state.beginAnnotation(tool: .text, at: .zero, color: .red, lineWidth: 4)
        state.updateDraftText("discard")
        state.undoLastAnnotation()
        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.count == 2)
        #expect(state.selectionRect == frame)
        state.beginAnnotation(tool: .text, at: .zero, color: .red, lineWidth: 4)
        state.updateDraftText(" \n ")
        state.commitDraftText()
        #expect(state.annotations.count == 2)
        #expect(state.draftAnnotation == nil)
        state.beginAnnotation(tool: .draw, at: .zero, color: .red, lineWidth: 4)
        state.reset()
        #expect(state.annotationCanvas == nil)
        #expect(state.capturedSelectionRect == nil)
        #expect(state.capturedImage == nil)
        #expect(state.capturedPNG == nil)
        #expect(state.selectionRect == nil)
        #expect(state.anchorPoint == nil)
        #expect(state.currentPoint == nil)
        #expect(!state.isSelectionAnchored)
        #expect(state.snapshots.isEmpty)
        #expect(state.annotations.isEmpty)
        #expect(state.draftAnnotation == nil)
        #expect(!state.hasCommittedOrDraftAnnotations)
        state.beginAnnotation(tool: .arrow, at: .zero, color: .red, lineWidth: 4)
        #expect(state.draftAnnotation == nil)

        let fresh = try selection()
        #expect(fresh.annotations.isEmpty)
        #expect(fresh.draftAnnotation == nil)
        #expect(try #require(fresh.annotationCanvas).point(fromScreen: CGPoint(x: -120, y: 300)) == .zero)
    }

    private func selection(density: CGFloat = 1) throws -> RegionSelectionState {
        let state = RegionSelectionState(snapshots: [try snapshot(
            frame: CGRect(x: -120, y: -60, width: 480, height: 360), density: density
        )])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 0, y: 0, width: 180, height: 144))
        return state
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

    private func addAnnotation(
        _ tool: OverlayAnnotationTool, to state: RegionSelectionState,
        start: CGPoint = CGPoint(x: 50, y: 100), end: CGPoint = CGPoint(x: 100, y: 70)
    ) throws {
        let canvas = try #require(state.annotationCanvas)
        state.beginAnnotation(tool: tool, at: canvas.point(fromScreen: start), color: .red, lineWidth: 4, fontSize: 18)
        if tool == .text {
            state.updateDraftText("Aa")
            state.commitDraftText()
        } else {
            state.updateAnnotation(to: canvas.point(fromScreen: end))
            state.commitAnnotation()
        }
    }

    private func assertOriginalContentLocation(_ mark: OverlayAnnotation, tool: OverlayAnnotationTool) {
        switch tool {
        case .rectangle:
            #expect(mark.rectInCanvas == CGRect(x: 170, y: 200, width: 50, height: 30))
        case .text:
            #expect(mark.textPositionInCanvas == CGPoint(x: 170, y: 200))
            #expect(mark.text == "Aa")
        case .arrow, .draw, .highlight:
            #expect(mark.pointsInCanvas == [CGPoint(x: 170, y: 200), CGPoint(x: 220, y: 230)])
        }
    }

    private func expectUnchanged(_ actual: OverlayAnnotation, _ expected: OverlayAnnotation) {
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
    }

    private func resizePoint(_ rect: CGRect, handle: RegionSelectionResizeHandle) -> CGPoint {
        let left = [RegionSelectionResizeHandle.topLeft, .left, .bottomLeft].contains(handle)
        let bottom = [RegionSelectionResizeHandle.bottomLeft, .bottom, .bottomRight].contains(handle)
        return CGPoint(x: left ? rect.minX - 12.13 : rect.maxX + 12.17,
                       y: bottom ? rect.minY - 10.19 : rect.maxY + 12.23)
    }

    private func expandedRect(_ rect: CGRect, handle: RegionSelectionResizeHandle) -> CGRect {
        let point = resizePoint(rect, handle: handle)
        let minX = [RegionSelectionResizeHandle.topLeft, .left, .bottomLeft].contains(handle) ? point.x : rect.minX
        let maxX = [RegionSelectionResizeHandle.topRight, .right, .bottomRight].contains(handle) ? point.x : rect.maxX
        let minY = [RegionSelectionResizeHandle.bottomLeft, .bottom, .bottomRight].contains(handle) ? point.y : rect.minY
        let maxY = [RegionSelectionResizeHandle.topLeft, .top, .topRight].contains(handle) ? point.y : rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func alignedRect(_ rect: CGRect, density: CGFloat) -> CGRect {
        let minX = -120 + floor((rect.minX + 120) * density) / density
        let maxX = -120 + ceil((rect.maxX + 120) * density) / density
        let maxY = 300 - floor((300 - rect.maxY) * density) / density
        let minY = 300 - ceil((300 - rect.minY) * density) / density
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func expectRect(_ actual: CGRect, _ expected: CGRect) {
        #expect(abs(actual.minX - expected.minX) < 0.000001)
        #expect(abs(actual.minY - expected.minY) < 0.000001)
        #expect(abs(actual.width - expected.width) < 0.000001)
        #expect(abs(actual.height - expected.height) < 0.000001)
    }
}
