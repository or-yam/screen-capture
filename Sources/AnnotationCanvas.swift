import CoreGraphics

/// Immutable screen-point coordinates shared by every annotation in a capture.
/// Canvas (0, 0) is the top-left of the frozen snapshots' screen-space bounds.
struct AnnotationCanvas {
    let frameInAppKitScreenSpace: CGRect

    init(frameInAppKitScreenSpace: CGRect) {
        self.frameInAppKitScreenSpace = frameInAppKitScreenSpace
    }

    func point(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - frameInAppKitScreenSpace.minX,
            y: frameInAppKitScreenSpace.maxY - point.y
        )
    }

    func screenPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(
            x: frameInAppKitScreenSpace.minX + point.x,
            y: frameInAppKitScreenSpace.maxY - point.y
        )
    }

    func rect(fromScreen rect: CGRect) -> CGRect {
        CGRect(
            origin: point(fromScreen: CGPoint(x: rect.minX, y: rect.maxY)),
            size: rect.size
        )
    }

    /// Maps top-left canvas coordinates into a bottom-left destination frame.
    /// Supply the complete selection and destination, even when a display's
    /// graphics context clips away part of them. X/Y densities are independent.
    func transform(selectionRect: CGRect, destinationRect: CGRect) -> CGAffineTransform? {
        guard !selectionRect.isEmpty, !destinationRect.isEmpty else { return nil }

        let selectionInCanvas = rect(fromScreen: selectionRect)
        let scaleX = destinationRect.width / selectionRect.width
        let scaleY = destinationRect.height / selectionRect.height
        return CGAffineTransform(
            a: scaleX,
            b: 0,
            c: 0,
            d: -scaleY,
            tx: destinationRect.minX - selectionInCanvas.minX * scaleX,
            ty: destinationRect.maxY + selectionInCanvas.minY * scaleY
        )
    }
}
