import AppKit

enum RenderError: Error {
    case missingCGImage
    case missingBitmapContext
    case pngEncodingFailed
}

final class Renderer {
    func renderPNG(baseImage: CGImage, annotations: [OverlayAnnotation]) throws -> Data {
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

        for annotation in annotations {
            draw(annotation, in: context, imageHeight: CGFloat(height))
        }

        guard let outputImage = context.makeImage() else { throw RenderError.missingCGImage }
        return try PNGEncoder.encode(outputImage)
    }

    private func draw(_ annotation: OverlayAnnotation, in context: CGContext, imageHeight: CGFloat) {
        if annotation.kind == .text {
            drawText(annotation, in: context, imageHeight: imageHeight)
            return
        }

        let strokeColor = annotation.color.usingColorSpace(.deviceRGB) ?? annotation.color
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(annotation.kind == .rectangle ? .butt : .round)

        if annotation.kind == .arrow {
            drawArrow(annotation, in: context, imageHeight: imageHeight)
            return
        }

        if let rect = annotation.rectInImageSpace {
            context.stroke(flip(rect, imageHeight: imageHeight))
            return
        }

        guard let firstPoint = annotation.pointsInImageSpace.first else { return }
        context.beginPath()
        context.move(to: flip(firstPoint, imageHeight: imageHeight))
        for point in annotation.pointsInImageSpace.dropFirst() {
            context.addLine(to: flip(point, imageHeight: imageHeight))
        }
        context.strokePath()
    }

    private func drawArrow(_ annotation: OverlayAnnotation, in context: CGContext, imageHeight: CGFloat) {
        guard
            let startPoint = annotation.pointsInImageSpace.first,
            let endPoint = annotation.pointsInImageSpace.last
        else {
            return
        }

        let start = flip(startPoint, imageHeight: imageHeight)
        let end = flip(endPoint, imageHeight: imageHeight)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)

        let dx = end.x - start.x
        let dy = end.y - start.y
        if hypot(dx, dy) >= 1 {
            let angle = atan2(dy, dx)
            let headLength = max(annotation.lineWidth * 4, 10)
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

    private func drawText(_ annotation: OverlayAnnotation, in context: CGContext, imageHeight: CGFloat) {
        guard let position = annotation.textPositionInImageSpace, !annotation.text.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
            .foregroundColor: annotation.color
        ]
        let drawPoint = CGPoint(
            x: position.x,
            y: imageHeight - position.y - annotation.fontSize
        )
        annotation.text.draw(at: drawPoint, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func flip(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private func flip(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }
}
