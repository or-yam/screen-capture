import AppKit
import SwiftUI

@main
struct ScreenCaptureAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(preferences: appDelegate.preferences, updates: appDelegate.updates)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    let updates = AppUpdateController()

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
            saveService: SaveService(preferences: preferences)
        )
        self.captureCoordinator = captureCoordinator

        menuBarController = MenuBarController(
            preferences: preferences,
            captureCoordinator: captureCoordinator,
            openPreferencesAction: { [weak self] in
                self?.showPreferences()
            },
            checkForUpdatesAction: { [weak self] in
                self?.showPreferences()
                self?.updates.checkForUpdates()
            }
        )
        menuBarController?.install()

        globalShortcutManager = GlobalShortcutManager {
            Task { @MainActor in
                captureCoordinator.startRegionCapture()
            }
        }
        globalShortcutManager?.start()

        if !preferences.hasShownInitialPreferences {
            showPreferences()
            preferences.hasShownInitialPreferences = true
        }
        updates.reportPendingUpdate()
    }

    private func showPreferences() {
        AppLogging.lifecycle.debug("Preferences requested")
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(preferences: preferences, updates: updates)
        }

        preferencesWindowController?.showPreferences()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogging.lifecycle.notice("App terminating run=\(AppLogging.runID, privacy: .public)")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If the user reopened the old app during installation, the helper's
        // final open activates that process rather than launching another one.
        updates.reportPendingUpdate()
    }
}
