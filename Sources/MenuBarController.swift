import AppKit

final class MenuBarController: NSObject {
    private let preferences: PreferencesStore
    private let captureCoordinator: CaptureCoordinator
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(preferences: PreferencesStore, captureCoordinator: CaptureCoordinator) {
        self.preferences = preferences
        self.captureCoordinator = captureCoordinator
        super.init()
    }

    func install() {
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screen Capture All")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: ""))
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

    @objc private func captureArea() {
        captureCoordinator.captureArea()
    }

    @objc private func captureWindow() {
        captureCoordinator.captureWindow()
    }

    @objc private func captureFullScreen() {
        captureCoordinator.captureFullScreen()
    }

    @objc private func openScreenshotFolder() {
        NSWorkspace.shared.open(preferences.saveFolderURL)
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
