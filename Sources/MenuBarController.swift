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
        menu.addItem(NSMenuItem(title: "Capture Region", action: #selector(startRegionCapture), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Screenshot Folder", action: #selector(openScreenshotFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func startRegionCapture() {
        captureCoordinator.startRegionCapture()
    }

    @objc private func openScreenshotFolder() {
        NSWorkspace.shared.open(preferences.saveFolderURL)
    }

    @objc private func openPreferences() {
        openPreferencesAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
