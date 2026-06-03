import AppKit

@MainActor
final class CaptureCoordinator {
    private let overlayController: RegionCaptureOverlayController
    private let screenshotService: ScreenshotCapturing
    private let clipboardService: ClipboardService
    private let saveService: SaveService

    init(
        overlayController: RegionCaptureOverlayController? = nil,
        screenshotService: ScreenshotCapturing = ScreenCaptureKitScreenshotService(),
        clipboardService: ClipboardService = ClipboardService(),
        saveService: SaveService
    ) {
        self.screenshotService = screenshotService
        self.clipboardService = clipboardService
        self.saveService = saveService
        self.overlayController = overlayController ?? RegionCaptureOverlayController()
        self.overlayController.onRegionSelected = { [weak self] rect in
            self?.captureSelectedRegion(rect)
        }
        self.overlayController.onCopy = { [weak self] data in
            self?.copyAndClose(data)
        }
        self.overlayController.onSave = { [weak self] data in
            self?.saveAndClose(data)
        }
    }

    func startRegionCapture() {
        NSLog("CaptureCoordinator: start region capture requested.")
        overlayController.start()
    }

    private func captureSelectedRegion(_ rect: CGRect) {
        NSLog("CaptureCoordinator: capturing selected region \(rect).")
        let region = ScreenRegion(rectInAppKitScreenSpace: rect)

        Task { [weak self] in
            guard let self else { return }

            do {
                overlayController.hideForCapture()
                let image = try await screenshotService.captureRegion(region)
                let pngData = try PNGEncoder.encode(image)
                NSLog("CaptureCoordinator: region capture encoded PNG, \(pngData.count) bytes.")
                overlayController.showAfterCapture()
                overlayController.setCapturedImage(image, pngData: pngData)
            } catch {
                NSLog("CaptureCoordinator: region capture failed: \(error.localizedDescription)")
                overlayController.showAfterCapture()
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
        } catch {
            NSLog("CaptureCoordinator: save failed: \(error.localizedDescription)")
            overlayController.showSaveError(error)
        }
    }
}
