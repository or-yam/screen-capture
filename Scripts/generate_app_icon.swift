import AppKit

/// Render each native icon size directly from vector artwork.
@main
struct GenerateAppIcon {
    static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func render(pixels: Int, dark: Bool) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                                xRadius: 205, yRadius: 205)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.42 : 0.18)
        shadow.shadowBlurRadius = 32
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        (dark ? color(0.055, 0.055, 0.075) : color(0.97, 0.97, 0.99)).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: dark ? color(0.14, 0.15, 0.19) : color(1, 1, 1),
                   ending: dark ? color(0.035, 0.035, 0.055) : color(0.94, 0.93, 0.97))!
            .draw(in: tile, angle: -75)

        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        // Soft reflected color, deliberately much quieter than the foreground ribbon.
        for (center, tint) in [
            (NSPoint(x: 280, y: 280), color(0.22, 0.32, 1, dark ? 0.10 : 0.12)),
            (NSPoint(x: 780, y: 300), color(1, 0.31, 0.26, dark ? 0.10 : 0.10))
        ] {
            let gradient = NSGradient(starting: tint, ending: tint.withAlphaComponent(0))!
            gradient.draw(fromCenter: center, radius: 0,
                          toCenter: center, radius: 440, options: [])
        }
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor.white.withAlphaComponent(0.055) : NSColor.white.withAlphaComponent(0.7)).setStroke()
        tile.lineWidth = 2
        tile.stroke()

        // Render a colored ribbon into a silhouette mask, retaining a continuous gradient.
        let mark = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            NSColor.white.set()
            BrandMark.drawSilhouette()
            NSGraphicsContext.current!.compositingOperation = .sourceIn
            let gradient = NSGradient(colorsAndLocations:
                (color(0.02, 0.67, 1), 0),
                (color(0.06, 0.29, 1), 0.24),
                (color(0.52, 0.16, 1), 0.47),
                (color(0.95, 0.22, 0.85), 0.66),
                (color(1, 0.39, 0.40), 0.84),
                (color(1, 0.57, 0.28), 1))!
            gradient.draw(from: NSPoint(x: 220, y: 590), to: NSPoint(x: 790, y: 340), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        let ribbonShadow = NSShadow()
        ribbonShadow.shadowColor = color(0.24, 0.09, 0.65, dark ? 0.18 : 0.23)
        ribbonShadow.shadowBlurRadius = 18
        ribbonShadow.shadowOffset = NSSize(width: 0, height: -10)
        ribbonShadow.set()
        mark.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func preview() -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 760,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        defer { NSGraphicsContext.restoreGraphicsState() }
        for dark in [false, true] {
            let x: CGFloat = dark ? 600 : 0
            (dark ? color(0.08, 0.09, 0.11) : color(0.94, 0.95, 0.97)).setFill()
            NSRect(x: x, y: 0, width: 600, height: 760).fill()
            let image = NSImage(data: render(pixels: 1024, dark: dark))!
            image.draw(in: NSRect(x: x + 44, y: 204, width: 512, height: 512))
            let ink = dark ? NSColor.white : NSColor.black
            (dark ? "DARK" : "LIGHT").draw(at: NSPoint(x: x + 32, y: 720), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink
            ])
            // Draw the same vector used by the template image at actual menu-bar size.
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: x + 90, yBy: 123)
            transform.scale(by: 20.0 / 900)
            transform.concat()
            ink.set()
            BrandMark.drawSilhouette()
            NSGraphicsContext.restoreGraphicsState()
            for (offset, size) in [(190.0, 32.0), (290.0, 64.0), (410.0, 96.0)] {
                image.draw(in: NSRect(x: x + offset, y: 84, width: size, height: size))
            }
        }
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: generate-app-icon <output-directory>")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for dark in [false, true] {
            let name = dark ? "AppIcon-Dark" : "AppIcon"
            let iconset = output.appendingPathComponent("\(name).iconset", isDirectory: true)
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for size in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let suffix = scale == 2 ? "@2x" : ""
                    try render(pixels: size * scale, dark: dark)
                        .write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
                }
            }
            try render(pixels: 1024, dark: dark).write(to: output.appendingPathComponent("\(name)-preview.png"))
        }
        try preview().write(to: output.appendingPathComponent("Icon-kit-preview.png"))
    }
}
