import AppKit
import SwiftUI

enum RenderError: Error {
    case missingCGImage
    case missingBitmapContext
    case pngEncodingFailed
}

final class Renderer {
    func renderPNG(baseImage: NSImage, annotations: [Annotation]) throws -> Data {
        guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RenderError.missingCGImage
        }

        let width = cgImage.width
        let height = cgImage.height
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

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: rect)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for annotation in annotations {
            draw(annotation, imageHeight: CGFloat(height))
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let outputImage = context.makeImage() else { throw RenderError.missingCGImage }
        let bitmap = NSBitmapImageRep(cgImage: outputImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodingFailed
        }
        return data
    }

    private func draw(_ annotation: Annotation, imageHeight: CGFloat) {
        switch annotation {
        case let .arrow(start, end, color, width):
            strokeLine(from: start, to: end, color: color, width: width, imageHeight: imageHeight)
        case let .ellipse(rect, color, width):
            strokePath(NSBezierPath(ovalIn: flip(rect, imageHeight: imageHeight)), color: color, width: width)
        case let .rectangle(rect, color, width):
            strokePath(NSBezierPath(rect: flip(rect, imageHeight: imageHeight)), color: color, width: width)
        case let .line(start, end, color, width):
            strokeLine(from: start, to: end, color: color, width: width, imageHeight: imageHeight)
        case let .pen(points, color, width):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: flip(first, imageHeight: imageHeight))
            for point in points.dropFirst() {
                path.line(to: flip(point, imageHeight: imageHeight))
            }
            strokePath(path, color: color, width: width)
        case let .text(value, position, color, fontSize):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(color)
            ]
            value.draw(at: flip(position, imageHeight: imageHeight), withAttributes: attributes)
        case let .blur(rect, _):
            NSColor.gray.withAlphaComponent(0.4).setFill()
            NSBezierPath(rect: flip(rect, imageHeight: imageHeight)).fill()
        }
    }

    private func strokeLine(from start: CGPoint, to end: CGPoint, color: Color, width: CGFloat, imageHeight: CGFloat) {
        let path = NSBezierPath()
        path.move(to: flip(start, imageHeight: imageHeight))
        path.line(to: flip(end, imageHeight: imageHeight))
        strokePath(path, color: color, width: width)
    }

    private func strokePath(_ path: NSBezierPath, color: Color, width: CGFloat) {
        NSColor(color).setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private func flip(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private func flip(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }
}
