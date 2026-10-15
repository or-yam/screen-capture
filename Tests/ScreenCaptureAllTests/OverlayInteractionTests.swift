import AppKit
import Testing
@testable import ScreenCaptureAll

@MainActor
struct OverlayInteractionTests {
    @Test(arguments: RegionSelectionResizeHandle.allCases)
    func handlesResizeAfterAnnotations(handle: RegionSelectionResizeHandle) throws {
        let state = try annotatedSelection()
        let initial = try #require(state.selectionRect)
        let annotation = try #require(state.annotations.first)
        var completed: CGRect?
        let view = overlay(state, selectionCompleted: { completed = $0 })
        let start = handlePoint(handle, in: initial)
        let end = CGPoint(
            x: start.x + (handle.movesLeftEdge ? -24 : handle.movesRightEdge ? 24 : 0),
            y: start.y + (handle.movesBottomEdge ? -20 : handle.movesTopEdge ? 20 : 0)
        )

        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        let live = try #require(state.selectionRect)
        #expect(live.minX == initial.minX - (handle.movesLeftEdge ? 24 : 0))
        #expect(live.maxX == initial.maxX + (handle.movesRightEdge ? 24 : 0))
        #expect(live.minY == initial.minY - (handle.movesBottomEdge ? 20 : 0))
        #expect(live.maxY == initial.maxY + (handle.movesTopEdge ? 20 : 0))
        #expect(state.capturedSelectionRect == initial)
        #expect(state.annotations.first?.id == annotation.id)
        #expect(state.annotations.first?.rectInCanvas == annotation.rectInCanvas)

        view.mouseUp(with: try mouse(.leftMouseUp, at: end))
        #expect(completed == live)
        try state.setCapturedImageFromFrozenSnapshots(for: #require(completed))
        #expect(state.capturedSelectionRect == live)
        #expect(state.annotations.first?.rectInCanvas == annotation.rectInCanvas)
    }

    @Test
    func moveAndUndoDoNotRewriteAnnotationOrSelectionGeometry() throws {
        let state = try annotatedSelection()
        let initial = try #require(state.selectionRect)
        let annotation = try #require(state.annotations.first)
        var completed: CGRect?
        let view = overlay(state, selectionCompleted: { completed = $0 })
        let start = CGPoint(x: initial.midX, y: initial.midY)
        let end = CGPoint(x: start.x + 120, y: start.y + 50)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: try mouse(.leftMouseUp, at: end))

        let moved = initial.offsetBy(dx: 120, dy: 50)
        #expect(completed == moved)
        #expect(state.selectionRect == moved)
        #expect(state.annotations.first?.rectInCanvas == annotation.rectInCanvas)
        view.keyDown(with: try command("z", keyCode: 6))
        #expect(state.annotations.isEmpty)
        #expect(state.selectionRect == moved)
    }

    @Test
    func annotationInputAfterMoveUsesCanvasAndTextCommitsOnToolSwitch() throws {
        let state = try annotatedSelection()
        let initial = try #require(state.selectionRect)
        state.moveAnchoredSelection(from: initial, by: CGSize(width: 100, height: 0))
        try state.setCapturedImageFromFrozenSnapshots(for: #require(state.selectionRect))
        let canvas = try #require(state.annotationCanvas)
        let view = overlay(state)
        view.refreshState()

        let arrow = try #require(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Arrow" })
        arrow.performClick(nil)
        let start = CGPoint(x: 300, y: 260)
        let end = CGPoint(x: 350, y: 220)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: try mouse(.leftMouseUp, at: end))
        #expect(state.annotations.last?.pointsInCanvas == [canvas.point(fromScreen: start), canvas.point(fromScreen: end)])

        let text = try #require(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Text" })
        text.performClick(nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        let field = try #require(view.subviews.compactMap { $0 as? AnnotationTextField }.first)
        #expect(state.draftAnnotation?.textPositionInCanvas == canvas.point(fromScreen: start))
        field.stringValue = "Anchored text"
        let move = try #require(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Move" })
        move.performClick(nil)
        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.last?.text == "Anchored text")
        #expect(state.annotations.last?.textPositionInCanvas == canvas.point(fromScreen: start))
        #expect(!view.subviews.contains { $0 is AnnotationTextField })
    }

    @Test
    func textEditorUsesTheDraftsAnisotropicGlyphBasis() throws {
        let state = try annotatedSelection(scaleX: 2)
        let view = overlay(state)
        view.refreshState()
        let text = try #require(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Text" })
        text.performClick(nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 260)))
        let field = try #require(view.subviews.compactMap { $0 as? AnnotationTextField }.first)
        let draft = try #require(state.draftAnnotation)
        #expect(draft.creationPixelSizeInCanvas == CGSize(width: 0.5, height: 1))
        #expect(field.font?.pointSize == draft.fontSize / draft.creationPixelSizeInCanvas.height)
        #expect(field.bounds.width == field.frame.width * 2)
        #expect(field.bounds.height == field.frame.height)
    }

    @Test
    func displayClippingDoesNotCreateAResizeHandleAtTheSeam() throws {
        let state = try annotatedSelection()
        let initial = try #require(state.selectionRect)
        let view = overlay(state)
        // This overlay sees only x < 300; the actual right edge is at x = 390.
        view.setFrameSize(CGSize(width: 300, height: 500))
        let start = CGPoint(x: 299, y: initial.midY)
        let end = CGPoint(x: 279, y: initial.midY)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: try mouse(.leftMouseUp, at: end))
        // A drag just inside the display edge is a Move, not a false right-edge
        // resize that would unexpectedly cut the global selection at the seam.
        #expect(state.selectionRect == initial.offsetBy(dx: -20, dy: 0))
    }

    @Test
    func replacementSelectionStaysDisabledUntilAnnotationsAreUndone() throws {
        let state = try annotatedSelection()
        let initial = try #require(state.selectionRect)
        var completed: CGRect?
        let view = overlay(state, selectionCompleted: { completed = $0 })
        let start = CGPoint(x: 20, y: 20)
        let end = CGPoint(x: 80, y: 80)

        for annotationsRemain in [true, false] {
            if !annotationsRemain {
                view.keyDown(with: try command("z", keyCode: 6))
            }
            view.mouseDown(with: try mouse(.leftMouseDown, at: start))
            view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
            view.mouseUp(with: try mouse(.leftMouseUp, at: end))
            if annotationsRemain {
                #expect(completed == nil)
                #expect(state.selectionRect == initial)
                #expect(state.annotations.count == 1)
            } else {
                #expect(completed == CGRect(x: 20, y: 20, width: 60, height: 60))
                #expect(state.annotations.isEmpty)
            }
        }
    }

    @Test(arguments: ["c", "s"])
    func exportDuringResizeUsesCommittedImageAndFrame(shortcut: String) throws {
        let state = try annotatedSelection()
        let initial = try #require(state.capturedSelectionRect)
        let image = try #require(state.capturedImage)
        let canvas = try #require(state.annotationCanvas)
        let expected = try Renderer().renderPNG(
            baseImage: image, annotations: state.annotations, canvas: canvas, selectionRect: initial
        )
        var exported: Data?
        let view = overlay(state, copy: { exported = $0 }, save: { exported = $0 })
        let start = CGPoint(x: initial.minX, y: initial.maxY)
        let end = CGPoint(x: start.x - 40, y: start.y + 30)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        #expect(state.selectionRect != initial)
        view.keyDown(with: try command(shortcut, keyCode: shortcut == "c" ? 8 : 1))
        #expect(try #require(exported) == expected)
        #expect(state.capturedSelectionRect == initial)
    }

    private func annotatedSelection(scaleX: Int = 1) throws -> RegionSelectionState {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        let context = try #require(CGContext(
            data: nil, width: 600 * scaleX, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 600 * scaleX, height: 500))
        let image = try #require(context.makeImage())
        let display = DisplayGeometry(
            localizedName: "Synthetic", frameInDisplaySpace: frame,
            frameInAppKitScreenSpace: frame, backingScaleFactor: CGFloat(scaleX)
        )
        let state = RegionSelectionState(snapshots: [DisplaySnapshot(display: display, image: image)])
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: 150, y: 140, width: 240, height: 180))
        let canvas = try #require(state.annotationCanvas)
        state.beginAnnotation(tool: .rectangle, at: canvas.point(fromScreen: CGPoint(x: 190, y: 250)), color: .red, lineWidth: 2)
        state.updateAnnotation(to: canvas.point(fromScreen: CGPoint(x: 230, y: 210)))
        state.commitAnnotation()
        #expect(state.annotations.count == 1)
        return state
    }

    private func overlay(
        _ state: RegionSelectionState,
        copy: @escaping (Data) -> Void = { _ in },
        save: @escaping (Data) -> Void = { _ in },
        selectionCompleted: @escaping (CGRect) -> Void = { _ in }
    ) -> RegionCaptureOverlayView {
        RegionCaptureOverlayView(
            frame: CGRect(x: 0, y: 0, width: 600, height: 500), selectionState: state,
            close: {}, copy: copy, save: save, selectionCompleted: selectionCompleted,
            defaultAnnotationColor: .red, defaultAnnotationStrokeWidth: 2, refresh: {}
        )
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

    private func handlePoint(_ handle: RegionSelectionResizeHandle, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: handle.movesLeftEdge ? rect.minX : handle.movesRightEdge ? rect.maxX : rect.midX,
            y: handle.movesTopEdge ? rect.maxY : handle.movesBottomEdge ? rect.minY : rect.midY
        )
    }
}
