import AppKit

@MainActor
final class SaveConfirmationToastController: NSObject {
    private var panel: NSPanel?
    private var savedURL: URL?
    private var dismissWorkItem: DispatchWorkItem?

    func showSavedFile(at url: URL) {
        savedURL = url
        dismissWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = makeContentView(filename: url.lastPathComponent)
        panel.layoutIfNeeded()
        position(panel)
        panel.orderFrontRegardless()

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismiss()
            }
        }
        self.dismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: dismissWorkItem)
    }

    @objc private func revealSavedFile() {
        guard let savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
        dismiss()
    }

    @objc private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        return panel
    }

    private func makeContentView(filename: String) -> NSView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved")
        icon.contentTintColor = .systemGreen
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Screenshot saved")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        let filenameLabel = NSTextField(labelWithString: filename)
        filenameLabel.font = .systemFont(ofSize: 12)
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.maximumNumberOfLines = 1
        filenameLabel.textColor = .secondaryLabelColor
        filenameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [title, filenameLabel])
        textStack.alignment = .leading
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let revealButton = NSButton(title: "Reveal", target: self, action: #selector(revealSavedFile))
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .small
        revealButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Reveal in Finder")
        revealButton.imagePosition = .imageLeading
        revealButton.toolTip = "Reveal in Finder"

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(revealButton)

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 460)
        ])

        container.frame = NSRect(origin: .zero, size: container.fittingSize)
        return container
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = panel.contentView?.fittingSize ?? NSSize(width: 360, height: 84)
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 18,
            y: visibleFrame.maxY - size.height - 18
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
