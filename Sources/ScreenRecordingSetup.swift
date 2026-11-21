import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class ScreenRecordingSetup {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    let appURL: URL
    let appName: String
    private(set) var isAllowed = false
    private(set) var actionFeedback: String?

    private let checkAccess: () -> Bool
    private let openURL: (URL) -> Bool
    private let revealURL: (URL) -> Void
    private let copyText: (String) -> Bool

    init(
        appURL: URL = Bundle.main.bundleURL,
        appName: String? = nil,
        checkAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        revealURL: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        copyText: @escaping (String) -> Bool = {
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString($0, forType: .string)
        }
    ) {
        self.appURL = appURL
        let bundle = Bundle(url: appURL)
        self.appName = appName ?? (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        self.checkAccess = checkAccess
        self.openURL = openURL
        self.revealURL = revealURL
        self.copyText = copyText
    }

    /// Called once at launch. Activation only refreshes status; it never presents a window.
    func prepareForLaunch(preferences: PreferencesStore) -> Bool {
        refresh()
        let shouldShow = !preferences.hasShownInitialPreferences || !isAllowed
        if shouldShow {
            preferences.hasShownInitialPreferences = true
        }
        return shouldShow
    }

    func refresh() {
        isAllowed = checkAccess()
    }

    func openSystemSettings() {
        guard let url = Self.settingsURL, openURL(url) else {
            actionFeedback = "Could not open System Settings. Open Privacy & Security → Screen & System Audio Recording manually."
            return
        }
        actionFeedback = nil
    }

    func showAppInFinder() {
        revealURL(appURL)
    }

    func copyAppPath() {
        actionFeedback = copyText(appURL.path) ? "App path copied."
            : "Could not copy the app path. Select the path above and press Command-C."
    }
}
