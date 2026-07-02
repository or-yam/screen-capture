import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let preferences: PreferencesStore
    private let captureCoordinator: CaptureCoordinator
    private let openPreferencesAction: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(
        preferences: PreferencesStore,
        captureCoordinator: CaptureCoordinator,
        openPreferencesAction: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.captureCoordinator = captureCoordinator
        self.openPreferencesAction = openPreferencesAction
        super.init()
    }

    func install() {
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screen Capture All")

        let menu = NSMenu()
        let captureItem = makeMenuItem(
            title: "Capture Region",
            action: #selector(startRegionCapture),
            keyEquivalent: "a",
            symbolName: "camera.viewfinder"
        )
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Open Screenshots Folder",
            action: #selector(openScreenshotFolder),
            symbolName: "folder"
        ))
        menu.addItem(makeMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ",",
            symbolName: "gearshape"
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Quit Screen Capture All",
            action: #selector(quit),
            keyEquivalent: "q",
            symbolName: "power"
        ))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func startRegionCapture() {
        captureCoordinator.startRegionCapture()
    }

    @objc private func openScreenshotFolder() {
        let folderURL = preferences.saveFolderURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        guard exists else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder is missing.",
                detail: "Choose an existing folder in Preferences before opening it."
            )
            return
        }

        guard isDirectory.boolValue else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder is not a folder.",
                detail: "The configured path points to a file. Choose a folder in Preferences."
            )
            return
        }

        guard FileManager.default.isReadableFile(atPath: folderURL.path) else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder is not accessible.",
                detail: "Check folder permissions or choose another folder in Preferences."
            )
            return
        }

        guard NSWorkspace.shared.open(folderURL) else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder could not be opened.",
                detail: "Finder could not open the configured folder. Choose another folder in Preferences."
            )
            return
        }
    }

    @objc private func openPreferences() {
        openPreferencesAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    private func showScreenshotFolderUnavailableAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openPreferencesAction()
        }
    }
}
