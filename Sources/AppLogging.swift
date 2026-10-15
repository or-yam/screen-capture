import Foundation
import OSLog

/// Operational logging remains available in release builds. Desktop images do not.
enum AppLogging {
    static let subsystem = "com.oryam.ScreenCaptureAll"
    static let runID = ProcessInfo.processInfo.environment["SCREEN_CAPTURE_RUN_ID"] ?? UUID().uuidString

    // Task-local context follows async snapshot work without shared mutable state.
    // AppKit event callbacks retain their capture ID in RegionSelectionState instead.
    @TaskLocal static var captureID: String?

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let selection = Logger(subsystem: subsystem, category: "selection")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let save = Logger(subsystem: subsystem, category: "save")
    static let permission = Logger(subsystem: subsystem, category: "permission")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
