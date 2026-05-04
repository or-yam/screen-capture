import AppKit

final class CaptureCoordinator {
    private let editorWindowController: ScreenshotEditorWindowController

    init(editorWindowController: ScreenshotEditorWindowController) {
        self.editorWindowController = editorWindowController
    }

    func captureArea() {
        runCapture(arguments: ["-i"])
    }

    func captureWindow() {
        runCapture(arguments: ["-i", "-w"])
    }

    func captureFullScreen() {
        runCapture(arguments: [])
    }

    private func runCapture(arguments: [String]) {
        Task { @MainActor in
            do {
                let url = try await ScreencaptureService.capture(arguments: arguments)
                guard let image = NSImage(contentsOf: url) else { return }
                editorWindowController.show(image: image)
            } catch is CancellationError {
                return
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

enum ScreencaptureService {
    static func capture(arguments: [String]) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-capture-all-\(UUID().uuidString).png")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments + [outputURL.path]

            process.terminationHandler = { process in
                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
