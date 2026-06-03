import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable {
    case arrow
    case ellipse
    case rectangle
    case pen
    case text
    case blur
}

enum Annotation {
    case arrow(start: CGPoint, end: CGPoint, color: Color, width: CGFloat)
    case ellipse(rect: CGRect, color: Color, width: CGFloat)
    case rectangle(rect: CGRect, color: Color, width: CGFloat)
    case line(start: CGPoint, end: CGPoint, color: Color, width: CGFloat)
    case pen(points: [CGPoint], color: Color, width: CGFloat)
    case text(String, position: CGPoint, color: Color, fontSize: CGFloat)
    case blur(rect: CGRect, radius: CGFloat)

}

extension Annotation {
    func draw(in context: inout GraphicsContext) {
        switch self {
        case let .arrow(start, end, color, width):
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), lineWidth: width)
        case let .ellipse(rect, color, width):
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)
        case let .rectangle(rect, color, width):
            context.stroke(Path(rect), with: .color(color), lineWidth: width)
        case let .line(start, end, color, width):
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), lineWidth: width)
        case let .pen(points, color, width):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), lineWidth: width)
        case let .text(value, position, color, fontSize):
            context.draw(Text(value).font(.system(size: fontSize)).foregroundColor(color), at: position, anchor: .topLeading)
        case let .blur(rect, _):
            context.fill(Path(rect), with: .color(.gray.opacity(0.4)))
        }
    }
}

@MainActor
final class AnnotationModel: ObservableObject {
    let baseImage: NSImage

    @Published var annotations: [Annotation] = []
    @Published var selectedTool: AnnotationTool = .arrow
    @Published var selectedColor: Color = .red

    init(baseImage: NSImage) {
        self.baseImage = baseImage
    }

    func addSampleText() {
        annotations.append(.text("Text", position: CGPoint(x: 24, y: 24), color: selectedColor, fontSize: 28))
    }

    func undo() {
        _ = annotations.popLast()
    }
}
