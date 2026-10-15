import AppKit
import ImageIO

/// Standalone diagnostic experiment, compiled with the current production sources.
/// No Screen Recording permission or live desktop capture is used.
@main
struct CropQualityProbe {
    @MainActor
    static func main() throws {
        var cases = 0
        let configurations = [(1, 1), (2, 2), (2, 1)].flatMap { density in
            [CGPoint.zero, CGPoint(x: -80, y: -40), CGPoint(x: 80, y: 100)].map {
                (density.0, density.1, $0)
            }
        }
        for (scaleX, scaleY, origin) in configurations {
            let source = try stripes(width: 64 * scaleX, height: 64 * scaleY)
            let frame = CGRect(origin: origin, size: CGSize(width: 64, height: 64))
            let display = DisplayGeometry(
                localizedName: "Synthetic \(scaleX)x\(scaleY)",
                frameInDisplaySpace: frame,
                frameInAppKitScreenSpace: frame,
                backingScaleFactor: CGFloat(scaleX)
            )
            for offset in [0.0, 0.25, 0.5, 0.75] {
                let state = RegionSelectionState(snapshots: [DisplaySnapshot(display: display, image: source)])
                let rect = CGRect(x: origin.x + 10 + offset, y: origin.y + 10 + offset, width: 20.5, height: 18.75)
                try state.setCapturedImageFromFrozenSnapshots(for: rect)
                guard let crop = state.capturedImage else { throw ProbeError.missingImage }
                let sourceRect = CGRect(
                    x: (rect.minX - frame.minX) * CGFloat(scaleX),
                    y: (frame.maxY - rect.maxY) * CGFloat(scaleY),
                    width: rect.width * CGFloat(scaleX), height: rect.height * CGFloat(scaleY)
                ).integral
                guard let expected = source.cropping(to: sourceRect), let aligned = state.selectionRect else {
                    throw ProbeError.missingImage
                }
                let cropBytes = try pixels(crop)
                guard crop.width == expected.width, crop.height == expected.height,
                      cropBytes == (try pixels(expected)),
                      abs(aligned.width * CGFloat(scaleX) - CGFloat(crop.width)) < 0.000001,
                      abs(aligned.height * CGFloat(scaleY) - CGFloat(crop.height)) < 0.000001,
                      abs(aligned.minX - (frame.minX + sourceRect.minX / CGFloat(scaleX))) < 0.000001,
                      abs(aligned.maxY - (frame.maxY - sourceRect.minY / CGFloat(scaleY))) < 0.000001,
                      frame.contains(aligned), aligned.contains(rect) else { throw ProbeError.baselineChanged }
                let grayPixels = stride(from: 0, to: cropBytes.count, by: 4).filter {
                    cropBytes[$0] > 0 && cropBytes[$0] < 255
                }.count
                let png = try Renderer().renderPNG(baseImage: crop, annotations: [])
                guard let decoder = CGImageSourceCreateWithData(png as CFData, nil),
                      let exported = CGImageSourceCreateImageAtIndex(decoder, 0, nil) else {
                    throw ProbeError.missingImage
                }
                let exportBytes = try pixels(exported)
                let differences = zip(cropBytes, exportBytes).filter { $0 != $1 }.count
                print("scale=\(scaleX)x\(scaleY) origin=\(origin) offset=\(offset) crop=\(crop.width)x\(crop.height) grayPixels=\(grayPixels)/\(crop.width * crop.height) exportChangedBytes=\(differences)")
                if grayPixels != 0 || differences != 0 || exported.width != crop.width || exported.height != crop.height {
                    throw ProbeError.baselineChanged
                }
                try state.setCapturedImageFromFrozenSnapshots(for: aligned)
                guard state.selectionRect == aligned,
                      let recrop = state.capturedImage, try pixels(recrop) == cropBytes else {
                    throw ProbeError.baselineChanged
                }
                for _ in 0..<4 {
                    guard let start = state.selectionRect else { throw ProbeError.missingImage }
                    state.moveAnchoredSelection(from: start, by: NSSize(width: 0.3, height: -0.3))
                    guard let moved = state.selectionRect else { throw ProbeError.missingImage }
                    try state.setCapturedImageFromFrozenSnapshots(for: moved)
                    guard let movedCrop = state.capturedImage,
                          movedCrop.width == crop.width, movedCrop.height == crop.height else {
                        throw ProbeError.baselineChanged
                    }
                }
                state.beginAnnotation(tool: .rectangle, at: CGPoint(x: 4, y: 4), color: .systemRed, lineWidth: 2)
                state.updateAnnotation(to: CGPoint(x: 12, y: 10))
                state.commitAnnotation()
                guard let movedCrop = state.capturedImage else { throw ProbeError.missingImage }
                let annotatedData = try Renderer().renderPNG(baseImage: movedCrop, annotations: state.annotations)
                guard let annotatedSource = CGImageSourceCreateWithData(annotatedData as CFData, nil),
                      let annotated = CGImageSourceCreateImageAtIndex(annotatedSource, 0, nil),
                      state.annotations.count == 1,
                      annotated.width == crop.width, annotated.height == crop.height,
                      try pixels(annotated) != pixels(movedCrop) else { throw ProbeError.baselineChanged }
                cases += 1
            }
        }
        try checkBoundariesAndCompositing()
        try checkFractionalDensity()
        print("PASS: \(cases) pixel-identity, aligned-geometry, repeat-crop, move-size, and annotation cases; display boundary and compositor checks")
    }

    @MainActor
    private static func checkFractionalDensity() throws {
        let source = try stripes(width: 3840, height: 128)
        for origin in [CGPoint.zero, CGPoint(x: -2304, y: -100)] {
            let frame = CGRect(origin: origin, size: CGSize(width: 2304, height: 64))
            let display = DisplayGeometry(localizedName: "Fractional density", frameInDisplaySpace: frame,
                                          frameInAppKitScreenSpace: frame, backingScaleFactor: 2)
            let state = RegionSelectionState(snapshots: [DisplaySnapshot(display: display, image: source)])
            try state.setCapturedImageFromFrozenSnapshots(for: CGRect(x: origin.x + 128.4, y: origin.y + 10.25, width: 21, height: 20))
            guard let first = state.capturedImage, let aligned = state.selectionRect,
                  first.width == 35, first.height == 41 else { throw ProbeError.baselineChanged }
            let firstBytes = try pixels(first)
            for _ in 0..<8 {
                guard let rect = state.selectionRect else { throw ProbeError.missingImage }
                state.moveAnchoredSelection(from: rect, by: .zero)
                guard let moved = state.selectionRect else { throw ProbeError.missingImage }
                try state.setCapturedImageFromFrozenSnapshots(for: moved)
                guard let image = state.capturedImage, image.width == first.width, image.height == first.height,
                      state.selectionRect == aligned, try pixels(image) == firstBytes else {
                    throw ProbeError.baselineChanged
                }
            }
        }
        print("PASS: non-integer 5/3 X density with repeated zero-delta moves/crops at positive and negative origins")
    }

    @MainActor
    private static func checkBoundariesAndCompositing() throws {
        let source = try stripes(width: 64, height: 64)
        let frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        let display = DisplayGeometry(localizedName: "First", frameInDisplaySpace: frame, frameInAppKitScreenSpace: frame, backingScaleFactor: 1)
        let snapshot = DisplaySnapshot(display: display, image: source)
        let state = RegionSelectionState(snapshots: [snapshot])
        for rect in [frame, CGRect(x: 63.25, y: 63.25, width: 0.75, height: 0.75)] {
            try state.setCapturedImageFromFrozenSnapshots(for: rect)
            guard let aligned = state.selectionRect, frame.contains(aligned), aligned.contains(rect) else {
                throw ProbeError.baselineChanged
            }
        }
        var secondDisplay = display
        secondDisplay.localizedName = "Second"
        secondDisplay.frameInAppKitScreenSpace.origin.x = 64
        secondDisplay.frameInDisplaySpace.origin.x = 64
        let composite = RegionSelectionState(snapshots: [snapshot, DisplaySnapshot(display: secondDisplay, image: source)])
        for rect in [CGRect(x: 60.25, y: 10.25, width: 8.5, height: 20.5),
                     CGRect(x: -2.25, y: 10.25, width: 8.5, height: 20.5)] {
            try composite.setCapturedImageFromFrozenSnapshots(for: rect)
            guard composite.selectionRect == rect, let image = composite.capturedImage,
                  image.width == 9, image.height == 21 else { throw ProbeError.baselineChanged }
        }
        do {
            try state.setCapturedImageFromFrozenSnapshots(for: .zero)
            throw ProbeError.baselineChanged
        } catch ScreenshotCaptureError.emptyRegion { }
    }

    private static func stripes(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { throw ProbeError.missingImage }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let value: UInt8 = x.isMultiple(of: 2) ? 0 : 255
                bytes[index] = value
                // Asymmetric channels catch crop location and vertical-flip errors.
                bytes[index + 1] = UInt8(y % 256)
                bytes[index + 2] = UInt8((x + y * 3) % 256)
                bytes[index + 3] = 255
            }
        }
        guard let image = context.makeImage() else { throw ProbeError.missingImage }
        return image
    }

    private static func pixels(_ image: CGImage) throws -> [UInt8] {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { throw ProbeError.missingImage }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private enum ProbeError: Error {
        case missingImage
        case baselineChanged
    }
}
