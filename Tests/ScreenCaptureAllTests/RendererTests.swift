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
        addAnnotation(tool: tool, to: state)

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

        // Ignore the app-owned selection outline; compare annotation content.
        let previewContent = try #require(preview.cropping(to: CGRect(x: 16, y: 16, width: 232, height: 172)))
        let exportContent = try #require(exported.cropping(to: CGRect(x: 4, y: 4, width: 232, height: 172)))
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
        state.beginAnnotation(tool: .rectangle, at: CGPoint(x: 80, y: 30), color: .red, lineWidth: 2)
        state.updateAnnotation(to: CGPoint(x: 100, y: 70))
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
        state.beginAnnotation(tool: .arrow, at: CGPoint(x: 40, y: 40), color: .red, lineWidth: 2)
        state.updateAnnotation(to: CGPoint(x: 90, y: 70))

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

    @Test
    func drawingRestoresCallerTransformAndClip() throws {
        let context = try bitmapContext(width: 80, height: 80)
        context.translateBy(x: 3, y: 7)
        context.clip(to: CGRect(x: 0, y: 0, width: 60, height: 60))
        let transform = context.ctm
        let clip = context.boundingBoxOfClipPath

        Renderer().drawAnnotations(
            [OverlayAnnotation(kind: .arrow, pointsInImageSpace: [.zero, CGPoint(x: 20, y: 20)])],
            imageSize: CGSize(width: 40, height: 40),
            in: context,
            destinationRect: CGRect(x: 10, y: 10, width: 20, height: 20)
        )

        #expect(context.ctm == transform)
        #expect(context.boundingBoxOfClipPath == clip)
    }

    private func addAnnotation(tool: OverlayAnnotationTool, to state: RegionSelectionState) {
        state.beginAnnotation(
            tool: tool,
            at: CGPoint(x: 40, y: 40),
            color: tool == .highlight ? NSColor.red.withAlphaComponent(0.3) : .red,
            lineWidth: 2,
            fontSize: 14
        )
        if tool == .text {
            state.updateDraftText("Aa")
            state.commitDraftText()
        } else {
            state.updateAnnotation(to: CGPoint(x: 90, y: 70))
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
        let data = try Renderer().renderPNG(baseImage: base, annotations: state.annotations)
        let decoder = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
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
        #expect(misplacedPixels == 0)
        #expect(maximumChannelDifference <= 20)
    }

    private func redInkMask(_ pixels: [UInt8]) -> [Bool] {
        stride(from: 0, to: pixels.count, by: 4).map { index in
            Int(pixels[index]) - Int(min(pixels[index + 1], pixels[index + 2])) >= 24
        }
    }
}
