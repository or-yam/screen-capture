import AppKit

/// Render the DMG window background image.
///
/// The geometry below mirrors `Scripts/make_dmg_layout.sh`, which is what tells
/// Finder where to place the app icon and the `Applications` symlink. Finder
/// records icon positions from the top-left corner of the window's content area,
/// AppKit draws from the bottom-left, so every vertical constant is mirrored
/// through `height`.
@main
struct GenerateDMGBackground {
    /// Content area of the DMG window. `Scripts/make_dmg_layout.sh` sets the window
    /// bounds to this plus the title bar, so the image is drawn at 1:1.
    static let width: CGFloat = 660
    static let height: CGFloat = 400

    /// Icon centres measured from the top of the content area, as Finder sees them.
    static let iconBandFromTop: CGFloat = 195
    static let appIconX: CGFloat = 170
    static let applicationsIconX: CGFloat = 490
    static let iconSize: CGFloat = 128

    /// The icon band in AppKit's bottom-left coordinates.
    static var iconBand: CGFloat { height - iconBandFromTop }

    static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func centered() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    /// The application mark, scaled from its 1024-point canvas into `size` points,
    /// painted with the same gradient as the app icon.
    static func mark(in size: CGFloat) -> NSImage {
        // BrandMark's ink occupies roughly x 190...868, y 246...715 of its canvas;
        // mapping that box to a centred square avoids a mark that looks off-centre
        // or clipped.
        let scale = (size - 4) / 680
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: 2 - 190 * scale,
                                 yBy: (size - (715 - 246) * scale) / 2 - 246 * scale)
            transform.scale(by: scale)
            transform.concat()
            NSColor.white.set()
            BrandMark.drawSilhouette()
            NSGraphicsContext.current!.compositingOperation = .sourceIn
            NSGradient(colorsAndLocations:
                (color(0.02, 0.67, 1), 0),
                (color(0.06, 0.29, 1), 0.24),
                (color(0.52, 0.16, 1), 0.47),
                (color(0.95, 0.22, 0.85), 0.66),
                (color(1, 0.39, 0.40), 0.84),
                (color(1, 0.57, 0.28), 1))!
                .draw(from: NSPoint(x: 190, y: 480), to: NSPoint(x: 868, y: 480),
                      options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            return true
        }
    }

    static func draw(footer: String, title: String) {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)

        NSGradient(starting: color(0.988, 0.988, 0.996),
                   ending: color(0.933, 0.933, 0.957))!
            .draw(in: bounds, angle: -90)

        // A very quiet colour wash behind the drag target, so the middle of the
        // window reads as paper rather than as a decorated poster.
        for (center, tint) in [
            (NSPoint(x: 250, y: iconBand), color(0.06, 0.29, 1, 0.055)),
            (NSPoint(x: 470, y: iconBand), color(1, 0.39, 0.40, 0.055))
        ] {
            NSGradient(starting: tint, ending: tint.withAlphaComponent(0))!
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: 230, options: [])
        }

        let markSize: CGFloat = 40
        let markTop = height - 34 - markSize
        mark(in: markSize).draw(in: NSRect(x: 36, y: markTop, width: markSize, height: markSize))
        title.draw(in: NSRect(x: 36 + markSize + 10, y: markTop + (markSize - 20) / 2,
                              width: 340, height: 20),
                   withAttributes: [
                       .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                       .foregroundColor: color(0.16, 0.16, 0.20)
                   ])

        // Arrow between the two icon slots, where the eye should travel.
        let arrow = NSBezierPath()
        let arrowMid = (appIconX + applicationsIconX) / 2
        arrow.move(to: NSPoint(x: arrowMid - 44, y: iconBand))
        arrow.line(to: NSPoint(x: arrowMid + 42, y: iconBand))
        arrow.move(to: NSPoint(x: arrowMid + 28, y: iconBand + 11))
        arrow.line(to: NSPoint(x: arrowMid + 42, y: iconBand))
        arrow.move(to: NSPoint(x: arrowMid + 28, y: iconBand - 11))
        arrow.line(to: NSPoint(x: arrowMid + 42, y: iconBand))
        arrow.lineWidth = 3
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        color(0.44, 0.45, 0.54).setStroke()
        arrow.stroke()

        "Drag to Applications".draw(in: NSRect(x: 0, y: iconBand - 36, width: width, height: 18),
                                    withAttributes: [
                                        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                        .foregroundColor: color(0.42, 0.42, 0.48),
                                        .paragraphStyle: centered()
                                    ])

        footer.draw(in: NSRect(x: 0, y: 20, width: width, height: 16),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: color(0.55, 0.55, 0.60),
                        .paragraphStyle: centered()
                    ])
    }

    static func render(scale: CGFloat, footer: String, title: String) -> Data {
        let pixels = NSSize(width: width * scale, height: height * scale)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
        draw(footer: footer, title: title)
        return bitmap.representation(using: .png, properties: [:])!
    }

    /// A 1x background with outlines where Finder will draw the icons, for checking
    /// that the artwork lines up with the recorded icon positions.
    static func preview(footer: String, title: String) -> Data {
        let image = NSImage(data: render(scale: 1, footer: footer, title: title))!
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        defer { NSGraphicsContext.restoreGraphicsState() }
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))

        let hint = NSBezierPath()
        hint.lineWidth = 1.5
        hint.setLineDash([5, 4], count: 2, phase: 0)
        color(1, 0.2, 0.3, 0.8).setStroke()
        for (x, label) in [(appIconX, " ScreenCaptureAll.app "), (applicationsIconX, " Applications ")] {
            hint.appendRoundedRect(
                NSRect(x: x - iconSize / 2, y: iconBand - iconSize / 2,
                       width: iconSize, height: iconSize),
                xRadius: 12, yRadius: 12)
            label.draw(in: NSRect(x: x - 90, y: iconBand - iconSize / 2 - 22, width: 180, height: 16),
                       withAttributes: [
                           .font: NSFont.systemFont(ofSize: 11),
                           .foregroundColor: color(1, 0.2, 0.3),
                           .paragraphStyle: centered()
                       ])
        }
        hint.stroke()
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            fatalError("Usage: generate-dmg-background <output-directory> <work-directory> [title] [footer]")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let work = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let title = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "Screen Capture All"
        let footer = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : ""

        try render(scale: 1, footer: footer, title: title)
            .write(to: output.appendingPathComponent("background.png"))
        try render(scale: 2, footer: footer, title: title)
            .write(to: output.appendingPathComponent("background@2x.png"))
        try preview(footer: footer, title: title)
            .write(to: work.appendingPathComponent("background-preview.png"))
    }
}
