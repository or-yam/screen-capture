import AppKit
import SwiftUI

final class ScreenshotEditorWindowController: NSWindowController {
    private let renderer: Renderer
    private let clipboardService: ClipboardService
    private let saveService: SaveService

    init(renderer: Renderer, clipboardService: ClipboardService, saveService: SaveService) {
        self.renderer = renderer
        self.clipboardService = clipboardService
        self.saveService = saveService

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.title = "Screen Capture All"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func show(image: NSImage) {
        let model = AnnotationModel(baseImage: image)
        let view = ScreenshotEditorView(
            model: model,
            renderer: renderer,
            clipboardService: clipboardService,
            saveService: saveService,
            close: { [weak self] in self?.close() }
        )
        window?.contentView = NSHostingView(rootView: view)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
