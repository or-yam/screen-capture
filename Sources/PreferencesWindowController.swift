import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(preferences: PreferencesStore, screenRecordingPermission: ScreenRecordingPermissionController) {
        let hostingController = NSHostingController(rootView: PreferencesView(
            preferences: preferences,
            screenRecordingPermission: screenRecordingPermission
        ))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.minSize = NSSize(width: 560, height: 460)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPreferences() {
        if window?.isVisible != true {
            window?.center()
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
