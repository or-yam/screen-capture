import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenRegion {
    var rectInDisplaySpace: CGRect
    var rectInAppKitScreenSpace: CGRect
    var displays: [DisplayGeometry]

    init(rectInDisplaySpace: CGRect, displays: [DisplayGeometry] = DisplayGeometry.currentDisplays()) {
        self.rectInDisplaySpace = rectInDisplaySpace.standardized
        self.rectInAppKitScreenSpace = rectInDisplaySpace.standardized
        self.displays = displays
    }

    init(rectInAppKitScreenSpace: CGRect, displays: [DisplayGeometry] = DisplayGeometry.currentDisplays()) {
        let rect = rectInAppKitScreenSpace.standardized
        self.rectInAppKitScreenSpace = rect
        self.rectInDisplaySpace = DisplayGeometry.convertToDisplaySpace(rect, displays: displays)
        self.displays = displays
    }

    init(display: DisplayGeometry, displays: [DisplayGeometry]) {
        self.rectInDisplaySpace = display.frameInDisplaySpace.standardized
        self.rectInAppKitScreenSpace = display.frameInAppKitScreenSpace.standardized
        self.displays = displays
    }
}

struct DisplaySnapshot {
    var display: DisplayGeometry
    var image: CGImage
}

struct DisplayGeometry {
    var localizedName: String
    var frameInDisplaySpace: CGRect
    var frameInAppKitScreenSpace: CGRect
    var backingScaleFactor: CGFloat

    static func currentDisplays() -> [DisplayGeometry] {
        let screens = NSScreen.screens
        let desktopMaxY = screens.map(\.frame.maxY).max() ?? 0

        return screens.map { screen in
            let appKitFrame = screen.frame
            return DisplayGeometry(
                localizedName: screen.localizedName,
                frameInDisplaySpace: CGRect(
                    x: appKitFrame.minX,
                    y: desktopMaxY - appKitFrame.maxY,
                    width: appKitFrame.width,
                    height: appKitFrame.height
                ),
                frameInAppKitScreenSpace: appKitFrame,
                backingScaleFactor: screen.backingScaleFactor
            )
        }
    }

    static func convertToDisplaySpace(_ rect: CGRect, displays: [DisplayGeometry]) -> CGRect {
        let desktopMaxY = displays.map(\.frameInAppKitScreenSpace.maxY).max() ?? 0
        return CGRect(
            x: rect.minX,
            y: desktopMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).standardized
    }
}

protocol ScreenshotCapturing {
    func captureRegion(_ region: ScreenRegion) async throws -> CGImage
    func captureDisplaySnapshots(displays: [DisplayGeometry]) async throws -> [DisplaySnapshot]
}

enum ScreenshotCaptureError: Error {
    case emptyRegion
    case regionOutsideDisplays(ScreenRegion)
    case screenRecordingPermissionDenied(underlyingError: Error?)
    case unsupportedOS
    case noImageReturned
    case pngEncodingFailed
}

extension ScreenshotCaptureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyRegion:
            return "The selected region is empty."
        case .regionOutsideDisplays:
            return "The selected region is outside the active displays."
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is required to capture the selected region."
        case .unsupportedOS:
            return "Native region capture requires macOS 15.2 or newer."
        case .noImageReturned:
            return "ScreenCaptureKit did not return an image."
        case .pngEncodingFailed:
            return "The captured image could not be encoded as PNG."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Enable Screen Recording for this app in System Settings, then try again."
        default:
            return nil
        }
    }
}

final class ScreenCaptureKitScreenshotService: ScreenshotCapturing {
    func captureDisplaySnapshots(displays: [DisplayGeometry]) async throws -> [DisplaySnapshot] {
        var snapshots: [DisplaySnapshot] = []
        snapshots.reserveCapacity(displays.count)

        for display in displays {
            let image = try await captureRegion(ScreenRegion(display: display, displays: displays))
            snapshots.append(DisplaySnapshot(display: display, image: image))
        }

        return snapshots
    }

    func captureRegion(_ region: ScreenRegion) async throws -> CGImage {
        let rect = region.rectInDisplaySpace.standardized.integral
        guard rect.width > 0, rect.height > 0 else {
            logCaptureDiagnostics(
                message: "Refusing to capture an empty region.",
                region: region,
                captureRect: rect
            )
            throw ScreenshotCaptureError.emptyRegion
        }

        let intersectingDisplays = region.displays.filter { !$0.frameInDisplaySpace.intersection(rect).isEmpty }
        guard !intersectingDisplays.isEmpty else {
            logCaptureDiagnostics(
                message: "Refusing to capture a region outside all displays.",
                region: region,
                captureRect: rect
            )
            throw ScreenshotCaptureError.regionOutsideDisplays(region)
        }

        guard #available(macOS 15.2, *) else {
            logCaptureDiagnostics(
                message: "SCScreenshotManager.captureImage(in:) requires macOS 15.2 or newer.",
                region: region,
                captureRect: rect
            )
            throw ScreenshotCaptureError.unsupportedOS
        }

        guard CGPreflightScreenCaptureAccess() else {
            logCaptureDiagnostics(
                message: "Screen Recording permission is not granted.",
                region: region,
                captureRect: rect
            )
            throw ScreenshotCaptureError.screenRecordingPermissionDenied(underlyingError: nil)
        }

        let image: CGImage = try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, error in
                if let error {
                    Self.logCaptureDiagnostics(
                        message: "ScreenCaptureKit capture failed: \(error)",
                        region: region,
                        captureRect: rect
                    )
                    if !CGPreflightScreenCaptureAccess() {
                        continuation.resume(
                            throwing: ScreenshotCaptureError.screenRecordingPermissionDenied(underlyingError: error)
                        )
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    Self.logCaptureDiagnostics(
                        message: "ScreenCaptureKit returned no image and no error.",
                        region: region,
                        captureRect: rect
                    )
                    continuation.resume(throwing: ScreenshotCaptureError.noImageReturned)
                }
            }
        }

        logScaleDiagnosticsIfNeeded(
            image: image,
            region: region,
            captureRect: rect,
            intersectingDisplays: intersectingDisplays
        )

        return image
    }

    private func logScaleDiagnosticsIfNeeded(
        image: CGImage,
        region: ScreenRegion,
        captureRect: CGRect,
        intersectingDisplays: [DisplayGeometry]
    ) {
        let scales = Set(intersectingDisplays.map(\.backingScaleFactor))
        guard scales.count == 1, let scale = scales.first else {
            logCaptureDiagnostics(
                message: "Capture spans displays with mixed backing scales; output size cannot be validated with one scale.",
                region: region,
                captureRect: captureRect,
                outputImageSize: CGSize(width: image.width, height: image.height)
            )
            return
        }

        let expectedSize = CGSize(
            width: captureRect.width * scale,
            height: captureRect.height * scale
        )
        let outputSize = CGSize(width: image.width, height: image.height)
        let widthDelta = abs(outputSize.width - expectedSize.width)
        let heightDelta = abs(outputSize.height - expectedSize.height)

        guard widthDelta > 1 || heightDelta > 1 else { return }

        logCaptureDiagnostics(
            message: "Captured image size does not match selected region at display scale \(scale). Expected \(format(expectedSize)), got \(format(outputSize)).",
            region: region,
            captureRect: captureRect,
            outputImageSize: outputSize
        )
    }

    private func logCaptureDiagnostics(
        message: String,
        region: ScreenRegion,
        captureRect: CGRect,
        outputImageSize: CGSize? = nil
    ) {
        Self.logCaptureDiagnostics(
            message: message,
            region: region,
            captureRect: captureRect,
            outputImageSize: outputImageSize
        )
    }

    private static func logCaptureDiagnostics(
        message: String,
        region: ScreenRegion,
        captureRect: CGRect,
        outputImageSize: CGSize? = nil
    ) {
        let displayDescriptions = region.displays.map { display in
            "\(display.localizedName): appKitFrame=\(format(display.frameInAppKitScreenSpace)) displayFrame=\(format(display.frameInDisplaySpace)) scale=\(display.backingScaleFactor)"
        }.joined(separator: "; ")
        let outputDescription = outputImageSize.map { format($0) } ?? "unavailable"

        NSLog(
            "Region capture diagnostic: %@ selectedAppKitRect=%@ selectedDisplayRect=%@ captureRect=%@ outputImageSize=%@ displays=[%@]",
            message,
            format(region.rectInAppKitScreenSpace),
            format(region.rectInDisplaySpace),
            format(captureRect),
            outputDescription,
            displayDescriptions
        )
    }

    private func format(_ rect: CGRect) -> String {
        Self.format(rect)
    }

    private func format(_ size: CGSize) -> String {
        Self.format(size)
    }

    private static func format(_ rect: CGRect) -> String {
        "x:\(rect.origin.x), y:\(rect.origin.y), w:\(rect.width), h:\(rect.height)"
    }

    private static func format(_ size: CGSize) -> String {
        "w:\(size.width), h:\(size.height)"
    }
}

enum PNGEncoder {
    static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        return data as Data
    }
}
