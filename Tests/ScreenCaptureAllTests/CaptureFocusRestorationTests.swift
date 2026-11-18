import Testing
@testable import ScreenCaptureAll

@MainActor
struct CaptureFocusRestorationTests {
    @Test
    func closingCaptureRestoresPreviousApplicationOnce() {
        var restorationCount = 0
        let overlay = RegionCaptureOverlayController(captureFocusRestoration: {
            { restorationCount += 1 }
        })

        overlay.prepareForCapture()
        #expect(restorationCount == 0)
        overlay.cancel()
        overlay.cancel()

        #expect(restorationCount == 1)
    }

    @Test
    func replacementCaptureKeepsOriginalApplication() {
        var rememberedCount = 0
        var restoredApplications: [Int] = []
        let overlay = RegionCaptureOverlayController(captureFocusRestoration: {
            rememberedCount += 1
            let application = rememberedCount
            return { restoredApplications.append(application) }
        })

        overlay.prepareForCapture()
        overlay.prepareForCapture()
        #expect(restoredApplications.isEmpty)
        overlay.cancel()

        #expect(rememberedCount == 1)
        #expect(restoredApplications == [1])

        overlay.prepareForCapture()
        overlay.cancel()
        #expect(restoredApplications == [1, 2])
    }

    @Test
    func userCancellationRestoresPreviousApplication() {
        var restored = false
        let overlay = RegionCaptureOverlayController(captureFocusRestoration: {
            { restored = true }
        })

        overlay.prepareForCapture()
        overlay.cancelFromUserAction()

        #expect(restored)
    }

    @Test
    func missingPreviousApplicationIsNotRecapturedDuringReplacement() {
        var rememberedCount = 0
        let overlay = RegionCaptureOverlayController(captureFocusRestoration: {
            rememberedCount += 1
            return nil
        })

        overlay.prepareForCapture()
        overlay.prepareForCapture()
        overlay.cancel()

        #expect(rememberedCount == 1)
    }
}
