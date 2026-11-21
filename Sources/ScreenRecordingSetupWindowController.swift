import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingSetupWindowController: NSWindowController {
    init(setup: ScreenRecordingSetup, startCapture: @escaping () -> Void) {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Set Up ScreenCaptureAll")
                    .font(.title2.bold())
                ScreenRecordingSetupView(setup: setup, startCapture: startCapture)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, minHeight: 360)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Screen Recording Setup"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 660))
        window.contentMinSize = NSSize(width: 460, height: 360)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSetup() {
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
