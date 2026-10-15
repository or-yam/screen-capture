import AppKit

/// Local, opt-in evidence collection for debug builds. Never enabled in release builds.
enum CaptureDiagnostics {
    private static let lock = NSLock()
    private static let directory: URL? = {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["SCREEN_CAPTURE_DIAGNOSTICS_DIR"] else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            AppLogging.diagnostics.error("Cannot create evidence directory: \(error.localizedDescription, privacy: .private)")
        }
        #endif
        return nil
    }()

    static var isEnabled: Bool { directory != nil }

    static var recordsImages: Bool {
        isEnabled && ProcessInfo.processInfo.environment["SCREEN_CAPTURE_DIAGNOSTICS_IMAGES"] == "1"
    }

    // Bound each run without deleting or rotating existing evidence.
    private static let maximumLogBytes = 8 * 1024 * 1024
    private static let maximumImageBytes = 256 * 1024 * 1024
    private static var imageBytesWritten = 0
    private static var reportedLogLimit = false
    private static var reportedImageLimit = false

    static func log(_ message: @autoclosure () -> String, captureID: String? = AppLogging.captureID) {
        guard let directory else { return }
        lock.lock()
        defer { lock.unlock() }
        let line = "\(Date().timeIntervalSince1970) run=\(AppLogging.runID) capture=\(captureID ?? "none") \(message())\n"
        let url = directory.appendingPathComponent("events.log")
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            guard size + UInt64(line.utf8.count) <= UInt64(maximumLogBytes) else {
                if !reportedLogLimit {
                    reportedLogLimit = true
                    AppLogging.diagnostics.notice("Diagnostic events.log reached its 8 MiB limit; further file events are skipped")
                }
                return
            }
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            AppLogging.diagnostics.error("Diagnostic log write failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func record(_ image: CGImage, stage: String, captureID: String? = AppLogging.captureID) {
        guard recordsImages else { return }
        do {
            recordPNG(try PNGEncoder.encode(image), stage: stage, captureID: captureID)
        } catch {
            log("artifact failed stage=\(stage) error=\(error)", captureID: captureID)
        }
    }

    static func recordPNG(_ data: Data, stage: String, captureID: String? = AppLogging.captureID) {
        guard recordsImages, let directory else { return }
        lock.lock()
        guard imageBytesWritten + data.count <= maximumImageBytes else {
            if !reportedImageLimit {
                reportedImageLimit = true
                AppLogging.diagnostics.notice("PNG evidence reached its 256 MiB limit; further images are skipped")
            }
            lock.unlock()
            return
        }
        imageBytesWritten += data.count
        lock.unlock()
        let url = directory.appendingPathComponent("\(stage)-\(captureID ?? "none")-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            log("artifact stage=\(stage) file=\(url.lastPathComponent) bytes=\(data.count)", captureID: captureID)
        } catch {
            log("artifact failed stage=\(stage) error=\(error)", captureID: captureID)
        }
    }

    @MainActor
    static func recordEnvironment() {
        guard isEnabled else { return }
        log("launch executable=\(Bundle.main.executablePath ?? "unknown") bundle=\(Bundle.main.bundleIdentifier ?? "unknown") os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            let pixels = id.map { "\(CGDisplayPixelsWide($0))x\(CGDisplayPixelsHigh($0))" } ?? "unknown"
            let mode = id.flatMap { CGDisplayCopyDisplayMode($0) }
            log("display id=\(String(describing: id)) name=\(screen.localizedName) frame=\(screen.frame) backingScale=\(screen.backingScaleFactor) displayPixels=\(pixels) modePixels=\(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0)")
        }
    }
}
