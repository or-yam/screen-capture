import AppKit
import ImageIO
import Testing
@testable import ScreenCaptureAll

@MainActor
struct RendererTests {
    @Test(arguments: OverlayAnnotationTool.allCases, [1.0, 2.0, 5.0 / 3.0])
    func overlayAndExportMatchAtNativePixelSize(tool: OverlayAnnotationTool, density: Double) throws {
        let source = try whiteImage(width: 240, height: 180)
        let frame = CGRect(x: 12 / density, y: 12 / density, width: 240 / density, height: 180 / density)
        let state = try selection(image: source, frame: frame)
        try addAnnotation(tool: tool, to: state)

        let preview = try drawOverlay(
            state,
            pointSize: CGSize(width: 264 / density, height: 204 / density),
            pixelWidth: 264,
            pixelHeight: 204,
            density: density
        )
        let exported = try export(state)
        #expect(exported.width == 240)
        #expect(exported.height == 180)

        // Handles are now visible after annotation. Exclude their 4-point
        // half-size plus border at up to 2x, not just the selection outline.
        let previewContent = try #require(preview.cropping(to: CGRect(x: 24, y: 24, width: 216, height: 156)))
        let exportContent = try #require(exported.cropping(to: CGRect(x: 12, y: 12, width: 216, height: 156)))
        try expectMatchingAnnotationFootprint(previewContent, exportContent)
        #expect(try pixels(exported) != pixels(source))
    }

    @Test
    func displayClippingDoesNotRescaleSelectionOrAnnotations() throws {
        let sourceContext = try bitmapContext(width: 120, height: 100)
        sourceContext.setFillColor(NSColor.white.cgColor)
        sourceContext.fill(CGRect(x: 0, y: 0, width: 120, height: 100))
        sourceContext.setFillColor(NSColor.black.cgColor)
        sourceContext.fill(CGRect(x: 0, y: 0, width: 60, height: 100))
        let source = try #require(sourceContext.makeImage())
        let frame = CGRect(x: -60, y: 0, width: 120, height: 100)
        let state = try selection(image: source, frame: frame)
        state.beginAnnotation(tool: .rectangle, at: try canvasPoint(fromImage: CGPoint(x: 80, y: 30), in: state), color: .red, lineWidth: 2)
        state.updateAnnotation(to: try canvasPoint(fromImage: CGPoint(x: 100, y: 70), in: state))
        state.commitAnnotation()

        // This overlay sees only the right half of the selected image.
        let preview = try drawOverlay(state, pointSize: CGSize(width: 60, height: 100), pixelWidth: 60, pixelHeight: 100)
        let exported = try export(state)
        let previewContent = try #require(preview.cropping(to: CGRect(x: 4, y: 4, width: 52, height: 92)))
        let exportContent = try #require(exported.cropping(to: CGRect(x: 64, y: 4, width: 52, height: 92)))
        try expectMatchingAnnotationFootprint(previewContent, exportContent)
    }

    @Test
    func draftAppearsInPreviewButNotExportUntilCommitted() throws {
        let source = try whiteImage(width: 240, height: 180)
        let state = try selection(image: source, frame: CGRect(x: 12, y: 12, width: 240, height: 180))
        state.beginAnnotation(tool: .arrow, at: try canvasPoint(fromImage: CGPoint(x: 40, y: 40), in: state), color: .red, lineWidth: 2)
        state.updateAnnotation(to: try canvasPoint(fromImage: CGPoint(x: 90, y: 70), in: state))

        let preview = try drawOverlay(state, pointSize: CGSize(width: 264, height: 204), pixelWidth: 264, pixelHeight: 204)
        let previewPixels = try pixels(preview)
        #expect(redInkMask(previewPixels).contains(true))
        #expect(try pixels(export(state)) == pixels(source))

        state.commitAnnotation()
        let committed = try export(state)
        let previewContent = try #require(preview.cropping(to: CGRect(x: 16, y: 16, width: 232, height: 172)))
        let exportContent = try #require(committed.cropping(to: CGRect(x: 4, y: 4, width: 232, height: 172)))
        try expectMatchingAnnotationFootprint(previewContent, exportContent)
    }

    @Test(arguments: OverlayAnnotationTool.allCases)
    func drawingRestoresCallerTransformAndClip(tool: OverlayAnnotationTool) throws {
        let context = try bitmapContext(width: 80, height: 80)
        context.translateBy(x: 3, y: 7)
        context.clip(to: CGRect(x: 0, y: 0, width: 60, height: 60))
        let transform = context.ctm
        let clip = context.boundingBoxOfClipPath
        let appKitContext = NSGraphicsContext.current

        Renderer().drawAnnotations(
            [OverlayAnnotation(
                kind: tool, rectInCanvas: tool == .rectangle ? CGRect(x: 2, y: 2, width: 20, height: 20) : nil,
                pointsInCanvas: [.zero, CGPoint(x: 20, y: 20)], text: "Aa", textPositionInCanvas: CGPoint(x: 2, y: 2)
            )],
            canvas: AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: 0, y: 0, width: 40, height: 40)),
            selectionRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            in: context,
            destinationRect: CGRect(x: 10, y: 10, width: 20, height: 20)
        )

        #expect(context.ctm == transform)
        #expect(context.boundingBoxOfClipPath == clip)
        #expect(NSGraphicsContext.current === appKitContext)
    }

    @Test(arguments: OverlayAnnotationTool.allCases, RegionSelectionResizeHandle.allCases)
    func liveAndCommittedResizeKeepInkAtItsFrozenScreenLocation(
        tool: OverlayAnnotationTool, handle: RegionSelectionResizeHandle
    ) throws {
        let state = try selection(image: whiteImage(width: 300, height: 260), frame: CGRect(x: 0, y: 0, width: 300, height: 260))
        let original = CGRect(x: 40, y: 40, width: 180, height: 160)
        try state.setCapturedImageFromFrozenSnapshots(for: original)
        try addScreenAnnotation(tool, to: state)
        let before = try screenPreview(state)
        let beforeExport = try export(state)
        try expectInkAtScreenLocation(before, selectionRect: CGRect(x: 0, y: 0, width: 300, height: 260))

        let point = CGPoint(
            x: [RegionSelectionResizeHandle.topLeft, .left, .bottomLeft].contains(handle) ? 27.25 : 233.25,
            y: [RegionSelectionResizeHandle.bottomLeft, .bottom, .bottomRight].contains(handle) ? 27.25 : 213.25
        )
        state.resizeAnchoredSelection(from: original, dragging: handle, to: point)
        let live = try screenPreview(state)
        // An independent screen-location check prevents two equally wrong
        // preview/export transforms from making this regression test pass.
        try expectInkAtScreenLocation(live, selectionRect: CGRect(x: 0, y: 0, width: 300, height: 260))
        #expect(try redInkMask(pixels(live)) == redInkMask(pixels(before)))
        #expect(state.capturedSelectionRect == original)
        #expect(try pixels(export(state)) == pixels(beforeExport))

        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        let committed = try screenPreview(state)
        #expect(try redInkMask(pixels(committed)) == redInkMask(pixels(before)))
        let frame = try #require(state.capturedSelectionRect)
        let exported = try export(state)
        try expectInkAtScreenLocation(exported, selectionRect: frame)
        let previewContent = try #require(committed.cropping(to: CGRect(
            x: frame.minX + 4, y: 260 - frame.maxY + 4, width: frame.width - 8, height: frame.height - 8
        )))
        let exportContent = try #require(exported.cropping(to: CGRect(x: 4, y: 4, width: frame.width - 8, height: frame.height - 8)))
        try expectMatchingAnnotationFootprint(previewContent, exportContent)
    }

    @Test(arguments: OverlayAnnotationTool.allCases)
    func clippingAndMovingAwayRevealOriginalMarksWhenBoundsReturn(tool: OverlayAnnotationTool) throws {
        let state = try selection(image: whiteImage(width: 500, height: 260), frame: CGRect(x: 0, y: 0, width: 500, height: 260))
        let original = CGRect(x: 40, y: 40, width: 180, height: 160)
        try state.setCapturedImageFromFrozenSnapshots(for: original)
        try addScreenAnnotation(tool, to: state)
        let initialExport = try export(state)
        let originalInkCount = try redInkMask(pixels(initialExport)).filter { $0 }.count
        #expect(originalInkCount > 0)

        state.resizeAnchoredSelection(from: original, dragging: .right, to: CGPoint(x: 110, y: 120))
        let partialPreview = try drawOverlay(state, pointSize: CGSize(width: 500, height: 260), pixelWidth: 500, pixelHeight: 260)
        let partialInkCount = try redInkMask(pixels(partialPreview)).filter { $0 }.count
        #expect(partialInkCount > 0)
        #expect(partialInkCount < originalInkCount)
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(try redInkMask(pixels(export(state))).contains(true))

        try state.setCapturedImageFromFrozenSnapshots(for: original)
        state.resizeAnchoredSelection(from: original, dragging: .left, to: CGPoint(x: 170, y: 120))
        let hiddenPreview = try drawOverlay(state, pointSize: CGSize(width: 500, height: 260), pixelWidth: 500, pixelHeight: 260)
        #expect(try !redInkMask(pixels(hiddenPreview)).contains(true))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(try !redInkMask(pixels(export(state))).contains(true))
        #expect(state.annotations.count == 1)

        state.resizeAnchoredSelection(from: try #require(state.selectionRect), dragging: .left, to: original.origin)
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(try pixels(export(state)) == pixels(initialExport))
        state.moveAnchoredSelection(from: original, by: CGSize(width: 240, height: 0))
        let awayPreview = try drawOverlay(state, pointSize: CGSize(width: 500, height: 260), pixelWidth: 500, pixelHeight: 260)
        #expect(try !redInkMask(pixels(awayPreview)).contains(true))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(try !redInkMask(pixels(export(state))).contains(true))
        state.moveAnchoredSelection(from: try #require(state.selectionRect), by: CGSize(width: -240, height: 0))
        try state.setCapturedImageFromFrozenSnapshots(for: try #require(state.selectionRect))
        #expect(try pixels(export(state)) == pixels(initialExport))
    }

    // Within-display mixed-density export is covered by
    // mixedDensityCommitPreservesOldSizesAndConvertsNewPixelToolSettings and
    // AnnotationDensityTests. Cross-display spanning resize is intentionally
    // blocked; see resizeCannotCrossDisplayBoundaries.

    @Test
    func annotationsAreClippedToDestinationNotCallerCanvas() throws {
        let context = try bitmapContext(width: 100, height: 80)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        let destination = CGRect(x: 20, y: 15, width: 50, height: 40)
        Renderer().drawAnnotations(
            [OverlayAnnotation(kind: .draw, pointsInCanvas: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)], color: .red, lineWidth: 8)],
            canvas: AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: -20, y: -10, width: 100, height: 80)),
            selectionRect: CGRect(x: 0, y: 10, width: 50, height: 40),
            in: context, destinationRect: destination
        )
        let image = try #require(context.makeImage())
        try expectInkInside(image, pixelRect: destination)
    }

    private func addScreenAnnotation(
        _ tool: OverlayAnnotationTool, to state: RegionSelectionState,
        start: CGPoint = CGPoint(x: 100, y: 150), end: CGPoint = CGPoint(x: 150, y: 120)
    ) throws {
        let canvas = try #require(state.annotationCanvas)
        state.beginAnnotation(tool: tool, at: canvas.point(fromScreen: start), color: .red, lineWidth: 2, fontSize: 14)
        if tool == .text {
            state.updateDraftText("Aa")
            state.commitDraftText()
        } else {
            state.updateAnnotation(to: canvas.point(fromScreen: end))
            state.commitAnnotation()
        }
    }

    private func screenPreview(_ state: RegionSelectionState) throws -> CGImage {
        try drawOverlay(state, pointSize: CGSize(width: 300, height: 260), pixelWidth: 300, pixelHeight: 260)
    }

    private func display(frame: CGRect, density: CGFloat) -> DisplayGeometry {
        DisplayGeometry(localizedName: "Synthetic", frameInDisplaySpace: frame, frameInAppKitScreenSpace: frame, backingScaleFactor: density)
    }

    private func expectInkAtScreenLocation(
        _ image: CGImage, selectionRect: CGRect,
        expected: CGRect = CGRect(x: 94, y: 112, width: 64, height: 46)
    ) throws {
        let scaleX = CGFloat(image.width) / selectionRect.width
        let scaleY = CGFloat(image.height) / selectionRect.height
        // This expected region is computed directly in screen/bitmap coordinates,
        // without using AnnotationCanvas or any renderer transform.
        try expectInkInside(image, pixelRect: CGRect(
            x: (expected.minX - selectionRect.minX) * scaleX,
            y: (expected.minY - selectionRect.minY) * scaleY,
            width: expected.width * scaleX, height: expected.height * scaleY
        ))
    }

    private func expectInkInside(_ image: CGImage, pixelRect: CGRect) throws {
        let reference = try bitmapContext(width: image.width, height: image.height)
        reference.setFillColor(NSColor.white.cgColor)
        reference.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        reference.setFillColor(NSColor.red.cgColor)
        reference.fill(pixelRect)
        let allowed = try redInkMask(pixels(#require(reference.makeImage())))
        let actual = try redInkMask(pixels(image))
        #expect(actual.contains(true))
        #expect(zip(actual, allowed).allSatisfy { ink, permitted in !ink || permitted })
    }

    private func addAnnotation(tool: OverlayAnnotationTool, to state: RegionSelectionState) throws {
        state.beginAnnotation(
            tool: tool,
            at: try canvasPoint(fromImage: CGPoint(x: 40, y: 40), in: state),
            color: tool == .highlight ? NSColor.red.withAlphaComponent(0.3) : .red,
            lineWidth: 2,
            fontSize: 14
        )
        if tool == .text {
            state.updateDraftText("Aa")
            state.commitDraftText()
        } else {
            state.updateAnnotation(to: try canvasPoint(fromImage: CGPoint(x: 90, y: 70), in: state))
            state.commitAnnotation()
        }
    }

    private func selection(image: CGImage, frame: CGRect) throws -> RegionSelectionState {
        let display = DisplayGeometry(
            localizedName: "Synthetic",
            frameInDisplaySpace: frame,
            frameInAppKitScreenSpace: frame,
            backingScaleFactor: CGFloat(image.width) / frame.width
        )
        let state = RegionSelectionState(snapshots: [DisplaySnapshot(display: display, image: image)])
        try state.setCapturedImageFromFrozenSnapshots(for: frame)
        return state
    }

    private func drawOverlay(
        _ state: RegionSelectionState,
        pointSize: CGSize,
        pixelWidth: Int,
        pixelHeight: Int,
        density: CGFloat = 1
    ) throws -> CGImage {
        let view = RegionCaptureOverlayView(
            frame: CGRect(origin: .zero, size: pointSize),
            selectionState: state,
            close: {},
            copy: { _ in },
            save: { _ in },
            selectionCompleted: { _ in },
            defaultAnnotationColor: .red,
            defaultAnnotationStrokeWidth: 2,
            refresh: {}
        )
        let context = try bitmapContext(width: pixelWidth, height: pixelHeight)
        context.scaleBy(x: density, y: density)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        view.draw(view.bounds)
        return try #require(context.makeImage())
    }

    private func export(_ state: RegionSelectionState) throws -> CGImage {
        let base = try #require(state.capturedImage)
        let canvas = try #require(state.annotationCanvas)
        let frame = try #require(state.capturedSelectionRect)
        let data = try Renderer().renderPNG(baseImage: base, annotations: state.annotations, canvas: canvas, selectionRect: frame)
        let decoder = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
    }

    // Preserve the old tests' image-pixel inputs and appearance, but enter them
    // through the new stable canvas rather than treating pixels as screen points.
    private func canvasPoint(fromImage point: CGPoint, in state: RegionSelectionState) throws -> CGPoint {
        let image = try #require(state.capturedImage)
        let frame = try #require(state.capturedSelectionRect)
        let canvas = try #require(state.annotationCanvas)
        return canvas.point(fromScreen: CGPoint(
            x: frame.minX + point.x * frame.width / CGFloat(image.width),
            y: frame.maxY - point.y * frame.height / CGFloat(image.height)
        ))
    }

    private func whiteImage(width: Int, height: Int) throws -> CGImage {
        let context = try bitmapContext(width: width, height: height)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func bitmapContext(width: Int, height: Int) throws -> CGContext {
        try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try bitmapContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: image.width * image.height * 4
        ))
    }

    private func expectMatchingAnnotationFootprint(_ preview: CGImage, _ exported: CGImage) throws {
        let previewPixels = try pixels(preview)
        let exportPixels = try pixels(exported)
        // AppKit and bitmap contexts can differ slightly in edge coverage.
        // Require matching red-ink placement and reject substantial color changes,
        // rather than depending on identical antialiasing bytes across contexts.
        let previewMask = redInkMask(previewPixels)
        let exportMask = redInkMask(exportPixels)
        let misplacedPixels = zip(previewMask, exportMask).filter { $0 != $1 }.count
        let maximumChannelDifference = zip(previewPixels, exportPixels).map {
            abs(Int($0) - Int($1))
        }.max() ?? 0
        #expect(exportMask.contains(true))
        // Fractional density can align outward to source pixels, shifting the
        // annotation by a fraction of a pixel between preview and export.
        #expect(misplacedPixels <= 2)
        #expect(maximumChannelDifference <= 20)
    }

    private func redInkMask(_ pixels: [UInt8]) -> [Bool] {
        stride(from: 0, to: pixels.count, by: 4).map { index in
            Int(pixels[index]) - Int(min(pixels[index + 1], pixels[index + 2])) >= 24
        }
    }
}
