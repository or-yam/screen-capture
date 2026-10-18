import AppKit
import SwiftUI

@main
struct ScreenCaptureAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(
                preferences: appDelegate.preferences,
                screenRecordingPermission: appDelegate.screenRecordingPermission
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    let screenRecordingPermission = ScreenRecordingPermissionController()

    private var menuBarController: MenuBarController?
    private var captureCoordinator: CaptureCoordinator?
    private var globalShortcutManager: GlobalShortcutManager?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLogging.lifecycle.notice("App launched run=\(AppLogging.runID, privacy: .public) bundle=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public) diagnostics=\(CaptureDiagnostics.isEnabled) images=\(CaptureDiagnostics.recordsImages)")
        CaptureDiagnostics.recordEnvironment()

        let captureCoordinator = CaptureCoordinator(
            preferences: preferences,
            saveService: SaveService(preferences: preferences),
            prepareForCapture: { [screenRecordingPermission] in
                screenRecordingPermission.requestAccess()
            }
        )
        self.captureCoordinator = captureCoordinator

        menuBarController = MenuBarController(
            preferences: preferences,
            captureCoordinator: captureCoordinator,
            screenRecordingPermission: screenRecordingPermission,
            openPreferencesAction: { [weak self] in
                self?.showPreferences()
            }
        )
        menuBarController?.install()

        globalShortcutManager = GlobalShortcutManager {
            Task { @MainActor in
                captureCoordinator.startRegionCapture()
            }
        }
        globalShortcutManager?.start()
        screenRecordingPermission.handleFirstLaunch()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        screenRecordingPermission.refresh()
    }

    private func showPreferences() {
        AppLogging.lifecycle.debug("Preferences requested")
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferences: preferences,
                screenRecordingPermission: screenRecordingPermission
            )
        }

        preferencesWindowController?.showPreferences()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogging.lifecycle.notice("App terminating run=\(AppLogging.runID, privacy: .public)")
    }
}
