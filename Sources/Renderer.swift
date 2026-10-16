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
    ///
    /// `previewClip`, in destination/context coordinates, replaces the
    /// `destinationRect` clip for overflow preview while the selection-to-
    /// destination transform is preserved. The PNG renderer leaves it `nil` so
    /// export stays clipped to the capture frame. Independently, each annotation
    /// is always confined to its owning display when it declares one.
    func drawAnnotations(
        _ annotations: [OverlayAnnotation],
        canvas: AnnotationCanvas,
        selectionRect: CGRect,
        in context: CGContext,
        destinationRect: CGRect,
        previewClip: CGRect? = nil
    ) {
        guard let transform = canvas.transform(selectionRect: selectionRect, destinationRect: destinationRect) else {
            return
        }

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: previewClip ?? destinationRect)
        context.concatenate(transform)
        // Draw in a bottom-left version of the entire canvas so AppKit text
        // remains upright. Geometry is flipped below, not relative to the crop.
        let canvasHeight = canvas.frameInAppKitScreenSpace.height
        context.translateBy(x: 0, y: canvasHeight)
        context.scaleBy(x: 1, y: -1)

        for annotation in annotations {
            context.saveGState()
            // Geometry is now in the bottom-left canvas used by draw().
            // Flip the owner clip too; vertically arranged screens otherwise
            // clip ink on the wrong half of the shared canvas.
            if let ownerClip = ownerClipInCanvas(of: annotation, canvas: canvas) {
                context.clip(to: ownerClip)
            }
            draw(annotation, in: context, canvasHeight: canvasHeight)
            context.restoreGState()
        }
    }

    /// The owner display frame converted to bottom-left canvas coordinates, or `nil`
    /// for legacy annotations that predate per-annotation display identity.
    private func ownerClipInCanvas(of annotation: OverlayAnnotation, canvas: AnnotationCanvas) -> CGRect? {
        guard let frame = annotation.displayFrameInAppKitScreenSpace else { return nil }
        let topLeft = canvas.rect(fromScreen: frame)
        return CGRect(x: topLeft.minX, y: canvas.frameInAppKitScreenSpace.height - topLeft.maxY,
                      width: topLeft.width, height: topLeft.height)
    }

    private func draw(_ annotation: OverlayAnnotation, in context: CGContext, canvasHeight: CGFloat) {
        if annotation.kind == .text {
            drawText(annotation, in: context, canvasHeight: canvasHeight)
            return
        }

        // Stroke in the creation-time pixel basis, compensating the path so its
        // canvas position stays fixed. This preserves even anisotropic brushes.
        let verticalScale = AnnotationGeometry.verticalScale(for: annotation)
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

        // The head is defined once in AnnotationGeometry so painted bounds,
        // hit testing, and drawing cannot drift apart. `flip` maps the shared
        // canvas-space wings back into this stroke space.
        for headPoint in AnnotationGeometry.arrowheadPointsInCanvas(for: annotation) {
            context.move(to: end)
            context.addLine(to: flip(headPoint, canvasHeight: canvasHeight, verticalScale: verticalScale))
        }

        context.strokePath()
    }

    private func drawText(_ annotation: OverlayAnnotation, in context: CGContext, canvasHeight: CGFloat) {
        guard let position = annotation.textPositionInCanvas, !annotation.text.isEmpty else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: position.x, y: canvasHeight - position.y)
        context.scaleBy(x: annotation.creationPixelSizeInCanvas.width, y: -annotation.creationPixelSizeInCanvas.height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let layout = AnnotationTextLayout(
            text: annotation.text,
            font: .systemFont(ofSize: annotation.fontSize / annotation.creationPixelSizeInCanvas.height, weight: .semibold),
            color: annotation.color
        )
        let glyphs = layout.manager.glyphRange(for: layout.container)
        layout.manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }

    private func flip(_ rect: CGRect, canvasHeight: CGFloat, verticalScale: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: (canvasHeight - rect.maxY) / verticalScale, width: rect.width, height: rect.height / verticalScale)
    }

    private func flip(_ point: CGPoint, canvasHeight: CGFloat, verticalScale: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: (canvasHeight - point.y) / verticalScale)
    }
}
