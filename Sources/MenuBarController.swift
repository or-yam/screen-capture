import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let preferences: PreferencesStore
    private let captureCoordinator: CaptureCoordinator
    private let openPreferencesAction: () -> Void
    private let screenRecordingPermission: ScreenRecordingPermissionController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var menuBarIconCancellable: AnyCancellable?
    private var volumeChangesCancellable: AnyCancellable?
    private var permissionItem: NSMenuItem?
    private var ejectInstallerItem: NSMenuItem?
    private var installerSeparator: NSMenuItem?
    private var installerVolume: URL?
    private var installerScanTask: Task<Void, Never>?
    private var isEjectingInstaller = false

    init(
        preferences: PreferencesStore,
        captureCoordinator: CaptureCoordinator,
        screenRecordingPermission: ScreenRecordingPermissionController,
        openPreferencesAction: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.captureCoordinator = captureCoordinator
        self.openPreferencesAction = openPreferencesAction
        self.screenRecordingPermission = screenRecordingPermission
        super.init()

        menuBarIconCancellable = preferences.$showsMenuBarIcon
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyMenuBarIconVisibility()
                }
            }
    }

    func install() {
        statusItem.button?.image = BrandMark.menuBarImage()
        statusItem.button?.setAccessibilityLabel("Screen Capture All")
        installMenu()
        applyMenuBarIconVisibility()
        let notifications = NSWorkspace.shared.notificationCenter
        volumeChangesCancellable = Publishers.Merge(
            notifications.publisher(for: NSWorkspace.didMountNotification),
            notifications.publisher(for: NSWorkspace.didUnmountNotification)
        ).sink { [weak self] _ in
            Task { @MainActor in self?.refreshInstallerItem() }
        }
        refreshInstallerItem()
    }

    private func installMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let captureItem = makeMenuItem(
            title: "Capture Region",
            action: #selector(startRegionCapture),
            keyEquivalent: "s",
            symbolName: "camera.viewfinder"
        )
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureItem)
        let permissionItem = makeMenuItem(
            title: "Enable Screen Recording...",
            action: #selector(enableScreenRecording),
            symbolName: "lock.open"
        )
        permissionItem.isHidden = true
        self.permissionItem = permissionItem
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Open Screenshots Folder",
            action: #selector(openScreenshotFolder),
            symbolName: "folder"
        ))
        menu.addItem(makeMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ",",
            symbolName: "gearshape"
        ))
        menu.addItem(.separator())
        let ejectItem = makeMenuItem(
            title: "Eject Installer",
            action: #selector(ejectInstaller),
            symbolName: "eject"
        )
        ejectItem.isHidden = true
        ejectInstallerItem = ejectItem
        menu.addItem(ejectItem)
        let installerSeparator = NSMenuItem.separator()
        installerSeparator.isHidden = true
        self.installerSeparator = installerSeparator
        menu.addItem(installerSeparator)
        menu.addItem(makeMenuItem(
            title: "Quit Screen Capture All",
            action: #selector(quit),
            keyEquivalent: "q",
            symbolName: "power"
        ))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        screenRecordingPermission.refresh()
        permissionItem?.isHidden = screenRecordingPermission.isAllowed
        refreshInstallerItem()
    }

    @objc private func enableScreenRecording() {
        screenRecordingPermission.requestAccess()
    }

    private func refreshInstallerItem() {
        guard installerScanTask == nil, !isEjectingInstaller else { return }
        let applicationURL = Bundle.main.bundleURL
        installerScanTask = Task { [weak self] in
            let volume = await InstallerDisk.find(for: applicationURL)
            guard !Task.isCancelled, let self else { return }
            installerVolume = volume
            ejectInstallerItem?.isHidden = volume == nil
            installerSeparator?.isHidden = volume == nil
            installerScanTask = nil
        }
    }

    @objc private func ejectInstaller() {
        guard installerVolume != nil, !isEjectingInstaller else { return }
        isEjectingInstaller = true
        installerScanTask?.cancel()
        installerScanTask = nil
        ejectInstallerItem?.isHidden = true
        installerSeparator?.isHidden = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                isEjectingInstaller = false
                refreshInstallerItem()
            }
            // Revalidate immediately before ejection; never force an unmount or delete the DMG.
            guard let volume = await InstallerDisk.find(for: Bundle.main.bundleURL) else { return }
            do {
                // The workspace API is synchronous; keep disk I/O off the main actor.
                try await Task.detached(priority: .userInitiated) {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                }.value
                installerVolume = nil
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Could not eject installer"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func startRegionCapture() {
        captureCoordinator.startRegionCapture()
    }

    @objc private func openScreenshotFolder() {
        let folderURL = preferences.saveFolderURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        guard exists else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder is missing.",
                detail: "Choose an existing folder in Preferences before opening it."
            )
            return
        }

        guard isDirectory.boolValue else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder is not a folder.",
                detail: "The configured path points to a file. Choose a folder in Preferences."
            )
            return
        }

        guard FileManager.default.isReadableFile(atPath: folderURL.path) else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder is not accessible.",
                detail: "Check folder permissions or choose another folder in Preferences."
            )
            return
        }

        guard NSWorkspace.shared.open(folderURL) else {
            showScreenshotFolderUnavailableAlert(
                message: "Screenshot folder could not be opened.",
                detail: "Finder could not open the configured folder. Choose another folder in Preferences."
            )
            return
        }
    }

    @objc private func openPreferences() {
        openPreferencesAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    private func applyMenuBarIconVisibility() {
        statusItem.isVisible = preferences.showsMenuBarIcon
    }

    private func showScreenshotFolderUnavailableAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openPreferencesAction()
        }
    }
}
