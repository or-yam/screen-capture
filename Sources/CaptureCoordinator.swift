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
        let captureID = UUID().uuidString
        AppLogging.capture.notice("Capture requested id=\(captureID, privacy: .public)")
        CaptureDiagnostics.log("capture requested", captureID: captureID)
        CaptureDiagnostics.recordEnvironment()
        Task { [weak self] in
            guard let self else { return }

            do {
                overlayController.cancel()
                let displays = DisplayGeometry.currentDisplays()
                let snapshots = try await AppLogging.$captureID.withValue(captureID) {
                    try await self.screenshotService.captureDisplaySnapshots(displays: displays)
                }
                AppLogging.capture.notice("Snapshots ready id=\(captureID, privacy: .public) displays=\(snapshots.count)")
                overlayController.start(
                    captureID: captureID,
                    snapshots: snapshots,
                    defaultAnnotationColor: preferences.defaultAnnotationColor,
                    defaultAnnotationStrokeWidth: preferences.defaultAnnotationStrokeWidth
                )
            } catch {
                AppLogging.capture.error("Capture failed id=\(captureID, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code) detail=\(error.localizedDescription, privacy: .private)")
                overlayController.showCaptureError(error)
            }
        }
    }

    private func copyAndClose(_ data: Data) {
        let captureID = overlayController.captureID
        AppLogging.export.debug("Copy requested id=\(captureID, privacy: .public) bytes=\(data.count)")
        do {
            try clipboardService.copyPNG(data)
            AppLogging.export.notice("Copy succeeded id=\(captureID, privacy: .public) bytes=\(data.count)")
            overlayController.cancel()
        } catch {
            AppLogging.export.error("Copy failed id=\(captureID, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code) detail=\(error.localizedDescription, privacy: .private)")
            overlayController.showCaptureError(error)
        }
    }

    private func saveAndClose(_ data: Data) {
        let captureID = overlayController.captureID
        AppLogging.save.debug("Save requested id=\(captureID, privacy: .public) bytes=\(data.count)")
        do {
            let outputURL = try saveService.savePNG(data)
            AppLogging.save.notice("Save succeeded id=\(captureID, privacy: .public) bytes=\(data.count) path=\(outputURL.path, privacy: .private)")
            overlayController.cancel()
            if preferences.showsSaveConfirmation {
                saveConfirmationToastController.showSavedFile(at: outputURL)
            }
        } catch {
            AppLogging.save.error("Save failed id=\(captureID, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code) detail=\(error.localizedDescription, privacy: .private)")
            overlayController.showSaveError(error)
        }
    }
}
