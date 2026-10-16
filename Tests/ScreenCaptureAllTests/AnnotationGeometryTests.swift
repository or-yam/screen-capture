import AppKit
import Testing
@testable import ScreenCaptureAll

/// Geometry tests for `AnnotationGeometry` plus the renderer seams it backs.
///
/// These assert explicit canvas/pixel geometry rather than comparing two calls
/// to the same code path, and they keep screen-point hit tolerance independent
/// of the anisotropic creation-pixel basis.
@MainActor
struct AnnotationGeometryTests {
    // MARK: - Painted bounds

    @Test
    func rectanglePaintedBoundsIncludeStrokeOnEverySide() {
        let annotation = OverlayAnnotation(
            kind: .rectangle,
            rectInCanvas: CGRect(x: 10, y: 20, width: 100, height: 50),
            color: .red,
            lineWidth: 8
        )
        #expect(AnnotationGeometry.paintedBounds(of: annotation) == CGRect(x: 6, y: 16, width: 108, height: 58))
    }

    @Test
    func paintedBoundsUseAnisotropicStrokeBasis() {
        // 8-point stroke with a 2:1 vertical basis is 4 wide in X and 8 tall in Y.
        let annotation = OverlayAnnotation(
            kind: .rectangle,
            rectInCanvas: CGRect(x: 10, y: 20, width: 100, height: 50),
            color: .red,
            lineWidth: 8,
            creationPixelSizeInCanvas: CGSize(width: 0.5, height: 1)
        )
        #expect(AnnotationGeometry.paintedBounds(of: annotation) == CGRect(x: 6, y: 12, width: 108, height: 66))
    }

    @Test
    func arrowPaintedBoundsIncludeArrowheadWings() {
        let annotation = OverlayAnnotation(
            kind: .arrow,
            pointsInCanvas: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            color: .red,
            lineWidth: 4,
            minimumArrowheadLength: 10
        )
        let bounds = AnnotationGeometry.paintedBounds(of: annotation)
        let wings = AnnotationGeometry.arrowheadPointsInCanvas(for: annotation)

        #expect(wings.count == 2)
        #expect(abs(bounds.maxX - 102) < 0.001) // tip plus half stroke
        #expect(bounds.minY <= -8 && bounds.maxY >= 8) // wings extend beyond the 4-wide shaft
        #expect(bounds.contains(wings[0]) && bounds.contains(wings[1]))
    }

    @Test
    func veryShortArrowSuppressesArrowhead() {
        let annotation = OverlayAnnotation(
            kind: .arrow,
            pointsInCanvas: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0)],
            color: .red,
            lineWidth: 4,
            minimumArrowheadLength: 10
        )
        #expect(AnnotationGeometry.arrowheadPointsInCanvas(for: annotation).isEmpty)
        #expect(AnnotationGeometry.paintedBounds(of: annotation) == CGRect(x: -2, y: -2, width: 4.5, height: 4))
    }

    @Test
    func arrowheadAppearsExactlyAtMinimumLengthThreshold() {
        let annotation = OverlayAnnotation(
            kind: .arrow,
            pointsInCanvas: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)],
            color: .red,
            lineWidth: 4,
            minimumArrowheadLength: 10
        )
        #expect(AnnotationGeometry.arrowheadPointsInCanvas(for: annotation).count == 2)
    }

    // MARK: - Hit testing

    @Test
    func rectangleInteriorIsNotAHitButEdgesAre() {
        let annotation = OverlayAnnotation(
            kind: .rectangle,
            rectInCanvas: CGRect(x: 10, y: 10, width: 100, height: 50),
            color: .red,
            lineWidth: 4
        )
        #expect(!AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 60, y: 35)), "empty interior is not ink")
        #expect(AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 10, y: 35)), "left edge")
        #expect(AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 60, y: 7)), "tolerance above the top edge")
        #expect(!AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 60, y: -20)), "far outside")
    }

    @Test(arguments: [
        CGSize(width: 1, height: 1),
        CGSize(width: 0.5, height: 0.5),
        CGSize(width: 0.5, height: 1)
    ])
    func hitToleranceIsScreenPointsRegardlessOfDensity(basis: CGSize) {
        let annotation = OverlayAnnotation(
            kind: .draw,
            pointsInCanvas: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            color: .red,
            lineWidth: 4 * basis.width,
            creationPixelSizeInCanvas: basis
        )
        // A fixed four-screen-point offset always hits, even on Retina.
        #expect(AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 50, y: 4)))
        // Just past the stroke radius plus tolerance, it misses.
        let beyond = annotation.lineWidth / 2 * basis.height / basis.width + 4 + 1.5
        #expect(!AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 50, y: beyond)))
    }

    @Test
    func arrowheadWingIsHittableAwayFromTheShaft() {
        let annotation = OverlayAnnotation(
            kind: .arrow,
            pointsInCanvas: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            color: .red,
            lineWidth: 4,
            minimumArrowheadLength: 10
        )
        let wing = AnnotationGeometry.arrowheadPointsInCanvas(for: annotation)[0]
        // A point on the wing is seven points from the shaft, beyond the
        // shaft's own 6-point allowance, so only the head can satisfy it.
        #expect(AnnotationGeometry.hitTest(annotation, at: CGPoint(x: wing.x, y: wing.y)))
        #expect(!AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 50, y: 20)))
    }

    @Test
    func multilineTextBoundsIncludeBlankLineSpacing() {
        let single = AnnotationGeometry.paintedBounds(of: textAnnotation("First"))
        let two = AnnotationGeometry.paintedBounds(of: textAnnotation("First\nThird"))
        let three = AnnotationGeometry.paintedBounds(of: textAnnotation("First\n\nThird"))

        #expect(single.origin == CGPoint(x: 10, y: 20))
        #expect(single.width > 0)
        #expect(single.height > 0)
        #expect(two.height > single.height)
        #expect(three.height > two.height, "a blank middle line still adds its line spacing")
    }

    @Test
    func textHitTestingTreatsTheBlockAsOneItemIncludingBlankLines() {
        let text = "First\n\nThird"
        let annotation = textAnnotation(text)
        let bounds = AnnotationGeometry.paintedBounds(of: annotation)

        // A point in the blank-line gap between the first and third lines still
        // hits, because the block is a single item.
        #expect(AnnotationGeometry.hitTest(annotation, at: CGPoint(x: bounds.midX, y: bounds.midY)))
        #expect(!AnnotationGeometry.hitTest(annotation, at: CGPoint(x: bounds.minX, y: bounds.maxY + 4 + 2)))
    }

    @Test
    func emptyTextDoesNotHit() {
        let annotation = OverlayAnnotation(kind: .text, text: "", textPositionInCanvas: CGPoint(x: 10, y: 20), color: .red, fontSize: 18)
        #expect(!AnnotationGeometry.hitTest(annotation, at: CGPoint(x: 10, y: 20)))
    }

    @Test
    func anisotropicPaintedInkAndIsotropicSlopBothHit() {
        let mark = OverlayAnnotation(kind: .highlight,
            pointsInCanvas: [CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 30)],
            lineWidth: 12, creationPixelSizeInCanvas: CGSize(width: 0.5, height: 1))
        #expect(AnnotationGeometry.hitTest(mark, at: CGPoint(x: 50, y: 41), tolerance: 0))
        #expect(AnnotationGeometry.hitTest(mark, at: CGPoint(x: 50, y: 45), tolerance: 4))
        #expect(!AnnotationGeometry.hitTest(mark, at: CGPoint(x: 50, y: 47), tolerance: 4))
        #expect(AnnotationGeometry.hitTest(mark, at: CGPoint(x: 12, y: 30), tolerance: 4))
        #expect(!AnnotationGeometry.hitTest(mark, at: CGPoint(x: 9, y: 30), tolerance: 4))
    }

    // MARK: - Translation

    @Test
    func translatedPreservesIdentityContentAndStyle() {
        let id = UUID()
        let original = OverlayAnnotation(
            id: id,
            kind: .arrow,
            pointsInCanvas: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)],
            text: "unchanged",
            color: .systemBlue,
            lineWidth: 6,
            fontSize: 21,
            minimumArrowheadLength: 13,
            creationPixelSizeInCanvas: CGSize(width: 0.5, height: 0.5)
        )
        let moved = AnnotationGeometry.translated(original, by: CGSize(width: 7, height: -3))

        #expect(moved.id == id)
        #expect(moved.kind == .arrow)
        #expect(moved.color == original.color)
        #expect(moved.lineWidth == 6)
        #expect(moved.fontSize == 21)
        #expect(moved.minimumArrowheadLength == 13)
        #expect(moved.creationPixelSizeInCanvas == CGSize(width: 0.5, height: 0.5))
        #expect(moved.text == "unchanged")
        #expect(moved.pointsInCanvas == [CGPoint(x: 17, y: 7), CGPoint(x: 57, y: 37)])
    }

    @Test
    func translationMovesRectangleAndTextGeometry() {
        let rectangleID = UUID()
        let rectangle = OverlayAnnotation(
            id: rectangleID,
            kind: .rectangle,
            rectInCanvas: CGRect(x: 10, y: 20, width: 30, height: 40),
            color: .red,
            lineWidth: 5
        )
        let movedRectangle = AnnotationGeometry.translated(rectangle, by: CGSize(width: 3, height: -7))
        #expect(movedRectangle.id == rectangleID)
        #expect(movedRectangle.rectInCanvas == CGRect(x: 13, y: 13, width: 30, height: 40))
        #expect(movedRectangle.pointsInCanvas.isEmpty)

        let text = OverlayAnnotation(
            kind: .text,
            text: "A\nB",
            textPositionInCanvas: CGPoint(x: 5, y: 6),
            color: .red,
            fontSize: 18
        )
        let movedText = AnnotationGeometry.translated(text, by: CGSize(width: 2, height: 3))
        #expect(movedText.textPositionInCanvas == CGPoint(x: 7, y: 9))
        #expect(movedText.text == "A\nB")
    }

    // MARK: - Constrained translation

    @Test
    func constrainedTranslationKeepsPaintedInkInsideTheDisplay() {
        let annotation = OverlayAnnotation(
            kind: .rectangle,
            rectInCanvas: CGRect(x: 10, y: 10, width: 100, height: 50),
            color: .red,
            lineWidth: 8
        )
        let display = CGRect(x: 0, y: 0, width: 200, height: 200)

        // Painted bounds are (6, 6, 108, 58). Using painted ink, not the bare
        // rectangle, limits the positive X move to 200 - 114 = 86.
        #expect(AnnotationGeometry.constrainedTranslation(
            of: annotation, proposed: CGSize(width: 1000, height: 1000), within: display
        ) == CGSize(width: 86, height: 136))
        #expect(AnnotationGeometry.constrainedTranslation(
            of: annotation, proposed: CGSize(width: -1000, height: -1000), within: display
        ) == CGSize(width: -6, height: -6))
        #expect(AnnotationGeometry.constrainedTranslation(
            of: annotation, proposed: CGSize(width: 10, height: 10), within: display
        ) == CGSize(width: 10, height: 10))
    }

    @Test
    func oversizedAxisClampsAnchorWithinDisplayInsteadOfFreezing() {
        let annotation = OverlayAnnotation(
            kind: .rectangle,
            rectInCanvas: CGRect(x: 0, y: 0, width: 300, height: 50),
            color: .red,
            lineWidth: 4
        )
        let display = CGRect(x: 0, y: 0, width: 200, height: 200)
        let painted = AnnotationGeometry.paintedBounds(of: annotation)
        #expect(painted.width > display.width)

        // X is oversized: the anchor may traverse the whole display width rather
        // than being immovable; Y cannot increase existing edge clipping.
        #expect(AnnotationGeometry.constrainedTranslation(
            of: annotation, proposed: CGSize(width: 1000, height: 1000), within: display
        ) == CGSize(width: 200, height: 148))
        #expect(AnnotationGeometry.constrainedTranslation(
            of: annotation, proposed: CGSize(width: -1000, height: -1000), within: display
        ) == .zero)
    }

    @Test
    func constrainedTranslationOnEmptyDisplayIsZero() {
        let annotation = OverlayAnnotation(kind: .draw, pointsInCanvas: [.zero, CGPoint(x: 10, y: 10)], lineWidth: 4)
        #expect(AnnotationGeometry.constrainedTranslation(
            of: annotation, proposed: CGSize(width: 50, height: 50), within: .zero
        ) == .zero)
    }

    @Test
    func initiallyClippedInkDoesNotJumpOrMoveFartherOffscreen() {
        let mark = OverlayAnnotation(kind: .rectangle, rectInCanvas: CGRect(x: 180, y: 40, width: 30, height: 30), lineWidth: 4)
        let display = CGRect(x: 0, y: 0, width: 200, height: 200)
        #expect(AnnotationGeometry.constrainedTranslation(of: mark, proposed: CGSize(width: 0, height: 10), within: display) == CGSize(width: 0, height: 10))
        #expect(AnnotationGeometry.constrainedTranslation(of: mark, proposed: CGSize(width: 10, height: 0), within: display) == .zero)
        #expect(AnnotationGeometry.constrainedTranslation(of: mark, proposed: CGSize(width: -5, height: 0), within: display) == CGSize(width: -5, height: 0))
        #expect(AnnotationGeometry.constrainedTranslation(of: mark, proposed: CGSize(width: -500, height: 0), within: display) == CGSize(width: -178, height: 0))
    }

    // MARK: - Renderer seams

    @Test
    func previewClipConfinesInkAndReplacesDestinationClip() throws {
        // The stroke now runs to canvas x=140, past the 100-point frame, so its
        // ink has to be clipped by whichever rectangle is active.
        let annotation = OverlayAnnotation(
            kind: .draw,
            pointsInCanvas: [CGPoint(x: 10, y: 50), CGPoint(x: 140, y: 50)],
            color: .red,
            lineWidth: 8
        )
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        // At 1:1 the default destination clip is the only thing stopping the
        // stroke, leaving ink in the full frame's last column.
        let full = try render([annotation], frame: frame, destination: frame)
        #expect(try maxInkColumn(full) == 99, "the default clip confines the overlong stroke")

        // Rescaling 100 -> 30 would place canvas x=140 at destination x=42, so a
        // last column of 29 proves the default destination clip actually bites
        // rather than the ink merely fitting inside the destination.
        let export = try render([annotation], frame: frame, destination: CGRect(x: 0, y: 0, width: 30, height: 100))
        #expect(try maxInkColumn(export) == 29, "with no preview clip, export stays destination clipped")

        // The overlay's preview clip replaces the destination clip while the
        // selection-to-destination transform is unchanged.
        let overflowPreview = try render(
            [annotation], frame: frame, destination: frame,
            previewClip: CGRect(x: 0, y: 0, width: 30, height: 100)
        )
        #expect(try maxInkColumn(overflowPreview) == 29, "preview clip replaces the destination clip")
    }

    @Test
    func rendererPaintsArrowheadAtSharedGeometryWings() throws {
        let annotation = OverlayAnnotation(
            kind: .arrow,
            pointsInCanvas: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
            color: .red,
            lineWidth: 4,
            minimumArrowheadLength: 10
        )
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = try render([annotation], frame: frame, destination: frame)

        // In this symmetric layout a top-left canvas point lands on image row
        // `y - 1`, so the wing ink is verifiable directly in image pixels.
        for wing in AnnotationGeometry.arrowheadPointsInCanvas(for: annotation) {
            #expect(try ink(aroundImagePoint: CGPoint(x: wing.x, y: wing.y), in: image, radius: 3))
        }
    }

    @Test
    func ownerDisplayFrameClipsInkInPreviewAndExport() throws {
        // The owning display covers only the left half of the capture frame.
        let annotation = OverlayAnnotation(
            kind: .draw,
            pointsInCanvas: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
            color: .red,
            lineWidth: 8,
            displayID: 1,
            displayFrameInAppKitScreenSpace: CGRect(x: 0, y: 0, width: 50, height: 100)
        )
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        let image = try render([annotation], frame: frame, destination: frame)
        #expect(try maxInkColumn(image) < 50, "ink is confined to the owning display")
        #expect(try maxInkColumn(image) > 10, "ink inside the owning display is preserved")
    }

    @Test
    func verticallyArrangedOwnerClipUsesTheCorrectCanvasHalf() throws {
        let frame = CGRect(x: -50, y: -100, width: 100, height: 200)
        // Lower screen in AppKit coordinates is the lower half of this canvas.
        let annotation = OverlayAnnotation(kind: .draw,
            pointsInCanvas: [CGPoint(x: 10, y: 150), CGPoint(x: 90, y: 150)],
            color: .red, lineWidth: 8, displayID: 1,
            displayFrameInAppKitScreenSpace: CGRect(x: -50, y: -100, width: 100, height: 100))
        let image = try render([annotation], frame: frame, destination: CGRect(x: 0, y: 0, width: 100, height: 200))
        #expect(try maxInkColumn(image) > 85)
        #expect(try ink(aroundImagePoint: CGPoint(x: 50, y: 150), in: image, radius: 2))
        #expect(try !ink(aroundImagePoint: CGPoint(x: 50, y: 50), in: image, radius: 2))
    }

    // MARK: - Helpers

    private func textAnnotation(_ text: String) -> OverlayAnnotation {
        OverlayAnnotation(
            kind: .text,
            text: text,
            textPositionInCanvas: CGPoint(x: 10, y: 20),
            color: .red,
            fontSize: 18
        )
    }

    private func render(
        _ annotations: [OverlayAnnotation],
        frame: CGRect,
        selection: CGRect? = nil,
        destination: CGRect,
        previewClip: CGRect? = nil
    ) throws -> CGImage {
        let context = try bitmapContext(width: Int(frame.width), height: Int(frame.height))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        Renderer().drawAnnotations(
            annotations,
            canvas: AnnotationCanvas(frameInAppKitScreenSpace: frame),
            selectionRect: selection ?? frame,
            in: context,
            destinationRect: destination,
            previewClip: previewClip
        )
        return try #require(context.makeImage())
    }

    private func maxInkColumn(_ image: CGImage) throws -> Int {
        let mask = try redInkMask(pixels(image))
        var maximum = -1
        for (index, isInk) in mask.enumerated() where isInk {
            maximum = max(maximum, index % image.width)
        }
        return maximum
    }

    private func ink(aroundImagePoint point: CGPoint, in image: CGImage, radius: Int) throws -> Bool {
        let mask = try redInkMask(pixels(image))
        let centerX = Int(point.x.rounded())
        let centerY = Int(point.y.rounded())
        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = centerX + dx
                let y = centerY + dy
                guard x >= 0, x < image.width, y >= 0, y < image.height else { continue }
                if mask[y * image.width + x] { return true }
            }
        }
        return false
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

    private func redInkMask(_ pixels: [UInt8]) -> [Bool] {
        stride(from: 0, to: pixels.count, by: 4).map { index in
            Int(pixels[index]) - Int(min(pixels[index + 1], pixels[index + 2])) >= 24
        }
    }
}
