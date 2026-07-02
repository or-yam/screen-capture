import AppKit

@MainActor
final class CaptureCoordinator {
    private let overlayController: RegionCaptureOverlayController
    private let screenshotService: ScreenshotCapturing
    private let clipboardService: ClipboardService
    private let saveService: SaveService
    private let saveConfirmationToastController: SaveConfirmationToastController
    private let preferences: PreferencesStore

    init(
        preferences: PreferencesStore,
        overlayController: RegionCaptureOverlayController? = nil,
        screenshotService: ScreenshotCapturing = ScreenCaptureKitScreenshotService(),
        clipboardService: ClipboardService = ClipboardService(),
        saveService: SaveService,
        saveConfirmationToastController: SaveConfirmationToastController? = nil
    ) {
        self.preferences = preferences
        self.screenshotService = screenshotService
        self.clipboardService = clipboardService
        self.saveService = saveService
        self.saveConfirmationToastController = saveConfirmationToastController ?? SaveConfirmationToastController()
        self.overlayController = overlayController ?? RegionCaptureOverlayController()
        self.overlayController.onCopy = { [weak self] data in
            self?.copyAndClose(data)
        }
        self.overlayController.onSave = { [weak self] data in
            self?.saveAndClose(data)
        }
    }

    func startRegionCapture() {
        NSLog("CaptureCoordinator: start region capture requested.")
        Task { [weak self] in
            guard let self else { return }

            do {
                overlayController.cancel()
                let displays = DisplayGeometry.currentDisplays()
                let snapshots = try await screenshotService.captureDisplaySnapshots(displays: displays)
                NSLog("CaptureCoordinator: captured \(snapshots.count) frozen display snapshots.")
                overlayController.start(
                    snapshots: snapshots,
                    defaultAnnotationColor: preferences.defaultAnnotationColor,
                    defaultAnnotationStrokeWidth: preferences.defaultAnnotationStrokeWidth
                )
            } catch {
                NSLog("CaptureCoordinator: frozen snapshot capture failed: \(error.localizedDescription)")
                overlayController.showCaptureError(error)
            }
        }
    }

    private func copyAndClose(_ data: Data) {
        NSLog("CaptureCoordinator: copy requested, \(data.count) bytes.")
        do {
            try clipboardService.copyPNG(data)
            NSLog("CaptureCoordinator: copy succeeded; closing overlay.")
            overlayController.cancel()
        } catch {
            NSLog("CaptureCoordinator: copy failed: \(error.localizedDescription)")
            overlayController.showCaptureError(error)
        }
    }

    private func saveAndClose(_ data: Data) {
        NSLog("CaptureCoordinator: save requested, \(data.count) bytes.")
        do {
            let outputURL = try saveService.savePNG(data)
            NSLog("CaptureCoordinator: save succeeded at \(outputURL.path); closing overlay.")
            overlayController.cancel()
            if preferences.showsSaveConfirmation {
                saveConfirmationToastController.showSavedFile(at: outputURL)
            }
        } catch {
            NSLog("CaptureCoordinator: save failed: \(error.localizedDescription)")
            overlayController.showSaveError(error)
        }
    }
}
