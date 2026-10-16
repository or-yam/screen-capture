import AppKit

/// Unwrapped, top-left text layout shared by the live editor and PNG renderer.
/// Coordinates use the creation-time pixel basis, not the current display scale.
struct AnnotationTextLayout {
    private let storage: NSTextStorage
    let manager: NSLayoutManager
    let container: NSTextContainer

    init(text: String = "", font: NSFont, color: NSColor) {
        storage = NSTextStorage(string: text, attributes: Self.attributes(font: font, color: color))
        manager = NSLayoutManager()
        container = Self.makeContainer()
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
    }

    var contentSize: NSSize {
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentRect
        return NSSize(width: ceil(used.maxX), height: ceil(max(used.maxY, extra.maxY)))
    }

    static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    private static func makeContainer() -> NSTextContainer {
        let container = NSTextContainer(size: NSSize(width: 1_000_000, height: 1_000_000))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        return container
    }
}
