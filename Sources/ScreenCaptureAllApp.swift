import AppKit
import SwiftUI

@main
struct ScreenCaptureAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(
                preferences: appDelegate.preferences,
                updates: appDelegate.updates,
                screenRecordingSetup: appDelegate.screenRecordingSetup,
                startCapture: appDelegate.startCaptureFromSetup
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    let updates = AppUpdateController()
    let screenRecordingSetup = ScreenRecordingSetup()

    private var menuBarController: MenuBarController?
    private var captureCoordinator: CaptureCoordinator?
    private var globalShortcutManager: GlobalShortcutManager?
    private var preferencesWindowController: PreferencesWindowController?
    private var setupWindowController: ScreenRecordingSetupWindowController?

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
            openPermissionSetupAction: { [weak self] in
                self?.showPermissionSetup()
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

        if screenRecordingSetup.prepareForLaunch(preferences: preferences) {
            showPermissionSetup()
        }
        updates.reportPendingUpdate()
    }

    private func showPreferences() {
        AppLogging.lifecycle.debug("Preferences requested")
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferences: preferences,
                updates: updates,
                screenRecordingSetup: screenRecordingSetup,
                startCapture: { [weak self] in self?.startCaptureFromSetup() }
            )
        }

        preferencesWindowController?.showPreferences()
    }

    private func showPermissionSetup() {
        screenRecordingSetup.refresh()
        if setupWindowController == nil {
            setupWindowController = ScreenRecordingSetupWindowController(
                setup: screenRecordingSetup,
                startCapture: { [weak self] in self?.startCaptureFromSetup() }
            )
        }
        setupWindowController?.showSetup()
    }

    func startCaptureFromSetup() {
        screenRecordingSetup.refresh()
        guard screenRecordingSetup.isAllowed else {
            showPermissionSetup()
            return
        }
        NSApp.keyWindow?.orderOut(nil)
        setupWindowController?.window?.orderOut(nil)
        preferencesWindowController?.window?.orderOut(nil)
        captureCoordinator?.startRegionCapture()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogging.lifecycle.notice("App terminating run=\(AppLogging.runID, privacy: .public)")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        screenRecordingSetup.refresh()
        // If the user reopened the old app during installation, the helper's
        // final open activates that process rather than launching another one.
        updates.reportPendingUpdate()
    }
}
