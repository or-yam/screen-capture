import AppKit

/// Shared vector silhouette for the app icon and the monochrome status item.
///
/// `Scripts/build_app_icon.sh` compiles this file standalone alongside
/// `Scripts/generate_app_icon.swift`, so it must stay self-contained: do not
/// reference any other source file in this target.
enum BrandMark {
    // Coordinates use a 1024-point canvas, with AppKit's bottom-left origin.
    static func path() -> NSBezierPath {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.move(to: NSPoint(x: 201, y: 289))
        path.curve(to: NSPoint(x: 772, y: 715),
                   controlPoint1: NSPoint(x: 65, y: 467),
                   controlPoint2: NSPoint(x: 596, y: 813))
        path.curve(to: NSPoint(x: 201, y: 289),
                   controlPoint1: NSPoint(x: 1011, y: 563),
                   controlPoint2: NSPoint(x: 395, y: 140))
        path.close()
        path.move(to: NSPoint(x: 260, y: 355))
        path.curve(to: NSPoint(x: 737, y: 653),
                   controlPoint1: NSPoint(x: 158, y: 455),
                   controlPoint2: NSPoint(x: 610, y: 715))
        path.curve(to: NSPoint(x: 260, y: 355),
                   controlPoint1: NSPoint(x: 880, y: 565),
                   controlPoint2: NSPoint(x: 386, y: 253))
        path.close()
        return path
    }

    static func tail() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 320, y: 300))
        path.curve(to: NSPoint(x: 680, y: 302),
                   controlPoint1: NSPoint(x: 413, y: 246),
                   controlPoint2: NSPoint(x: 560, y: 264))
        path.lineWidth = 55
        path.lineCapStyle = .round
        return path
    }

    static func dot() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 763, y: 333))
        path.line(to: NSPoint(x: 806, y: 355))
        path.lineWidth = 62
        path.lineCapStyle = .round
        return path
    }

    static func drawSilhouette() {
        tail().stroke()
        path().fill()
        dot().stroke()
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            // Enlarge the mark within the menu-bar canvas, without the app tile margin.
            transform.translateX(by: -1, yBy: -2)
            transform.scale(by: rect.width / 900)
            transform.concat()
            NSColor.black.set()
            drawSilhouette()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Screen Capture All"
        return image
    }
}
