import AppKit
import Testing
@testable import ScreenCaptureAll

@MainActor
struct CaptureCoordinatorTests {
    @Test(.timeLimit(.minutes(1)))
    func repeatedTriggersAreIgnoredUntilSnapshotsFinish() async {
        let capture = ControlledScreenshotCapture()
        let overlay = RecordingCaptureOverlay()
        let coordinator = makeCoordinator(capture: capture, overlay: overlay)
        var events = overlay.events.makeAsyncIterator()

        coordinator.startRegionCapture()
        coordinator.startRegionCapture()
        await capture.waitForRequest()
        coordinator.startRegionCapture()

        #expect(overlay.cancelCount == 1)
        await capture.completeRequest()
        #expect(await events.next() == .started)
        #expect(await capture.requestCount == 1)
        #expect(overlay.startCount == 1)

        // Once the overlay is ready, starting a fresh capture still works.
        coordinator.startRegionCapture()
        await capture.waitForRequest()
        await capture.completeRequest()
        #expect(await events.next() == .started)
        #expect(await capture.requestCount == 2)
        #expect(overlay.startCount == 2)
        #expect(overlay.cancelCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func captureFailureAllowsAnotherRequest() async {
        let capture = ControlledScreenshotCapture()
        let overlay = RecordingCaptureOverlay()
        let coordinator = makeCoordinator(capture: capture, overlay: overlay)
        var events = overlay.events.makeAsyncIterator()

        coordinator.startRegionCapture()
        await capture.waitForRequest()
        await capture.completeRequest(error: ScreenshotCaptureError.noImageReturned)
        #expect(await events.next() == .failed)
        #expect(overlay.startCount == 0)

        coordinator.startRegionCapture()
        await capture.waitForRequest()
        await capture.completeRequest()
        #expect(await events.next() == .started)
        #expect(await capture.requestCount == 2)
    }

    private func makeCoordinator(
        capture: ControlledScreenshotCapture,
        overlay: RecordingCaptureOverlay
    ) -> CaptureCoordinator {
        let preferences = PreferencesStore()
        return CaptureCoordinator(
            preferences: preferences,
            overlayController: overlay,
            screenshotService: capture,
            saveService: SaveService(preferences: preferences)
        )
    }
}

private actor ControlledScreenshotCapture: ScreenshotCapturing {
    private(set) var requestCount = 0
    private var pendingRequest: CheckedContinuation<[DisplaySnapshot], Error>?
    private var requestWaiter: CheckedContinuation<Void, Never>?

    func captureRegion(_ region: ScreenRegion) async throws -> CGImage {
        throw ScreenshotCaptureError.noImageReturned
    }

    func captureDisplaySnapshots(displays: [DisplayGeometry]) async throws -> [DisplaySnapshot] {
        requestCount += 1
        guard pendingRequest == nil else {
            Issue.record("Started another snapshot request while one was pending")
            return []
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequest = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }

    func waitForRequest() async {
        guard pendingRequest == nil else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func completeRequest(error: Error? = nil) {
        let continuation = pendingRequest
        pendingRequest = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: [])
        }
    }
}

@MainActor
private final class RecordingCaptureOverlay: CaptureOverlay {
    enum Event: Equatable {
        case started
        case failed
    }

    var onCopy: ((Data) -> Void)?
    var onSave: ((Data) -> Void)?
    var captureID = "none"
    var cancelCount = 0
    var startCount = 0
    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func start(
        captureID: String,
        snapshots: [DisplaySnapshot],
        defaultAnnotationColor: NSColor,
        defaultAnnotationStrokeWidth: CGFloat
    ) {
        self.captureID = captureID
        startCount += 1
        continuation.yield(.started)
    }

    func cancel() { cancelCount += 1 }
    func showCaptureError(_ error: Error) { continuation.yield(.failed) }
    func showSaveError(_ error: Error) { continuation.yield(.failed) }
}
