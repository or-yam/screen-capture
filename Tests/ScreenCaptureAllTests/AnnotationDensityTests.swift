import AppKit
import ImageIO
import Testing
@testable import ScreenCaptureAll

@MainActor
struct AnnotationDensityTests {
    struct Density: Sendable {
        let x: CGFloat
        let y: CGFloat
    }

    nonisolated static let densities = [
        Density(x: 1, y: 1),
        Density(x: 2, y: 2),
        Density(x: 2, y: 1),
        Density(x: 5.0 / 3.0, y: 2)
    ]

    @Test(arguments: OverlayAnnotationTool.allCases, densities)
    func initialToolAppearanceMatchesIndependentPixelGeometry(tool: OverlayAnnotationTool, density: Density) throws {
        let background = try landmarkImage(width: 240, height: 180)
        let frame = CGRect(x: -137, y: 23, width: 240 / density.x, height: 180 / density.y)
        let state = RegionSelectionState(snapshots: [snapshot(frame: frame, image: background)])
        try state.setCapturedImageFromFrozenSnapshots(for: frame)
        let canvas = try #require(state.annotationCanvas)
        let selection = try #require(state.capturedSelectionRect)
        let image = try #require(state.capturedImage)
        #expect(image.width == 240)
        #expect(image.height == 180)

        let pixelPoints = [
            CGPoint(x: 41, y: 39), CGPoint(x: 67, y: 84),
            CGPoint(x: 119, y: 61), CGPoint(x: 167, y: 113)
        ]
        // These conversions do not use AnnotationCanvas's destination transform.
        // Inputs represent the same original image-pixel geometry at every density.
        let canvasPoints = pixelPoints.map { point in
            canvas.point(fromScreen: CGPoint(
                x: selection.minX + point.x * selection.width / 240,
                y: selection.maxY - point.y * selection.height / 180
            ))
        }

        // Exercise both the minimum arrowhead and the stroke-dependent head size.
        let strokeWidths: [CGFloat] = tool == .text ? [2] : [2, 5]
        for strokeWidth in strokeWidths {
            state.beginAnnotation(tool: tool, at: canvasPoints[0], color: .red, lineWidth: strokeWidth, fontSize: 22)
            if tool == .text {
                state.updateDraftText("Wim 42")
                state.commitDraftText()
            } else {
                for point in canvasPoints.dropFirst() {
                    state.updateAnnotation(to: point)
                }
                state.commitAnnotation()
            }

            let annotation = try #require(state.annotations.last)
            #expect(abs(annotation.creationPixelSizeInCanvas.width - 1 / density.x) < 0.000001)
            #expect(abs(annotation.creationPixelSizeInCanvas.height - 1 / density.y) < 0.000001)
            let actual = try renderedImage(
                background: background, annotations: [annotation], canvas: canvas, selection: selection
            )

            // Construct the legacy pixel-valued mark independently; in particular,
            // never derive this reference by rescaling the stored canvas annotation.
            let referenceAnnotation = OverlayAnnotation(
                kind: tool,
                rectInCanvas: tool == .rectangle ? CGRect(
                    x: 41, y: 39, width: 126, height: 74
                ) : nil,
                pointsInCanvas: tool == .arrow ? [pixelPoints[0], pixelPoints[3]] : pixelPoints,
                text: tool == .text ? "Wim 42" : "",
                textPositionInCanvas: tool == .text ? pixelPoints[0] : nil,
                color: tool == .highlight ? NSColor.red.withAlphaComponent(0.35) : .red,
                lineWidth: tool == .highlight ? strokeWidth * 3 : strokeWidth,
                fontSize: 22
            )
            let pixelFrame = CGRect(x: 0, y: 0, width: 240, height: 180)
            let reference = try renderedImage(
                background: background,
                annotations: [referenceAnnotation],
                canvas: AnnotationCanvas(frameInAppKitScreenSpace: pixelFrame),
                selection: pixelFrame
            )
            let difference = try pixelDifference(actual, reference, tolerance: 20)
            #expect(difference.pixelsOverTolerance == 0, "Maximum channel difference: \(difference.maximumChannelDifference)")
            #expect(try pixels(actual) != pixels(background))
        }
    }

    @Test(arguments: densities)
    func noAnnotationsPreserveAsymmetricBackgroundPixels(density: Density) throws {
        let background = try landmarkImage(width: 240, height: 180)
        let frame = CGRect(x: -137, y: 23, width: 240 / density.x, height: 180 / density.y)
        let state = RegionSelectionState(snapshots: [snapshot(frame: frame, image: background)])
        try state.setCapturedImageFromFrozenSnapshots(for: frame)
        let captured = try #require(state.capturedImage)
        #expect(try pixels(captured) == pixels(background))
        let output = try renderedImage(
            background: captured, annotations: [],
            canvas: try #require(state.annotationCanvas),
            selection: try #require(state.capturedSelectionRect)
        )
        #expect(output.width == background.width)
        #expect(output.height == background.height)
        #expect(try pixels(output) == pixels(background))
    }

    @Test
    func fractionalDisplaySeamDoesNotAddTransparentPixels() throws {
        let snapshots = [
            snapshot(frame: CGRect(x: -240, y: 0, width: 240, height: 180), image: try landmarkImage(width: 240, height: 180)),
            snapshot(frame: CGRect(x: 0, y: 0, width: 240, height: 180), image: try landmarkImage(width: 400, height: 300))
        ]
        let state = RegionSelectionState(snapshots: snapshots)
        try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: -200, y: 20, width: 260, height: 120))
        let bytes = try pixels(#require(state.capturedImage))
        let transparent = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] != 255 }.count
        #expect(transparent == 0)
    }

    @Test
    func fractionalCompositePreservesFullSnapshotContentCoordinates() throws {
        // Neither axis retains the nominal 5/3 density after rounding outward.
        try expectCompositeMatchesFullSnapshots(
            selection: CGRect(x: -71.35, y: -17.2, width: 135.7, height: 56.45),
            expectedWidth: 227, expectedHeight: 95
        )
    }

    @Test
    func roundedCompositeUsesActualIndependentOutputDensities() throws {
        // The source intersections are integral on both displays. This isolates
        // output-allocation rounding from fractional source-crop expansion.
        try expectCompositeMatchesFullSnapshots(
            selection: CGRect(x: -71, y: -17, width: 131, height: 56),
            expectedWidth: 219, expectedHeight: 94
        )
    }

    private func expectCompositeMatchesFullSnapshots(
        selection: CGRect, expectedWidth: Int, expectedHeight: Int
    ) throws {
        let snapshots = [
            snapshot(
                frame: CGRect(x: -120, y: -40, width: 120, height: 100),
                image: try landmarkImage(width: 120, height: 100)
            ),
            snapshot(
                frame: CGRect(x: 0, y: -40, width: 120, height: 100),
                image: try landmarkImage(width: 200, height: 200)
            )
        ]
        let state = RegionSelectionState(snapshots: snapshots)
        try state.setCapturedImageFromFrozenSnapshots(for: selection)
        let actual = try #require(state.capturedImage)
        #expect(state.capturedSelectionRect == selection)
        #expect(actual.width == expectedWidth)
        #expect(actual.height == expectedHeight)

        let referenceContext = try bitmapContext(width: expectedWidth, height: expectedHeight)
        let scaleX = CGFloat(expectedWidth) / selection.width
        let scaleY = CGFloat(expectedHeight) / selection.height
        referenceContext.clip(to: CGRect(x: 0, y: 0, width: expectedWidth, height: expectedHeight))
        for snapshot in snapshots {
            let frame = snapshot.display.frameInAppKitScreenSpace
            // Draw the entire source at its screen location, clipped by the
            // output bitmap. No source .integral crop or intersection stretching.
            referenceContext.draw(snapshot.image, in: CGRect(
                x: (frame.minX - selection.minX) * scaleX,
                y: (frame.minY - selection.minY) * scaleY,
                width: frame.width * scaleX,
                height: frame.height * scaleY
            ))
        }
        let reference = try #require(referenceContext.makeImage())
        let seamX = (0 - selection.minX) * scaleX
        // Full images and cropped images can use different interpolation kernels.
        // Compare color-weighted landmark centers within a quarter output pixel,
        // not exact edge coverage. The integral-source control verifies the same
        // tolerance without fractional source expansion.
        let leftBarActual = try landmarkCenter(actual, including: { x, _ in CGFloat(x) < seamX - 3 }) { red, green, blue in
            max(0, min(red, blue) - green)
        }
        let leftBarReference = try landmarkCenter(reference, including: { x, _ in CGFloat(x) < seamX - 3 }) { red, green, blue in
            max(0, min(red, blue) - green)
        }
        let rightSearchRect = CGRect(
            x: (35 - selection.minX) * scaleX,
            y: CGFloat(expectedHeight) - (-5 - selection.minY) * scaleY,
            width: 22 * scaleX, height: 12 * scaleY
        )
        let rightBlockActual = try landmarkCenter(actual, including: { x, y in
            rightSearchRect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
        }) { red, green, blue in
            max(0, green - max(red, blue))
        }
        let rightBlockReference = try landmarkCenter(reference, including: { x, y in
            rightSearchRect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
        }) { red, green, blue in
            max(0, green - max(red, blue))
        }
        #expect(abs(leftBarActual.x - leftBarReference.x) <= 0.25)
        #expect(abs(rightBlockActual.x - rightBlockReference.x) <= 0.25)
        #expect(abs(rightBlockActual.y - rightBlockReference.y) <= 0.25)
    }

    private func snapshot(frame: CGRect, image: CGImage) -> DisplaySnapshot {
        DisplaySnapshot(display: DisplayGeometry(
            localizedName: "Synthetic density fixture",
            frameInDisplaySpace: frame,
            frameInAppKitScreenSpace: frame,
            backingScaleFactor: CGFloat(image.width) / frame.width
        ), image: image)
    }

    private func renderedImage(
        background: CGImage, annotations: [OverlayAnnotation], canvas: AnnotationCanvas, selection: CGRect
    ) throws -> CGImage {
        let data = try Renderer().renderPNG(
            baseImage: background, annotations: annotations, canvas: canvas, selectionRect: selection
        )
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func landmarkImage(width: Int, height: Int) throws -> CGImage {
        let context = try bitmapContext(width: width, height: height)
        context.setFillColor(NSColor(deviceRed: 0.08, green: 0.19, blue: 0.31, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Unequal, off-center bars distinguish X/Y shifts, stretching, and flips.
        let landmarks: [(CGRect, NSColor)] = [
            (CGRect(x: 13, y: 17, width: 7, height: height - 29), NSColor(deviceRed: 0.9, green: 0.71, blue: 0.12, alpha: 1)),
            (CGRect(x: width / 3, y: height / 4, width: 19, height: 11), NSColor(deviceRed: 0.13, green: 0.82, blue: 0.45, alpha: 1)),
            (CGRect(x: width / 2 + 7, y: 9, width: 5, height: height - 21), NSColor(deviceRed: 0.68, green: 0.28, blue: 0.83, alpha: 1)),
            (CGRect(x: 8, y: height * 2 / 3, width: width - 31, height: 9), NSColor(deviceRed: 0.18, green: 0.61, blue: 0.88, alpha: 1))
        ]
        for (rect, color) in landmarks {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
        return try #require(context.makeImage())
    }

    private func bitmapContext(width: Int, height: Int) throws -> CGContext {
        try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try bitmapContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4
        ))
    }

    private func landmarkCenter(
        _ image: CGImage, including: (Int, Int) -> Bool,
        weight: (Int, Int, Int) -> Int
    ) throws -> CGPoint {
        let bytes = try pixels(image)
        var totalWeight: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        for y in 3..<(image.height - 3) {
            for x in 3..<(image.width - 3) where including(x, y) {
                let offset = (y * image.width + x) * 4
                let contribution = CGFloat(weight(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])))
                totalWeight += contribution
                weightedX += (CGFloat(x) + 0.5) * contribution
                weightedY += (CGFloat(y) + 0.5) * contribution
            }
        }
        try #require(totalWeight > 0)
        return CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)
    }

    private func pixelDifference(
        _ actual: CGImage, _ reference: CGImage, tolerance: Int
    ) throws -> (pixelsOverTolerance: Int, maximumChannelDifference: Int) {
        try #require(actual.width == reference.width && actual.height == reference.height)
        let actualPixels = try pixels(actual)
        let referencePixels = try pixels(reference)
        var pixelsOverTolerance = 0
        var maximumChannelDifference = 0
        for y in 0..<actual.height {
            for x in 0..<actual.width {
                let offset = (y * actual.width + x) * 4
                let difference = (0..<4).map { channel in
                    abs(Int(actualPixels[offset + channel]) - Int(referencePixels[offset + channel]))
                }.max() ?? 0
                maximumChannelDifference = max(maximumChannelDifference, difference)
                if difference > tolerance {
                    pixelsOverTolerance += 1
                }
            }
        }
        return (pixelsOverTolerance, maximumChannelDifference)
    }
}
