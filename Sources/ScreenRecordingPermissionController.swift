import AppKit
import Combine
import CoreGraphics

@MainActor
final class ScreenRecordingPermissionController: ObservableObject {
    @Published private(set) var isAllowed = false

    private let defaults: UserDefaults
    private let preflight: () -> Bool
    private let request: () -> Bool
    private let openSettings: @MainActor () -> Void
    private var isRequestingAccess = false
    private static let firstLaunchKey = "hasCheckedFirstLaunchScreenRecording"

    init(
        defaults: UserDefaults = .standard,
        preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        request: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings: @escaping @MainActor () -> Void = { ScreenRecordingPermissionController.openSystemSettings() }
    ) {
        self.defaults = defaults
        self.preflight = preflight
        self.request = request
        self.openSettings = openSettings
    }

    func handleFirstLaunch() {
        refresh()
        guard !defaults.bool(forKey: Self.firstLaunchKey) else { return }
        // macOS may quit/relaunch the app during approval. Never repeat setup after that.
        defaults.set(true, forKey: Self.firstLaunchKey)
        if !isAllowed {
            requestAccess()
        }
    }

    func refresh() {
        isAllowed = preflight()
    }

    @discardableResult
    func requestAccess() -> Bool {
        refresh()
        guard !isAllowed else { return true }
        guard !isRequestingAccess else { return false }
        isRequestingAccess = true
        defer { isRequestingAccess = false }

        // Register this app with TCC before opening Settings, so users needn't add it manually.
        let granted = request()
        refresh()
        if !granted && !isAllowed {
            openSettings()
        }
        return isAllowed
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        if !NSWorkspace.shared.open(url) {
            AppLogging.permission.error("Could not open Screen Recording settings")
        }
    }
}
