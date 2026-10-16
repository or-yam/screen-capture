import AppKit
import CoreGraphics

/// Renderer-accurate annotation geometry in the stable top-left canvas.
///
/// The PNG renderer and the select/move interaction must agree on the painted
/// extent, the hit region, and the arrowhead shape, so both derive them here
/// instead of maintaining separate approximations. Every input and output is a
/// top-left canvas coordinate (`AnnotationCanvas`), never AppKit screen space.
///
/// Strokes follow the renderer's creation-time pixel basis. The renderer scales
/// its stroke space vertically by `creationPixelSizeInCanvas.height /
/// creationPixelSizeInCanvas.width`, so a canvas stroke is an ellipse that is
/// `lineWidth / 2` wide in X and `lineWidth / 2 * verticalScale` tall in Y.
/// Painted bounds use that anisotropic extent; hit tolerance stays a
/// screen-point value and is deliberately not distorted by that basis.
enum AnnotationGeometry {
    // MARK: - Public interface

    /// The painted extent of `annotation`, including stroke width, arrowheads,
    /// round caps, and TextKit line/text bounds (with blank-line spacing).
    static func paintedBounds(of annotation: OverlayAnnotation) -> CGRect {
        if annotation.kind == .text {
            return textBounds(of: annotation)
        }

        return paintedStrokePath(of: annotation)?.boundingBoxOfPath ?? .zero
    }

    /// Hit-test the painted ink at a top-left canvas `point`.
    ///
    /// `tolerance` is a screen-point radius applied uniformly in canvas space so
    /// thin strokes and arrowheads stay usable regardless of display density or
    /// an anisotropic creation basis. A rectangle's empty interior is not ink,
    /// so it does not hit. Text is hit anywhere inside its laid-out block,
    /// including blank lines.
    static func hitTest(
        _ annotation: OverlayAnnotation,
        at point: CGPoint,
        tolerance: CGFloat = 4
    ) -> Bool {
        if annotation.kind == .text {
            let bounds = textBounds(of: annotation)
            guard !bounds.isEmpty else { return false }
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }

        guard let painted = paintedStrokePath(of: annotation) else { return false }
        if painted.contains(point) { return true }
        guard tolerance > 0 else { return false }
        // Expand the actual painted shape AFTER mapping it to screen points.
        // This preserves anisotropic ink while keeping hit slop isotropic.
        return painted.copy(strokingWithWidth: tolerance * 2, lineCap: .round,
                            lineJoin: .round, miterLimit: 10).contains(point)
    }

    /// Translate an annotation in canvas space.
    ///
    /// Only geometry moves: identity, kind, color, stroke/font style, text and
    /// its line breaks, arrowhead settings, and the creation-time pixel basis
    /// are all preserved by the value copy.
    static func translated(_ annotation: OverlayAnnotation, by delta: CGSize) -> OverlayAnnotation {
        var moved = annotation
        moved.pointsInCanvas = annotation.pointsInCanvas.map {
            CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
        }
        if let rect = annotation.rectInCanvas {
            moved.rectInCanvas = rect.offsetBy(dx: delta.width, dy: delta.height)
        }
        if let position = annotation.textPositionInCanvas {
            moved.textPositionInCanvas = CGPoint(x: position.x + delta.width, y: position.y + delta.height)
        }
        return moved
    }

    /// Clamp a proposed canvas translation so painted ink stays on `bounds`.
    ///
    /// `bounds` is the owning display in top-left canvas space. On a normal axis
    /// the whole painted extent (stroke and arrowheads included) stays inside.
    /// On an oversized axis, where the content cannot fit, the item's geometry
    /// anchor is clamped inside the display instead, preserving the content and
    /// letting the excess clip rather than shrinking, wrapping, or freezing it.
    static func constrainedTranslation(
        of annotation: OverlayAnnotation,
        proposed delta: CGSize,
        within bounds: CGRect
    ) -> CGSize {
        guard !bounds.isEmpty else { return .zero }

        let painted = paintedBounds(of: annotation)
        let anchor = annotation.textPositionInCanvas ?? annotation.rectInCanvas?.origin
            ?? annotation.pointsInCanvas.first ?? painted.origin
        return CGSize(
            width: constrainedDelta(
                paintedMin: painted.minX,
                paintedLength: painted.width,
                anchor: anchor.x,
                displayMin: bounds.minX,
                displayLength: bounds.width,
                proposed: delta.width
            ),
            height: constrainedDelta(
                paintedMin: painted.minY,
                paintedLength: painted.height,
                anchor: anchor.y,
                displayMin: bounds.minY,
                displayLength: bounds.height,
                proposed: delta.height
            )
        )
    }

    // MARK: - Shared with the renderer

    /// The renderer's vertical stroke-space scale for this annotation.
    static func verticalScale(for annotation: OverlayAnnotation) -> CGFloat {
        let width = annotation.creationPixelSizeInCanvas.width
        guard width != 0 else { return 1 }
        return annotation.creationPixelSizeInCanvas.height / width
    }

    /// Arrowhead wing points in top-left canvas space, or an empty array when
    /// the head is suppressed for a very short shaft.
    ///
    /// This reproduces the renderer's stroke-space math exactly. It is the one
    /// arrowhead definition shared by drawing and geometry.
    static func arrowheadPointsInCanvas(for annotation: OverlayAnnotation) -> [CGPoint] {
        guard
            annotation.kind == .arrow,
            let start = annotation.pointsInCanvas.first,
            let end = annotation.pointsInCanvas.last,
            annotation.pointsInCanvas.count >= 2
        else {
            return []
        }

        let scale = verticalScale(for: annotation)
        // Renderer stroke space flips Y and divides it by `scale`.
        let dx = end.x - start.x
        let dy = -(end.y - start.y) / scale
        guard hypot(dx, dy) >= annotation.minimumArrowheadLength / 10 else { return [] }

        let angle = atan2(dy, dx)
        let headLength = max(annotation.lineWidth * 4, annotation.minimumArrowheadLength)
        let headAngle = CGFloat.pi / 7
        // Convert each stroke-space wing back into canvas space (Y reverses and
        // rescales by `scale`).
        return [
            CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y + scale * headLength * sin(angle - headAngle)
            ),
            CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y + scale * headLength * sin(angle + headAngle)
            )
        ]
    }

    // MARK: - Private geometry

    private static func textBounds(of annotation: OverlayAnnotation) -> CGRect {
        guard let position = annotation.textPositionInCanvas else { return .zero }

        let pixelSize = annotation.creationPixelSizeInCanvas
        guard
            !annotation.text.isEmpty,
            pixelSize.width != 0,
            pixelSize.height != 0,
            annotation.fontSize > 0
        else {
            return CGRect(origin: position, size: .zero)
        }

        let layout = AnnotationTextLayout(
            text: annotation.text,
            font: .systemFont(ofSize: annotation.fontSize / pixelSize.height, weight: .semibold),
            color: annotation.color
        )
        let content = layout.contentSize
        return CGRect(
            origin: position,
            size: CGSize(width: content.width * pixelSize.width, height: content.height * pixelSize.height)
        )
    }

    private static func segments(of annotation: OverlayAnnotation) -> [(CGPoint, CGPoint)] {
        switch annotation.kind {
        case .rectangle:
            guard let rect = annotation.rectInCanvas, !rect.isEmpty else { return [] }
            let topLeft = CGPoint(x: rect.minX, y: rect.minY)
            let topRight = CGPoint(x: rect.maxX, y: rect.minY)
            let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
            let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
            return [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]

        case .arrow:
            let points = annotation.pointsInCanvas
            guard let start = points.first, let end = points.last, points.count >= 2 else { return [] }
            var result = [(start, end)]
            for head in arrowheadPointsInCanvas(for: annotation) {
                result.append((end, head))
            }
            return result

        case .draw, .highlight:
            let points = annotation.pointsInCanvas
            guard let first = points.first else { return [] }
            guard points.count >= 2 else { return [(first, first)] }
            return zip(points, points.dropFirst()).map { pair in (pair.0, pair.1) }

        case .text:
            return []
        }
    }

    private static func paintedStrokePath(of annotation: OverlayAnnotation) -> CGPath? {
        let scale = verticalScale(for: annotation)
        guard scale > 0, annotation.lineWidth > 0 else { return nil }
        let segments = segments(of: annotation)
        guard !segments.isEmpty else { return nil }
        let path = CGMutablePath()
        for (start, end) in segments {
            path.move(to: CGPoint(x: start.x, y: start.y / scale))
            path.addLine(to: CGPoint(x: end.x, y: end.y / scale))
        }
        let stroke = path.copy(strokingWithWidth: annotation.lineWidth, lineCap: .round,
                               lineJoin: .round, miterLimit: 10)
        var transform = CGAffineTransform(scaleX: 1, y: scale)
        return stroke.copy(using: &transform)
    }

    private static func constrainedDelta(
        paintedMin: CGFloat,
        paintedLength: CGFloat,
        anchor: CGFloat,
        displayMin: CGFloat,
        displayLength: CGFloat,
        proposed: CGFloat
    ) -> CGFloat {
        let displayMax = displayMin + displayLength
        if paintedLength <= displayLength {
            // Text or a stroke created at the screen edge may already be
            // clipped. Preserve the grab offset: allow recovery toward the
            // screen, but never increase existing overflow or snap it inward.
            let lower = min(0, displayMin - paintedMin)
            let upper = max(0, displayMax - (paintedMin + paintedLength))
            return min(max(proposed, lower), upper)
        }

        // Oversized axis: keep the creation anchor, not the stroke's min bound,
        // inside the display. Stroke extent must not cause a correction jump.
        let lower = displayMin - anchor
        let upper = displayMax - anchor
        return min(max(proposed, lower), upper)
    }
}
