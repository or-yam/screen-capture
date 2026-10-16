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
        let field = try #require(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        #expect(state.draftAnnotation?.textPositionInCanvas == canvas.point(fromScreen: start))
        field.insertText("Anchored text", replacementRange: NSRange(location: 0, length: 0))
        let move = try #require(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Move" })
        move.performClick(nil)
        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.last?.text == "Anchored text")
        #expect(state.annotations.last?.textPositionInCanvas == canvas.point(fromScreen: start))
        #expect(!view.subviews.contains { $0 is AnnotationTextEditor })
    }

    @Test
    func textEditorUsesTheDraftsAnisotropicGlyphBasis() throws {
        let state = try annotatedSelection(scaleX: 2)
        let view = overlay(state)
        view.refreshState()
        let text = try #require(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Text" })
        text.performClick(nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 260)))
        let field = try #require(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        let draft = try #require(state.draftAnnotation)
        #expect(draft.creationPixelSizeInCanvas == CGSize(width: 0.5, height: 1))
        #expect(field.font?.pointSize == draft.fontSize / draft.creationPixelSizeInCanvas.height)
        #expect(field.bounds.width == field.frame.width * 2)
        #expect(field.bounds.height == field.frame.height)
        field.insertText("First\nSecond", replacementRange: NSRange(location: 0, length: 0))
        #expect(field.bounds.width == field.frame.width * 2)
        #expect(field.bounds.height == field.frame.height)
        #expect(field.frame.minX == 300)
        #expect(field.frame.maxY == 260)
    }

    @Test
    func transparentEditorInsertsNewlinesAndGrowsWithoutWrappingOrMovingItsAnchor() throws {
        let state = try annotatedSelection()
        let view = overlay(state)
        let anchor = CGPoint(x: 300, y: 260)
        let editor = try beginText(in: view, at: anchor)
        #expect(!editor.drawsBackground)
        #expect(!editor.isRichText)
        #expect(editor.textContainerInset == .zero)
        #expect(editor.textContainer?.lineFragmentPadding == 0)
        #expect(editor.textContainer?.widthTracksTextView == false)

        let firstHeight = editor.frame.height
        let longLine = String(repeating: "Long line ", count: 12)
        editor.insertText(longLine, replacementRange: NSRange(location: 0, length: 0))
        #expect(state.draftAnnotation != nil, "after long line")
        let selection = try #require(state.selectionRect)
        #expect(editor.frame.maxX > selection.maxX)
        #expect(editor.frame.height == firstHeight)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(state.draftAnnotation != nil, "after newline")
        #expect(editor.string == longLine + "\n")
        #expect(editor.frame.height > firstHeight)
        editor.insertText("Second line", replacementRange: editor.selectedRange())
        #expect(editor.string == longLine + "\nSecond line")
        #expect(editor.frame.minX == anchor.x)
        #expect(editor.frame.maxY == anchor.y)
        #expect(state.draftAnnotation != nil)
        #expect(state.annotations.count == 1)

        try button("Move", in: view).performClick(nil)
        #expect(state.annotations.last?.text == longLine + "\nSecond line")
    }

    @Test(arguments: [true, false])
    func escapeDiscardsOnlyDraftAndReturnsToMoveBeforeClosing(fromEditor: Bool) throws {
        let state = try annotatedSelection()
        let original = try #require(state.annotations.first)
        var closeCount = 0
        let view = overlay(state, close: { closeCount += 1 })
        let editor = try beginText(in: view)
        editor.insertText("Discard\nthis", replacementRange: NSRange(location: 0, length: 0))
        if fromEditor {
            editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        } else {
            view.keyDown(with: try escape())
        }
        // Resigning focus after cancellation must not commit or remove old ink.
        editor.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor))
        view.refreshState()
        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.map(\.id) == [original.id])
        #expect(!view.subviews.contains { $0 is AnnotationTextEditor })
        #expect(try button("Move", in: view).isActive)
        #expect(try !button("Text", in: view).isActive)
        #expect(closeCount == 0)
        view.keyDown(with: try escape())
        #expect(closeCount == 1)
    }

    @Test
    func escapeExitsSelectedTextToolWithoutAnEditor() throws {
        let state = try annotatedSelection()
        var closeCount = 0
        let view = overlay(state, close: { closeCount += 1 })
        view.refreshState()
        try button("Text", in: view).performClick(nil)
        view.keyDown(with: try escape())
        view.refreshState()
        #expect(try button("Move", in: view).isActive)
        #expect(closeCount == 0)
        view.keyDown(with: try escape())
        #expect(closeCount == 1)
    }

    @Test
    func undoDiscardsTextDraftWithoutDeletingCommittedInkOrExitingTextTool() throws {
        let state = try annotatedSelection()
        let original = try #require(state.annotations.first)
        let view = overlay(state)
        let editor = try beginText(in: view)
        editor.insertText("Draft", replacementRange: editor.selectedRange())
        view.keyDown(with: try command("z", keyCode: 6))
        view.refreshState()
        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.map(\.id) == [original.id])
        #expect(!view.subviews.contains { $0 is AnnotationTextEditor })
        #expect(try button("Text", in: view).isActive)
        // Once the draft is gone, the next Undo retains its normal meaning.
        view.keyDown(with: try command("z", keyCode: 6))
        #expect(state.annotations.isEmpty)
    }

    @Test(arguments: ["click-away", "Copy", "Save", "c", "s", "Move", "Arrow"])
    func multilineTextCommitsOnceThroughEveryCompletionPath(path: String) throws {
        let state = try annotatedSelection()
        var output: Data?
        let view = overlay(state, copy: { output = $0 }, save: { output = $0 })
        let editor = try beginText(in: view)
        editor.insertText("First\nSecond\nThird", replacementRange: NSRange(location: 0, length: 0))
        switch path {
        case "click-away":
            view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        case "c", "s":
            view.keyDown(with: try command(path, keyCode: path == "c" ? 8 : 1))
        default:
            try button(path, in: view).performClick(nil)
        }
        editor.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor))
        #expect(state.annotations.count == 2)
        #expect(state.annotations.last?.text == "First\nSecond\nThird")
        #expect(state.draftAnnotation == nil)
        #expect(!view.subviews.contains { $0 is AnnotationTextEditor })
        if ["Copy", "Save", "c", "s"].contains(path) {
            #expect(output != nil)
        }
    }

    @Test
    func windowResponderRoutesReturnEscapeAndFocusLoss() throws {
        _ = NSApplication.shared
        let state = try annotatedSelection()
        let view = overlay(state)
        // Never order the window onscreen or request desktop automation access.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer {
            window.contentView = nil
            window.close()
        }
        let editor = try beginText(in: view)
        #expect(window.firstResponder === editor)
        editor.insertText("First", replacementRange: editor.selectedRange())
        editor.keyDown(with: try key("\r", keyCode: 36, windowNumber: window.windowNumber))
        editor.insertText("Second", replacementRange: editor.selectedRange())
        #expect(editor.string == "First\nSecond")
        #expect(state.draftAnnotation != nil)
        #expect(state.annotations.count == 1)
        #expect(window.makeFirstResponder(view))
        #expect(state.annotations.last?.text == "First\nSecond")
        #expect(state.annotations.count == 2)

        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 260)))
        let discarded = try #require(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        #expect(window.firstResponder === discarded)
        discarded.insertText("Discard", replacementRange: discarded.selectedRange())
        discarded.keyDown(with: try key("\u{1b}", keyCode: 53, windowNumber: window.windowNumber))
        view.refreshState()
        #expect(state.draftAnnotation == nil)
        #expect(state.annotations.count == 2)
        #expect(try button("Move", in: view).isActive)
        #expect(window.firstResponder === view)
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

    private func button(_ label: String, in view: RegionCaptureOverlayView) throws -> SolidActionButton {
        try #require(view.subviews.compactMap { $0 as? SolidActionButton }.first { $0.accessibilityLabel() == label })
    }

    private func beginText(
        in view: RegionCaptureOverlayView, at point: CGPoint = CGPoint(x: 300, y: 260)
    ) throws -> AnnotationTextEditor {
        view.refreshState()
        try button("Text", in: view).performClick(nil)
        view.refreshState()
        view.mouseDown(with: try mouse(.leftMouseDown, at: point))
        return try #require(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
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

    private func handlePoint(_ handle: RegionSelectionResizeHandle, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: handle.movesLeftEdge ? rect.minX : handle.movesRightEdge ? rect.maxX : rect.midX,
            y: handle.movesTopEdge ? rect.maxY : handle.movesBottomEdge ? rect.minY : rect.midY
        )
    }
}
