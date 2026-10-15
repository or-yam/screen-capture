import AppKit

enum RenderError: Error {
    case missingCGImage
    case missingBitmapContext
    case pngEncodingFailed
}

final class Renderer {
    func renderPNG(
        baseImage: CGImage,
        annotations: [OverlayAnnotation],
        canvas: AnnotationCanvas,
        selectionRect: CGRect
    ) throws -> Data {
        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.missingBitmapContext
        }

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(baseImage, in: imageRect)

        drawAnnotations(
            annotations,
            canvas: canvas,
            selectionRect: selectionRect,
            in: context,
            destinationRect: imageRect
        )

        guard let outputImage = context.makeImage() else { throw RenderError.missingCGImage }
        return try PNGEncoder.encode(outputImage)
    }

    /// Preview and export share a stable screen-point canvas. Clipping must not
    /// change either the selection frame or the full destination frame.
    func drawAnnotations(
        _ annotations: [OverlayAnnotation],
        canvas: AnnotationCanvas,
        selectionRect: CGRect,
        in context: CGContext,
        destinationRect: CGRect
    ) {
        guard let transform = canvas.transform(selectionRect: selectionRect, destinationRect: destinationRect) else {
            return
        }

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: destinationRect)
        context.concatenate(transform)
        // Draw in a bottom-left version of the entire canvas so AppKit text
        // remains upright. Geometry is flipped below, not relative to the crop.
        let canvasHeight = canvas.frameInAppKitScreenSpace.height
        context.translateBy(x: 0, y: canvasHeight)
        context.scaleBy(x: 1, y: -1)

        for annotation in annotations {
            draw(annotation, in: context, canvasHeight: canvasHeight)
        }
    }

    private func draw(_ annotation: OverlayAnnotation, in context: CGContext, canvasHeight: CGFloat) {
        if annotation.kind == .text {
            drawText(annotation, in: context, canvasHeight: canvasHeight)
            return
        }

        // Stroke in the creation-time pixel basis, compensating the path so its
        // canvas position stays fixed. This preserves even anisotropic brushes.
        let verticalScale = annotation.creationPixelSizeInCanvas.height / annotation.creationPixelSizeInCanvas.width
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: 1, y: verticalScale)
        let strokeColor = annotation.color.usingColorSpace(.deviceRGB) ?? annotation.color
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(annotation.kind == .rectangle ? .butt : .round)

        if annotation.kind == .arrow {
            drawArrow(annotation, in: context, canvasHeight: canvasHeight, verticalScale: verticalScale)
            return
        }

        if let rect = annotation.rectInCanvas {
            context.stroke(flip(rect, canvasHeight: canvasHeight, verticalScale: verticalScale))
            return
        }

        guard let firstPoint = annotation.pointsInCanvas.first else { return }
        context.beginPath()
        context.move(to: flip(firstPoint, canvasHeight: canvasHeight, verticalScale: verticalScale))
        for point in annotation.pointsInCanvas.dropFirst() {
            context.addLine(to: flip(point, canvasHeight: canvasHeight, verticalScale: verticalScale))
        }
        context.strokePath()
    }

    private func drawArrow(_ annotation: OverlayAnnotation, in context: CGContext, canvasHeight: CGFloat, verticalScale: CGFloat) {
        guard
            let startPoint = annotation.pointsInCanvas.first,
            let endPoint = annotation.pointsInCanvas.last
        else {
            return
        }

        let start = flip(startPoint, canvasHeight: canvasHeight, verticalScale: verticalScale)
        let end = flip(endPoint, canvasHeight: canvasHeight, verticalScale: verticalScale)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)

        let dx = end.x - start.x
        let dy = end.y - start.y
        // The legacy head appeared at one image pixel of shaft length. Its
        // ten-pixel minimum is converted at creation, so retain that ratio in
        // canvas units rather than introducing a one-screen-point threshold.
        if hypot(dx, dy) >= annotation.minimumArrowheadLength / 10 {
            let angle = atan2(dy, dx)
            let headLength = max(annotation.lineWidth * 4, annotation.minimumArrowheadLength)
            let headAngle = CGFloat.pi / 7
            let firstHeadPoint = CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y - headLength * sin(angle - headAngle)
            )
            let secondHeadPoint = CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y - headLength * sin(angle + headAngle)
            )
            context.move(to: end)
            context.addLine(to: firstHeadPoint)
            context.move(to: end)
            context.addLine(to: secondHeadPoint)
        }

        context.strokePath()
    }

    private func drawText(_ annotation: OverlayAnnotation, in context: CGContext, canvasHeight: CGFloat) {
        guard let position = annotation.textPositionInCanvas, !annotation.text.isEmpty else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: position.x, y: canvasHeight - position.y - annotation.fontSize)
        context.scaleBy(x: annotation.creationPixelSizeInCanvas.width, y: annotation.creationPixelSizeInCanvas.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            // Reconstruct the creation-time font, not a smaller font scaled up:
            // macOS optical sizing changes glyph metrics at different font sizes.
            .font: NSFont.systemFont(ofSize: annotation.fontSize / annotation.creationPixelSizeInCanvas.height, weight: .semibold),
            .foregroundColor: annotation.color
        ]
        annotation.text.draw(at: .zero, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func flip(_ rect: CGRect, canvasHeight: CGFloat, verticalScale: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: (canvasHeight - rect.maxY) / verticalScale, width: rect.width, height: rect.height / verticalScale)
    }

    private func flip(_ point: CGPoint, canvasHeight: CGFloat, verticalScale: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: (canvasHeight - point.y) / verticalScale)
    }
}
