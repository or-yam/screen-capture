import AppKit
import ImageIO
import UniformTypeIdentifiers

// Standalone synthetic probe. No NSApplication, desktop capture, or TCC changes.
// Compiled alongside the production AppLogging.swift and CaptureDiagnostics.swift.
enum PNGEncoder {
    static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}

@main
struct DiagnosticsProbe {
    static func main() throws {
        guard let context = CGContext(
            data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { fatalError("Cannot create synthetic image") }

        // A reused events.log is never allowed to grow beyond the per-file budget.
        if ProcessInfo.processInfo.environment["PROBE_LOG_LIMIT"] == "1" {
            let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREEN_CAPTURE_DIAGNOSTICS_DIR"]!)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("events.log")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 8 * 1024 * 1024)
            try handle.close()
        }

        AppLogging.$captureID.withValue("synthetic-capture") {
            CaptureDiagnostics.log("synthetic probe")
            CaptureDiagnostics.record(image, stage: "snapshot")
        }
        print("enabled=\(CaptureDiagnostics.isEnabled) images=\(CaptureDiagnostics.recordsImages)")
    }
}
