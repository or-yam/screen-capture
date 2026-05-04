import AppKit
import SwiftUI

@main
struct ScreenCaptureAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(preferences: appDelegate.preferences)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()

    private var menuBarController: MenuBarController?
    private var captureCoordinator: CaptureCoordinator?
    private var globalShortcutManager: GlobalShortcutManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let clipboardService = ClipboardService()
        let saveService = SaveService(preferences: preferences)
        let renderer = Renderer()
        let editorWindowController = ScreenshotEditorWindowController(
            renderer: renderer,
            clipboardService: clipboardService,
            saveService: saveService
        )
        let captureCoordinator = CaptureCoordinator(editorWindowController: editorWindowController)
        self.captureCoordinator = captureCoordinator

        menuBarController = MenuBarController(
            preferences: preferences,
            captureCoordinator: captureCoordinator
        )
        menuBarController?.install()

        globalShortcutManager = GlobalShortcutManager {
            captureCoordinator.captureArea()
        }
        globalShortcutManager?.start()
    }
}
