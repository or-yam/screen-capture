import AppKit
import Observation

/// Owns manual update checks and hands installation to a helper that survives app exit.
@MainActor
@Observable
final class AppUpdateController {
    private(set) var isBusy = false
    private(set) var status = "Updates are checked only when you ask."

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"

    var canUpdate: Bool {
        Bundle.main.bundleIdentifier == "com.oryam.ScreenCaptureAll"
            && Bundle.main.bundleURL.lastPathComponent == "ScreenCaptureAll.app"
            && AppRelease.Version(currentVersion) != nil
            && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
            && Bundle.main.url(forResource: "install", withExtension: "sh") != nil
            && Bundle.main.url(forResource: "update_app", withExtension: "sh") != nil
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        guard canUpdate, let installedVersion = AppRelease.Version(currentVersion) else {
            showError(AppRelease.UpdateError.unsupportedInstallation.localizedDescription)
            return
        }
        isBusy = true
        status = "Checking for updates…"
        Task {
            defer { isBusy = false }
            do {
                let release = try await AppRelease.latest()
                let version = try release.validatedVersion()
                guard version > installedVersion else {
                    status = "ScreenCaptureAll \(currentVersion) is up to date."
                    showMessage(title: "You’re up to date", detail: status)
                    return
                }
                status = "Version \(version) is available."
                let alert = NSAlert()
                alert.messageText = "Install ScreenCaptureAll \(version)?"
                alert.informativeText = "ScreenCaptureAll will quit, download and verify the update, replace version \(currentVersion), then reopen. Any current capture will be closed.\n\nThis app is ad-hoc signed and not notarized by Apple. Continue only if you trust this project. Screen Recording may need approval again. No security settings will be changed."
                alert.addButton(withTitle: "Install and Restart")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try startUpdate(version: version)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func updatesDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ScreenCaptureAll/Updates", isDirectory: true)
    }

    private func startUpdate(version: AppRelease.Version) throws {
        guard canUpdate,
              let installer = Bundle.main.url(forResource: "install", withExtension: "sh"),
              let helper = Bundle.main.url(forResource: "update_app", withExtension: "sh") else {
            throw AppRelease.UpdateError.unsupportedInstallation
        }
        let id = UUID().uuidString
        let directory = try updatesDirectory().appendingPathComponent(id, isDirectory: true)
        let pending = try updatesDirectory().appendingPathComponent("pending")
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            // These copies must survive replacement of the running app bundle.
            try files.copyItem(at: installer, to: directory.appendingPathComponent("install.sh"))
            try files.copyItem(at: helper, to: directory.appendingPathComponent("update_app.sh"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                directory.appendingPathComponent("update_app.sh").path,
                String(ProcessInfo.processInfo.processIdentifier),
                version.description,
                Bundle.main.bundleURL.path,
                directory.path
            ]
            process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // An atomic file makes the handoff durable before the app exits.
            try id.write(to: pending, atomically: true, encoding: .utf8)
            try process.run()
        } catch {
            try? files.removeItem(at: pending)
            try? files.removeItem(at: directory)
            throw error
        }
        status = "Quitting to install version \(version)…"
        NSApp.terminate(nil)
    }

    func reportPendingUpdate() {
        guard let root = try? updatesDirectory(),
              let id = try? String(contentsOf: root.appendingPathComponent("pending"), encoding: .utf8),
              UUID(uuidString: id) != nil else { return }
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let resultURL = directory.appendingPathComponent("result")
        guard let result = try? String(contentsOf: resultURL, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent("pending"))
        if result.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
            status = "Updated to ScreenCaptureAll \(currentVersion)."
            showMessage(title: "Update complete", detail: status)
            try? FileManager.default.removeItem(at: directory)
        } else {
            status = "The update failed. The previous app was restored where possible."
            let log = directory.appendingPathComponent("update.log")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t install the update"
            alert.informativeText = "\(status)\n\nSee the update log for the failure and any retained backup location."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show Log")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([log])
            }
        }
    }

    private func showError(_ detail: String) {
        status = "Couldn’t update ScreenCaptureAll."
        showMessage(title: status, detail: detail, style: .warning)
    }

    private func showMessage(title: String, detail: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
