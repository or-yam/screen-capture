import AppKit

@MainActor
final class RegionCaptureOverlayController: CaptureOverlay {
    var onCopy: ((Data) -> Void)?
    var onSave: ((Data) -> Void)?

    private var windows: [RegionCaptureOverlayWindow] = []
    private var selectionState = RegionSelectionState()

    var captureID: String { selectionState.captureID }

    func start(
        captureID: String,
        snapshots: [DisplaySnapshot],
        defaultAnnotationColor: NSColor,
        defaultAnnotationStrokeWidth: CGFloat
    ) {
        AppLogging.selection.notice("Starting overlay id=\(captureID, privacy: .public)")
        cancel()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            AppLogging.selection.error("No screens available id=\(captureID, privacy: .public)")
            return
        }

        selectionState = RegionSelectionState(snapshots: snapshots, captureID: captureID)
        windows = screens.map { screen in
            let window = RegionCaptureOverlayWindow(
                screen: screen,
                selectionState: selectionState,
                close: { [weak self] in self?.cancelFromUserAction() },
                copy: { [weak self] data in self?.onCopy?(data) },
                save: { [weak self] data in self?.onSave?(data) },
                selectionCompleted: { [weak self] rect in self?.setSelectedRegionFromFrozenSnapshots(rect) },
                defaultAnnotationColor: defaultAnnotationColor,
                defaultAnnotationStrokeWidth: defaultAnnotationStrokeWidth,
                refresh: { [weak self] in self?.refreshOverlays() }
            )
            window.orderFrontRegardless()
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
        focusPrimaryOverlay(reason: "session start")
    }

    func cancel() {
        AppLogging.selection.debug("Closing overlay id=\(self.captureID, privacy: .public) windows=\(self.windows.count)")
        CaptureDiagnostics.log("overlay cancel windows=\(windows.count)", captureID: captureID)
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        selectionState.reset()
    }

    func cancelFromUserAction() {
        AppLogging.selection.notice("Capture cancelled by user id=\(self.captureID, privacy: .public)")
        cancel()
    }

    func hideForCapture() {
        AppLogging.selection.debug("Hiding overlay id=\(self.captureID, privacy: .public)")
        for window in windows {
            window.orderOut(nil)
        }
    }

    func showAfterCapture() {
        AppLogging.selection.debug("Restoring overlay id=\(self.captureID, privacy: .public)")
        for window in windows {
            window.orderFrontRegardless()
        }
        focusPrimaryOverlay(reason: "capture restore")
    }

    func showCaptureError(_ error: Error) {
        AppLogging.capture.error("Showing capture error: \(error.localizedDescription, privacy: .private)")
        hideForCapture()
        NSSound.beep()
        let alert = makeAlert(for: error)
        let response = alert.runModal()
        if isScreenRecordingPermissionDenied(error), response == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
        cancel()
    }

    func showSaveError(_ error: Error) {
        AppLogging.save.error("Showing save error id=\(self.captureID, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
        hideForCapture()
        NSSound.beep()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Close")
        alert.runModal()

        showAfterCapture()
    }

    private func makeAlert(for error: Error) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning

        if isScreenRecordingPermissionDenied(error) {
            alert.messageText = "Screen Recording permission required"
            alert.informativeText = "Enable Screen Recording for this app in System Settings, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Close")
        } else {
            alert.messageText = "Region capture failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Close")
        }

        return alert
    }

    private func isScreenRecordingPermissionDenied(_ error: Error) -> Bool {
        if case ScreenshotCaptureError.screenRecordingPermissionDenied = error {
            return true
        }

        return false
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func setSelectedRegionFromFrozenSnapshots(_ rect: CGRect) {
        do {
            try selectionState.setCapturedImageFromFrozenSnapshots(for: rect)
            if let image = selectionState.capturedImage, let pngData = selectionState.capturedPNG {
                AppLogging.selection.notice("Selection ready id=\(self.captureID, privacy: .public) pixels=\(image.width)x\(image.height) bytes=\(pngData.count)")
            }
            refreshOverlays()
        } catch {
            showCaptureError(error)
        }
    }

    private func refreshOverlays() {
        for window in windows {
            window.overlayView.refreshState()
        }
    }

    private func focusPrimaryOverlay(reason: String) {
        guard let window = windows.first else {
            AppLogging.selection.debug("No overlay to focus id=\(self.captureID, privacy: .public) reason=\(reason, privacy: .public)")
            return
        }

        window.makeKey()
        window.makeFirstResponder(window.overlayView)
        AppLogging.selection.debug("Focused overlay id=\(self.captureID, privacy: .public) reason=\(reason, privacy: .public) key=\(window.isKeyWindow)")
    }
}

enum RegionSelectionResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            return RegionResizeCursorCache.topLeftBottomRight
        case .topRight, .bottomLeft:
            return RegionResizeCursorCache.topRightBottomLeft
        case .left, .right:
            return RegionResizeCursorCache.leftRight
        case .top, .bottom:
            return RegionResizeCursorCache.upDown
        }
    }

    var movesLeftEdge: Bool {
        self == .topLeft || self == .left || self == .bottomLeft
    }

    var movesRightEdge: Bool {
        self == .topRight || self == .right || self == .bottomRight
    }

    var movesBottomEdge: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }

    var movesTopEdge: Bool {
        self == .topLeft || self == .top || self == .topRight
    }
}

private enum RegionResizeCursorCache {
    static let leftRight = makeCursor(angle: 0)
    static let upDown = makeCursor(angle: .pi / 2)
    static let topLeftBottomRight = makeCursor(angle: -.pi / 4)
    static let topRightBottomLeft = makeCursor(angle: .pi / 4)

    private static func makeCursor(angle: CGFloat) -> NSCursor {
        let size = NSSize(width: 20, height: 20)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: angle)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        drawResizeCursorStroke(color: .white, lineWidth: 4.5, center: center)
        drawResizeCursorStroke(color: .black, lineWidth: 2.2, center: center)

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    private static func drawResizeCursorStroke(color: NSColor, lineWidth: CGFloat, center: NSPoint) {
        color.setStroke()

        let linePath = NSBezierPath()
        linePath.lineWidth = lineWidth
        linePath.lineCapStyle = .round
        linePath.lineJoinStyle = .round
        linePath.move(to: NSPoint(x: 4, y: center.y))
        linePath.line(to: NSPoint(x: 16, y: center.y))
        linePath.stroke()

        let leftHead = NSBezierPath()
        leftHead.lineWidth = lineWidth
        leftHead.lineCapStyle = .round
        leftHead.lineJoinStyle = .round
        leftHead.move(to: NSPoint(x: 7.5, y: center.y + 3.5))
        leftHead.line(to: NSPoint(x: 4, y: center.y))
        leftHead.line(to: NSPoint(x: 7.5, y: center.y - 3.5))
        leftHead.stroke()

        let rightHead = NSBezierPath()
        rightHead.lineWidth = lineWidth
        rightHead.lineCapStyle = .round
        rightHead.lineJoinStyle = .round
        rightHead.move(to: NSPoint(x: 12.5, y: center.y + 3.5))
        rightHead.line(to: NSPoint(x: 16, y: center.y))
        rightHead.line(to: NSPoint(x: 12.5, y: center.y - 3.5))
        rightHead.stroke()
    }
}

@MainActor
final class RegionSelectionState {
    let captureID: String
    private(set) var snapshots: [DisplaySnapshot]
    private(set) var anchorPoint: NSPoint?
    private(set) var currentPoint: NSPoint?
    private(set) var canonicalSelectionRect: NSRect?
    private(set) var isSelectionAnchored = false
    private(set) var capturedPNG: Data?
    private(set) var capturedImage: CGImage?
    // The image and this frame are committed together. Live drag bounds may differ.
    private(set) var capturedSelectionRect: NSRect?
    private(set) var annotationCanvas: AnnotationCanvas?
    private(set) var annotations: [OverlayAnnotation] = []
    private(set) var draftAnnotation: OverlayAnnotation?

    private var annotationDragAnchorInCanvas: CGPoint?
    private var annotationPixelSizeInCanvas = CGSize(width: 1, height: 1)

    init(snapshots: [DisplaySnapshot] = [], captureID: String = "none") {
        self.snapshots = snapshots
        self.captureID = captureID
        if let frame = snapshots.map(\.display.frameInAppKitScreenSpace).reduce(nil as CGRect?, { bounds, frame in
            bounds.map { $0.union(frame) } ?? frame
        }) {
            annotationCanvas = AnnotationCanvas(frameInAppKitScreenSpace: frame)
        }
    }

    var selectionRect: NSRect? {
        if let canonicalSelectionRect {
            return canonicalSelectionRect
        }

        guard let anchorPoint, let currentPoint else { return nil }
        return Self.normalizedRect(from: anchorPoint, to: currentPoint)
    }

    var hasCommittedOrDraftAnnotations: Bool {
        !annotations.isEmpty || draftAnnotation != nil
    }

    private static func normalizedRect(from startPoint: NSPoint, to endPoint: NSPoint) -> NSRect {
        let origin = NSPoint(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y)
        )
        let size = NSSize(
            width: abs(startPoint.x - endPoint.x),
            height: abs(startPoint.y - endPoint.y)
        )

        return NSRect(origin: origin, size: size)
    }

    func beginSelection(at point: NSPoint) {
        anchorPoint = point
        currentPoint = point
        canonicalSelectionRect = nil
        isSelectionAnchored = false
        capturedPNG = nil
        capturedImage = nil
        capturedSelectionRect = nil
        annotations = []
        draftAnnotation = nil
        annotationDragAnchorInCanvas = nil
    }

    func updateSelection(to point: NSPoint) {
        guard anchorPoint != nil, !isSelectionAnchored else { return }
        currentPoint = point
    }

    func anchorSelection(at point: NSPoint) {
        guard let anchorPoint else { return }
        currentPoint = point
        canonicalSelectionRect = Self.normalizedRect(from: anchorPoint, to: point)
        isSelectionAnchored = true
        capturedPNG = nil
        capturedImage = nil
        capturedSelectionRect = nil
        annotations = []
        draftAnnotation = nil
        annotationDragAnchorInCanvas = nil
    }

    func moveAnchoredSelection(from initialRect: NSRect, by delta: NSSize) {
        guard isSelectionAnchored else { return }

        var proposedRect = constrainedRect(initialRect.offsetBy(dx: delta.width, dy: delta.height).standardized)
        if let snapshot = snapshots.first(where: {
            $0.display.frameInAppKitScreenSpace.contains(initialRect)
                && $0.display.frameInAppKitScreenSpace.contains(proposedRect)
        }) {
            let frame = snapshot.display.frameInAppKitScreenSpace
            let scaleX = CGFloat(snapshot.image.width) / frame.width
            let scaleY = CGFloat(snapshot.image.height) / frame.height
            // A fractional move must not expand an already aligned crop by an
            // extra row/column each time the pointer is released.
            proposedRect.origin = NSPoint(
                x: Self.clamp(frame.minX + ((proposedRect.minX - frame.minX) * scaleX).rounded() / scaleX,
                              min: frame.minX, max: frame.maxX - proposedRect.width),
                y: Self.clamp(frame.minY + ((proposedRect.minY - frame.minY) * scaleY).rounded() / scaleY,
                              min: frame.minY, max: frame.maxY - proposedRect.height)
            )
        }
        setAnchoredSelectionRect(proposedRect)
    }

    func resizeAnchoredSelection(from initialRect: NSRect, dragging handle: RegionSelectionResizeHandle, to point: NSPoint) {
        guard isSelectionAnchored else { return }

        let bounds = snapshots.first {
            $0.display.frameInAppKitScreenSpace.contains(initialRect)
        }?.display.frameInAppKitScreenSpace ?? snapshotBounds ?? initialRect
        let minSelectionSize: CGFloat = 12
        var minX = initialRect.minX
        var maxX = initialRect.maxX
        var minY = initialRect.minY
        var maxY = initialRect.maxY

        if handle.movesLeftEdge {
            minX = Self.clamp(point.x, min: bounds.minX, max: maxX - minSelectionSize)
        }
        if handle.movesRightEdge {
            maxX = Self.clamp(point.x, min: minX + minSelectionSize, max: bounds.maxX)
        }
        if handle.movesBottomEdge {
            minY = Self.clamp(point.y, min: bounds.minY, max: maxY - minSelectionSize)
        }
        if handle.movesTopEdge {
            maxY = Self.clamp(point.y, min: minY + minSelectionSize, max: bounds.maxY)
        }

        setAnchoredSelectionRect(NSRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ))
    }

    func setCapturedImageFromFrozenSnapshots(for rect: CGRect) throws {
        CaptureDiagnostics.log("crop begin selection=\(rect)", captureID: captureID)
        let crop = try Self.cropFrozenSnapshots(snapshots, to: rect, captureID: captureID)
        let image = crop.image
        let pngData = try PNGEncoder.encode(image)
        AppLogging.selection.debug("Crop ready id=\(self.captureID, privacy: .public) pixels=\(image.width)x\(image.height)")
        CaptureDiagnostics.log("crop complete pixels=\(image.width)x\(image.height)", captureID: captureID)
        CaptureDiagnostics.recordPNG(pngData, stage: "crop", captureID: captureID)
        capturedImage = image
        capturedPNG = pngData
        capturedSelectionRect = crop.rect
        // Preview and annotations must map the exact source-pixel bounds, not
        // stretch the image back into the original fractional drag rectangle.
        setAnchoredSelectionRect(crop.rect)
    }

    func beginAnnotation(tool: OverlayAnnotationTool, at point: CGPoint, color: NSColor, lineWidth: CGFloat, fontSize: CGFloat? = nil) {
        guard let capturedImage, let capturedSelectionRect, annotationCanvas != nil else { return }

        // Tool preferences remain image-pixel values. Convert once at creation;
        // existing marks then keep their screen size as the output density changes.
        annotationPixelSizeInCanvas = CGSize(
            width: capturedSelectionRect.width / CGFloat(capturedImage.width),
            height: capturedSelectionRect.height / CGFloat(capturedImage.height)
        )
        let canvasLineWidth = lineWidth * annotationPixelSizeInCanvas.width
        annotationDragAnchorInCanvas = point
        switch tool {
        case .arrow:
            draftAnnotation = OverlayAnnotation(
                kind: .arrow,
                pointsInCanvas: [point, point],
                color: color,
                lineWidth: canvasLineWidth,
                minimumArrowheadLength: 10 * annotationPixelSizeInCanvas.width,
                creationPixelSizeInCanvas: annotationPixelSizeInCanvas
            )
        case .rectangle:
            draftAnnotation = OverlayAnnotation(
                kind: .rectangle,
                rectInCanvas: CGRect(origin: point, size: .zero),
                color: color,
                lineWidth: canvasLineWidth,
                creationPixelSizeInCanvas: annotationPixelSizeInCanvas
            )
        case .draw:
            draftAnnotation = OverlayAnnotation(
                kind: .draw,
                pointsInCanvas: [point],
                color: color,
                lineWidth: canvasLineWidth,
                creationPixelSizeInCanvas: annotationPixelSizeInCanvas
            )
        case .highlight:
            draftAnnotation = OverlayAnnotation(
                kind: .highlight,
                pointsInCanvas: [point],
                color: color.withAlphaComponent(0.35),
                lineWidth: canvasLineWidth * 3,
                creationPixelSizeInCanvas: annotationPixelSizeInCanvas
            )
        case .text:
            draftAnnotation = OverlayAnnotation(
                kind: .text,
                text: "",
                textPositionInCanvas: point,
                color: color,
                fontSize: (fontSize ?? Self.defaultTextFontSize) * annotationPixelSizeInCanvas.height,
                creationPixelSizeInCanvas: annotationPixelSizeInCanvas
            )
        }
    }

    func updateAnnotation(to point: CGPoint) {
        guard let annotationDragAnchorInCanvas, var draftAnnotation else { return }

        switch draftAnnotation.kind {
        case .arrow:
            draftAnnotation.pointsInCanvas = [annotationDragAnchorInCanvas, point]
        case .rectangle:
            draftAnnotation.rectInCanvas = Self.normalizedRect(from: annotationDragAnchorInCanvas, to: point)
        case .draw, .highlight:
            if draftAnnotation.pointsInCanvas.last.map({ annotationPixelDistance(from: $0, to: point) >= 1 }) ?? true {
                draftAnnotation.pointsInCanvas.append(point)
            }
        case .text:
            return
        }
        self.draftAnnotation = draftAnnotation
    }

    func commitAnnotation() {
        defer {
            annotationDragAnchorInCanvas = nil
            draftAnnotation = nil
        }

        guard let draftAnnotation else { return }
        guard draftAnnotation.kind != .text else { return }
        if let rect = draftAnnotation.rectInCanvas,
           rect.width < annotationPixelSizeInCanvas.width || rect.height < annotationPixelSizeInCanvas.height {
            return
        }
        if draftAnnotation.kind == .arrow,
           let start = draftAnnotation.pointsInCanvas.first,
           let end = draftAnnotation.pointsInCanvas.last,
           annotationPixelDistance(from: start, to: end) < 1 {
            return
        }
        if draftAnnotation.pointsInCanvas.count == 1 {
            return
        }

        annotations.append(draftAnnotation)
    }

    func updateDraftText(_ text: String) {
        guard var draftAnnotation, draftAnnotation.kind == .text else { return }
        draftAnnotation.text = text
        self.draftAnnotation = draftAnnotation
    }

    func commitDraftText() {
        defer {
            annotationDragAnchorInCanvas = nil
            draftAnnotation = nil
        }

        guard var draftAnnotation, draftAnnotation.kind == .text else { return }
        let trimmedText = draftAnnotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        draftAnnotation.text = trimmedText
        annotations.append(draftAnnotation)
    }

    func undoLastAnnotation() {
        if draftAnnotation != nil {
            draftAnnotation = nil
            annotationDragAnchorInCanvas = nil
            return
        }

        _ = annotations.popLast()
    }

    func reset() {
        snapshots = []
        anchorPoint = nil
        currentPoint = nil
        canonicalSelectionRect = nil
        isSelectionAnchored = false
        capturedPNG = nil
        capturedImage = nil
        capturedSelectionRect = nil
        annotationCanvas = nil
        annotations = []
        draftAnnotation = nil
        annotationDragAnchorInCanvas = nil
        annotationPixelSizeInCanvas = CGSize(width: 1, height: 1)
    }

    private func annotationPixelDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot((end.x - start.x) / annotationPixelSizeInCanvas.width,
              (end.y - start.y) / annotationPixelSizeInCanvas.height)
    }

    private func setAnchoredSelectionRect(_ rect: NSRect) {
        let rect = rect.standardized
        anchorPoint = rect.origin
        currentPoint = NSPoint(x: rect.maxX, y: rect.maxY)
        canonicalSelectionRect = rect
        isSelectionAnchored = true
    }

    private func constrainedRect(_ rect: NSRect) -> NSRect {
        guard let snapshotBounds else { return rect }

        return NSRect(
            x: Self.clamp(rect.minX, min: snapshotBounds.minX, max: snapshotBounds.maxX - rect.width),
            y: Self.clamp(rect.minY, min: snapshotBounds.minY, max: snapshotBounds.maxY - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    private var snapshotBounds: NSRect? {
        var result: NSRect?
        for snapshot in snapshots {
            let frame = snapshot.display.frameInAppKitScreenSpace
            result = result.map { $0.union(frame) } ?? frame
        }
        return result
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else {
            return minValue
        }

        return min(max(value, minValue), maxValue)
    }

    private static func cropFrozenSnapshots(_ snapshots: [DisplaySnapshot], to rect: CGRect, captureID: String) throws -> (image: CGImage, rect: CGRect) {
        let selectionRect = rect.standardized
        guard selectionRect.width > 0, selectionRect.height > 0 else {
            throw ScreenshotCaptureError.emptyRegion
        }

        let intersectingSnapshots = snapshots.compactMap { snapshot -> (snapshot: DisplaySnapshot, intersection: CGRect)? in
            let intersection = snapshot.display.frameInAppKitScreenSpace.intersection(selectionRect).standardized
            guard !intersection.isEmpty else { return nil }
            return (snapshot, intersection)
        }

        guard !intersectingSnapshots.isEmpty else {
            throw ScreenshotCaptureError.regionOutsideDisplays(
                ScreenRegion(rectInAppKitScreenSpace: selectionRect, displays: snapshots.map(\.display))
            )
        }

        if intersectingSnapshots.count == 1,
           let snapshot = intersectingSnapshots.first?.snapshot,
           snapshot.display.frameInAppKitScreenSpace.contains(selectionRect) {
            return try cropSingleDisplaySnapshot(snapshot, to: selectionRect, captureID: captureID)
        }

        let outputScale = intersectingSnapshots
            .map { CGFloat($0.snapshot.image.width) / $0.snapshot.display.frameInAppKitScreenSpace.width }
            .max() ?? 1
        let outputWidth = max(1, Int(ceil(selectionRect.width * outputScale)))
        let outputHeight = max(1, Int(ceil(selectionRect.height * outputScale)))
        // Allocation rounds outward. Background content and annotations must
        // share the resulting effective X/Y density, not the nominal scale.
        let outputScaleX = CGFloat(outputWidth) / selectionRect.width
        let outputScaleY = CGFloat(outputHeight) / selectionRect.height
        AppLogging.selection.debug("Composite crop id=\(captureID, privacy: .public) displays=\(intersectingSnapshots.count) scale=\(Double(outputScale)) pixels=\(outputWidth)x\(outputHeight)")
        CaptureDiagnostics.log("composite selection=\(selectionRect) intersectingDisplays=\(intersectingSnapshots.count) scale=\(outputScale) output=\(outputWidth)x\(outputHeight)", captureID: captureID)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.missingBitmapContext
        }

        for (snapshot, intersection) in intersectingSnapshots {
            let frame = snapshot.display.frameInAppKitScreenSpace
            let scaleX = CGFloat(snapshot.image.width) / frame.width
            let scaleY = CGFloat(snapshot.image.height) / frame.height
            let sourceRect = CGRect(
                x: (intersection.minX - frame.minX) * scaleX,
                y: (frame.maxY - intersection.maxY) * scaleY,
                width: intersection.width * scaleX,
                height: intersection.height * scaleY
            )
            .integral
            .intersection(CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))

            guard let croppedImage = snapshot.image.cropping(to: sourceRect), !sourceRect.isEmpty else { continue }

            let destinationRect = CGRect(
                x: (intersection.minX - selectionRect.minX) * outputScaleX,
                y: (intersection.minY - selectionRect.minY) * outputScaleY,
                width: intersection.width * outputScaleX,
                height: intersection.height * outputScaleY
            )
            // The integral source crop can include extra edge pixels. Preserve
            // their actual screen extent rather than squeezing them into the
            // fractional intersection, which would move content beneath marks.
            let alignedSourceFrame = CGRect(
                x: frame.minX + sourceRect.minX / scaleX,
                y: frame.maxY - sourceRect.maxY / scaleY,
                width: sourceRect.width / scaleX,
                height: sourceRect.height / scaleY
            )
            let alignedDestinationRect = CGRect(
                x: (alignedSourceFrame.minX - selectionRect.minX) * outputScaleX,
                y: (alignedSourceFrame.minY - selectionRect.minY) * outputScaleY,
                width: alignedSourceFrame.width * outputScaleX,
                height: alignedSourceFrame.height * outputScaleY
            )
            CaptureDiagnostics.log("composite display=\(snapshot.display.localizedName) intersection=\(intersection) sourcePixels=\(sourceRect) destinationPixels=\(destinationRect)", captureID: captureID)
            CaptureDiagnostics.record(croppedImage, stage: "direct-source-crop", captureID: captureID)
            context.saveGState()
            // Display intersections tile the output. Antialiased clip coverage
            // would source-over two partial pixels into a translucent seam.
            context.setShouldAntialias(false)
            context.clip(to: destinationRect)
            context.draw(croppedImage, in: alignedDestinationRect)
            context.restoreGState()
        }

        guard let outputImage = context.makeImage() else {
            throw RenderError.missingCGImage
        }

        return (outputImage, selectionRect)
    }

    private static func cropSingleDisplaySnapshot(_ snapshot: DisplaySnapshot, to rect: CGRect, captureID: String) throws -> (image: CGImage, rect: CGRect) {
        let frame = snapshot.display.frameInAppKitScreenSpace
        let scaleX = CGFloat(snapshot.image.width) / frame.width
        let scaleY = CGFloat(snapshot.image.height) / frame.height
        // Expand to include every source pixel touched by the selection. Use
        // measured X/Y density rather than assuming a display's backing scale.
        // Aligned point bounds can round-trip to e.g. 214.00000000000003
        // pixels at non-integer densities. Remove only sub-pixel numerical
        // noise before rounding outward, otherwise repeated crops can grow.
        let minX = floor(sourcePixelEdge((rect.minX - frame.minX) * scaleX))
        let maxX = ceil(sourcePixelEdge((rect.maxX - frame.minX) * scaleX))
        let minY = floor(sourcePixelEdge((frame.maxY - rect.maxY) * scaleY))
        let maxY = ceil(sourcePixelEdge((frame.maxY - rect.minY) * scaleY))
        let sourceRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
        guard !sourceRect.isEmpty, let image = snapshot.image.cropping(to: sourceRect) else {
            throw RenderError.missingCGImage
        }
        let alignedRect = CGRect(
            x: frame.minX + sourceRect.minX / scaleX,
            y: frame.maxY - sourceRect.maxY / scaleY,
            width: sourceRect.width / scaleX,
            height: sourceRect.height / scaleY
        )
        AppLogging.selection.debug("Direct crop id=\(captureID, privacy: .public) sourcePixels=\(String(describing: sourceRect), privacy: .public) alignedSelection=\(String(describing: alignedRect), privacy: .public)")
        CaptureDiagnostics.log("direct crop display=\(snapshot.display.localizedName) requested=\(rect) sourcePixels=\(sourceRect) alignedSelection=\(alignedRect)", captureID: captureID)
        CaptureDiagnostics.record(image, stage: "direct-source-crop", captureID: captureID)
        return (image, alignedRect)
    }

    private static func sourcePixelEdge(_ value: CGFloat) -> CGFloat {
        let nearest = value.rounded()
        return abs(value - nearest) < 0.0000001 ? nearest : value
    }

    private static let defaultTextFontSize: CGFloat = 28
}

enum OverlayAnnotationTool: CaseIterable {
    case arrow
    case rectangle
    case draw
    case highlight
    case text
}

struct OverlayAnnotation: Identifiable {
    let id: UUID
    var kind: OverlayAnnotationTool
    var rectInCanvas: CGRect?
    var pointsInCanvas: [CGPoint]
    var text: String
    var textPositionInCanvas: CGPoint?
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var minimumArrowheadLength: CGFloat
    // Retain the creation-time pixel basis for stroke/glyph proportions when
    // measured X/Y density differs. Selection changes never update this basis.
    let creationPixelSizeInCanvas: CGSize

    init(
        id: UUID = UUID(),
        kind: OverlayAnnotationTool,
        rectInCanvas: CGRect? = nil,
        pointsInCanvas: [CGPoint] = [],
        text: String = "",
        textPositionInCanvas: CGPoint? = nil,
        color: NSColor = .systemRed,
        lineWidth: CGFloat = 4,
        fontSize: CGFloat = 28,
        minimumArrowheadLength: CGFloat = 10,
        creationPixelSizeInCanvas: CGSize = CGSize(width: 1, height: 1)
    ) {
        self.id = id
        self.kind = kind
        self.rectInCanvas = rectInCanvas?.standardized
        self.pointsInCanvas = pointsInCanvas
        self.text = text
        self.textPositionInCanvas = textPositionInCanvas
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.minimumArrowheadLength = minimumArrowheadLength
        self.creationPixelSizeInCanvas = creationPixelSizeInCanvas
    }
}

final class RegionCaptureOverlayWindow: NSWindow {
    let overlayView: RegionCaptureOverlayView

    init(
        screen: NSScreen,
        selectionState: RegionSelectionState,
        close: @escaping () -> Void,
        copy: @escaping (Data) -> Void,
        save: @escaping (Data) -> Void,
        selectionCompleted: @escaping (CGRect) -> Void,
        defaultAnnotationColor: NSColor,
        defaultAnnotationStrokeWidth: CGFloat,
        refresh: @escaping () -> Void
    ) {
        overlayView = RegionCaptureOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            selectionState: selectionState,
            close: close,
            copy: copy,
            save: save,
            selectionCompleted: selectionCompleted,
            defaultAnnotationColor: defaultAnnotationColor,
            defaultAnnotationStrokeWidth: defaultAnnotationStrokeWidth,
            refresh: refresh
        )

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = overlayView
        ignoresMouseEvents = false
        isMovable = false
        isOpaque = false
        level = .screenSaver
        sharingType = .none
        titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if overlayView.handleCommandKeyEquivalent(event, source: "window") {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

final class RegionCaptureOverlayView: NSView {
    private let selectionState: RegionSelectionState
    private let close: () -> Void
    private let copy: (Data) -> Void
    private let save: (Data) -> Void
    private let selectionCompleted: (CGRect) -> Void
    private let refresh: () -> Void
    private let annotationToolbarBackground = FloatingToolbarBackgroundView()
    private let actionBarBackground = FloatingToolbarBackgroundView()
    private let shortcutHelpView = OverlayShortcutHelpView()
    private let moveButton = SolidActionButton(symbolName: "hand.raised", accessibilityDescription: "Move")
    private let arrowButton = SolidActionButton(symbolName: "arrow.up.right", accessibilityDescription: "Arrow")
    private let textButton = SolidActionButton(symbolName: "textformat", accessibilityDescription: "Text")
    private let rectangleButton = SolidActionButton(symbolName: "rectangle", accessibilityDescription: "Rectangle")
    private let drawButton = SolidActionButton(symbolName: "pencil.tip", accessibilityDescription: "Draw")
    private let highlightButton = SolidActionButton(symbolName: "highlighter", accessibilityDescription: "Highlight")
    private let colorButton = SolidActionButton(symbolName: nil, accessibilityDescription: "Color")
    private let strokeButton = SolidActionButton(symbolName: "lineweight", accessibilityDescription: "Size")
    private let undoButton = SolidActionButton(
        symbolName: "arrow.uturn.backward",
        accessibilityDescription: "Undo",
        helpText: "Undo (Cmd-Z)"
    )
    private let copyButton = SolidActionButton(
        symbolName: "doc.on.doc",
        accessibilityDescription: "Copy",
        helpText: "Copy (Cmd-C)"
    )
    private let saveButton = SolidActionButton(
        symbolName: "square.and.arrow.down",
        accessibilityDescription: "Save",
        helpText: "Save (Cmd-S)"
    )
    private let closeButton = SolidActionButton(
        symbolName: "xmark",
        accessibilityDescription: "Cancel",
        helpText: "Cancel (Esc)"
    )
    private var activeAnnotationTool: OverlayAnnotationTool?
    private var isMoveToolActive = true
    private var selectionMoveStartPoint: NSPoint?
    private var selectionMoveStartRect: NSRect?
    private var selectionResizeHandle: RegionSelectionResizeHandle?
    private var selectionResizeStartRect: NSRect?
    private var pendingReselectionStartPoint: NSPoint?
    private var isReselectingRegion = false
    private var diagnosticDragEventCount = 0
    private var selectedColor: NSColor
    private var selectedStrokeIndex: Int
    private var colorPopover: NSPopover?
    private var strokePopover: NSPopover?
    private var activeTextField: AnnotationTextEditor?
    private weak var shortcutHelpOwner: SolidActionButton?
    private static let availableColors: [NSColor] = [
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .systemPurple,
        .white,
        .black
    ]
    private static let availableStrokeWidths = PreferencesStore.annotationStrokeWidths
    private static let toolbarButtonSize = NSSize(width: 30, height: 30)
    private static let toolbarPadding: CGFloat = 5
    private static let toolbarGap: CGFloat = 4
    private static let resizeHandleSize = NSSize(width: 8, height: 8)
    private static let resizeHandleHitOutset: CGFloat = 6

    init(
        frame frameRect: NSRect,
        selectionState: RegionSelectionState,
        close: @escaping () -> Void,
        copy: @escaping (Data) -> Void,
        save: @escaping (Data) -> Void,
        selectionCompleted: @escaping (CGRect) -> Void,
        defaultAnnotationColor: NSColor,
        defaultAnnotationStrokeWidth: CGFloat,
        refresh: @escaping () -> Void
    ) {
        self.selectionState = selectionState
        self.close = close
        self.copy = copy
        self.save = save
        self.selectionCompleted = selectionCompleted
        self.selectedColor = defaultAnnotationColor
        self.selectedStrokeIndex = Self.nearestStrokeIndex(for: defaultAnnotationStrokeWidth)
        self.refresh = refresh
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureActionButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
        AppLogging.selection.debug("Overlay view attached id=\(self.selectionState.captureID, privacy: .public)")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            colorPopover?.close()
            strokePopover?.close()
            activeTextField?.finishEditing()
            activeTextField?.removeFromSuperview()
            activeTextField = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)

        guard selectionState.isSelectionAnchored, let selectionRect = selectionState.selectionRect else {
            return
        }

        let fullLocalSelectionRect = convertScreenRectToLocal(selectionRect)
        let visibleSelectionRect = fullLocalSelectionRect.intersection(bounds)
        if !visibleSelectionRect.isEmpty {
            addCursorRect(visibleSelectionRect, cursor: isMoveToolActive ? .openHand : .arrow)
        }
        if canResizeRegion {
            for handle in RegionSelectionResizeHandle.allCases {
                let hitRect = resizeHandleHitRect(for: handle, in: fullLocalSelectionRect).intersection(bounds)
                if !hitRect.isEmpty {
                    addCursorRect(hitRect, cursor: handle.cursor)
                }
            }
        }

        if !moveButton.isHidden {
            addCursorRect(moveButton.frame, cursor: .arrow)
        }
        if !copyButton.isHidden {
            addCursorRect(copyButton.frame, cursor: .arrow)
        }
        if !saveButton.isHidden {
            addCursorRect(saveButton.frame, cursor: .arrow)
        }
        if !arrowButton.isHidden {
            addCursorRect(arrowButton.frame, cursor: .arrow)
        }
        if !textButton.isHidden {
            addCursorRect(textButton.frame, cursor: .arrow)
        }
        if !rectangleButton.isHidden {
            addCursorRect(rectangleButton.frame, cursor: .arrow)
        }
        if !drawButton.isHidden {
            addCursorRect(drawButton.frame, cursor: .arrow)
        }
        if !highlightButton.isHidden {
            addCursorRect(highlightButton.frame, cursor: .arrow)
        }
        if !colorButton.isHidden {
            addCursorRect(colorButton.frame, cursor: .arrow)
        }
        if !strokeButton.isHidden {
            addCursorRect(strokeButton.frame, cursor: .arrow)
        }
        if !undoButton.isHidden {
            addCursorRect(undoButton.frame, cursor: .arrow)
        }
        if !closeButton.isHidden {
            addCursorRect(closeButton.frame, cursor: .arrow)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = screenPoint(for: event)
        diagnosticDragEventCount = 0
        CaptureDiagnostics.log("mouseDown window=\(window?.windowNumber ?? -1) frame=\(window?.frame ?? .zero) key=\(window?.isKeyWindow ?? false) point=\(point) anchored=\(selectionState.isSelectionAnchored) captured=\(selectionState.capturedImage != nil)", captureID: selectionState.captureID)
        if let activeTextField {
            let localPoint = convert(event.locationInWindow, from: nil)
            if !activeTextField.frame.contains(localPoint) {
                commitActiveTextField()
            }
        }
        if let handle = resizeHandle(at: convert(event.locationInWindow, from: nil)) {
            beginSelectionResize(handle: handle)
            return
        }
        if let activeAnnotationTool, let canvasPoint = canvasPointForAnnotationEvent(event) {
            if activeAnnotationTool == .text {
                beginTextAnnotation(event: event)
                return
            }
            selectionState.beginAnnotation(
                tool: activeAnnotationTool,
                at: canvasPoint,
                color: selectedColor,
                lineWidth: selectedStrokeWidth
            )
            refresh()
            return
        }
        if selectionState.capturedImage != nil, isMoveToolActive {
            if selectionContains(point) {
                beginSelectionMove(at: point)
            } else if canReselectRegion {
                pendingReselectionStartPoint = point
                isReselectingRegion = false
            }
            return
        }
        if selectionState.capturedImage != nil {
            return
        }

        if selectionState.isSelectionAnchored, selectionContains(point) {
            return
        }

        AppLogging.selection.debug("Selection started id=\(self.selectionState.captureID, privacy: .public) point=\(String(describing: point), privacy: .public)")
        selectionState.beginSelection(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        diagnosticDragEventCount += 1
        if diagnosticDragEventCount == 1 || diagnosticDragEventCount.isMultiple(of: 30) {
            AppLogging.selection.debug("Drag id=\(self.selectionState.captureID, privacy: .public) events=\(self.diagnosticDragEventCount) point=\(String(describing: self.screenPoint(for: event)), privacy: .public)")
            CaptureDiagnostics.log("mouseDragged window=\(window?.windowNumber ?? -1) count=\(diagnosticDragEventCount) point=\(screenPoint(for: event)) selection=\(String(describing: selectionState.selectionRect)) anchored=\(selectionState.isSelectionAnchored) captured=\(selectionState.capturedImage != nil)", captureID: selectionState.captureID)
        }
        if selectionResizeHandle != nil {
            updateSelectionResize(to: screenPoint(for: event))
            return
        }
        if selectionMoveStartPoint != nil {
            updateSelectionMove(to: screenPoint(for: event))
            return
        }
        if pendingReselectionStartPoint != nil {
            updatePendingReselection(to: screenPoint(for: event))
            return
        }
        if activeAnnotationTool != nil, activeAnnotationTool != .text, let canvasPoint = canvasPointForAnnotationEvent(event) {
            selectionState.updateAnnotation(to: canvasPoint)
            refresh()
            return
        }
        if selectionState.capturedImage != nil {
            return
        }

        selectionState.updateSelection(to: screenPoint(for: event))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        AppLogging.selection.debug("Mouse released id=\(self.selectionState.captureID, privacy: .public) dragEvents=\(self.diagnosticDragEventCount)")
        CaptureDiagnostics.log("mouseUp window=\(window?.windowNumber ?? -1) point=\(screenPoint(for: event)) dragEvents=\(diagnosticDragEventCount)", captureID: selectionState.captureID)
        if selectionResizeHandle != nil {
            finishSelectionResize()
            return
        }
        if selectionMoveStartPoint != nil {
            finishSelectionMove()
            return
        }
        if pendingReselectionStartPoint != nil {
            finishPendingReselection(at: screenPoint(for: event))
            return
        }
        if activeAnnotationTool != nil, activeAnnotationTool != .text, let canvasPoint = canvasPointForAnnotationEvent(event) {
            selectionState.updateAnnotation(to: canvasPoint)
            selectionState.commitAnnotation()
            refresh()
            return
        }
        if selectionState.capturedImage != nil {
            guard activeAnnotationTool != .text else { return }
            selectionState.commitAnnotation()
            refresh()
            return
        }

        selectionState.anchorSelection(at: screenPoint(for: event))
        refresh()

        if let selectionRect = selectionState.selectionRect, selectionRect.width >= 1, selectionRect.height >= 1 {
            AppLogging.selection.debug("Selection completed id=\(self.selectionState.captureID, privacy: .public) rect=\(String(describing: selectionRect), privacy: .public)")
            selectionCompleted(selectionRect)
        } else {
            AppLogging.selection.debug("Ignored empty selection id=\(self.selectionState.captureID, privacy: .public)")
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            CaptureDiagnostics.log("escape window=\(window?.windowNumber ?? -1)", captureID: selectionState.captureID)
            if activeAnnotationTool != nil || activeTextField != nil {
                exitAnnotationMode()
                return
            }
            close()
        } else if handleCommandKeyEquivalent(event, source: "view keyDown") {
            return
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleCommandKeyEquivalent(event, source: "view performKeyEquivalent") || super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let drewFrozenBackground = drawFrozenSnapshots(in: bounds)
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()

        guard let selectionRect = selectionState.selectionRect, !selectionRect.isEmpty else { return }

        let fullLocalSelectionRect = convertScreenRectToLocal(selectionRect)
        let localSelectionRect = fullLocalSelectionRect.intersection(bounds)
        guard !localSelectionRect.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: localSelectionRect).addClip()
        if let capturedImage = selectionState.capturedImage, selectionState.capturedSelectionRect == selectionRect {
            NSImage(cgImage: capturedImage, size: fullLocalSelectionRect.size).draw(in: fullLocalSelectionRect)
        } else if drewFrozenBackground {
            drawFrozenSnapshots(in: localSelectionRect)
        } else {
            NSColor.clear.setFill()
            bounds.fill(using: .copy)
        }
        drawAnnotations(in: fullLocalSelectionRect)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: fullLocalSelectionRect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        NSColor.systemBlue.setStroke()
        let accentPath = NSBezierPath(rect: fullLocalSelectionRect.insetBy(dx: 1, dy: 1))
        accentPath.lineWidth = 1
        accentPath.stroke()

        if canResizeRegion {
            drawResizeHandles(in: fullLocalSelectionRect)
        }
    }

    func refreshState() {
        needsDisplay = true
        updateActionButtons()
        window?.invalidateCursorRects(for: self)
    }

    @discardableResult
    private func drawFrozenSnapshots(in clippingRect: NSRect) -> Bool {
        var didDraw = false

        for snapshot in selectionState.snapshots {
            let localSnapshotRect = convertScreenRectToLocal(snapshot.display.frameInAppKitScreenSpace).intersection(bounds)
            guard !localSnapshotRect.isEmpty, localSnapshotRect.intersects(clippingRect) else { continue }

            NSImage(cgImage: snapshot.image, size: localSnapshotRect.size).draw(in: localSnapshotRect)
            didDraw = true
        }

        return didDraw
    }

    private func configureActionButtons() {
        annotationToolbarBackground.isHidden = true
        addSubview(annotationToolbarBackground)
        actionBarBackground.isHidden = true
        addSubview(actionBarBackground)

        moveButton.target = self
        moveButton.action = #selector(moveButtonPressed)
        moveButton.isHidden = true
        addSubview(moveButton)

        arrowButton.target = self
        arrowButton.action = #selector(arrowButtonPressed)
        arrowButton.isHidden = true
        addSubview(arrowButton)

        textButton.target = self
        textButton.action = #selector(textButtonPressed)
        textButton.isHidden = true
        addSubview(textButton)

        rectangleButton.target = self
        rectangleButton.action = #selector(rectangleButtonPressed)
        rectangleButton.isHidden = true
        addSubview(rectangleButton)

        drawButton.target = self
        drawButton.action = #selector(drawButtonPressed)
        drawButton.isHidden = true
        addSubview(drawButton)

        highlightButton.target = self
        highlightButton.action = #selector(highlightButtonPressed)
        highlightButton.isHidden = true
        addSubview(highlightButton)

        colorButton.target = self
        colorButton.action = #selector(colorButtonPressed)
        colorButton.isHidden = true
        addSubview(colorButton)

        strokeButton.target = self
        strokeButton.action = #selector(strokeButtonPressed)
        strokeButton.isHidden = true
        addSubview(strokeButton)

        undoButton.target = self
        undoButton.action = #selector(undoButtonPressed)
        undoButton.isHidden = true
        addSubview(undoButton)

        copyButton.target = self
        copyButton.action = #selector(copyButtonPressed)
        copyButton.isHidden = true
        addSubview(copyButton)

        saveButton.target = self
        saveButton.action = #selector(saveButtonPressed)
        saveButton.isHidden = true
        addSubview(saveButton)

        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        closeButton.isHidden = true
        addSubview(closeButton)

        [undoButton, copyButton, saveButton, closeButton].forEach(configureShortcutHelp)
        shortcutHelpView.isHidden = true
        addSubview(shortcutHelpView)
    }

    private func updateActionButtons() {
        guard
            let selectionRect = selectionState.selectionRect,
            selectionState.capturedImage != nil
        else {
            activeAnnotationTool = nil
            isMoveToolActive = true
            colorPopover?.close()
            strokePopover?.close()
            hideFloatingControls()
            return
        }

        let localSelectionRect = convertScreenRectToLocal(selectionRect).intersection(bounds)
        guard !localSelectionRect.isEmpty else {
            activeAnnotationTool = nil
            isMoveToolActive = true
            colorPopover?.close()
            strokePopover?.close()
            hideFloatingControls()
            return
        }

        moveButton.isActive = isMoveToolActive && activeAnnotationTool == nil
        drawButton.isActive = activeAnnotationTool == .draw
        highlightButton.isActive = activeAnnotationTool == .highlight
        arrowButton.isActive = activeAnnotationTool == .arrow
        textButton.isActive = activeAnnotationTool == .text
        rectangleButton.isActive = activeAnnotationTool == .rectangle
        colorButton.swatchColor = selectedColor

        let annotationButtons = [moveButton, drawButton, highlightButton, arrowButton, textButton, rectangleButton, colorButton, strokeButton, undoButton]
        let actionButtons = [copyButton, saveButton, closeButton]
        let toolbarSize = floatingBarSize(buttonCount: annotationButtons.count, axis: .vertical)
        let actionBarSize = floatingBarSize(buttonCount: actionButtons.count, axis: .horizontal)
        annotationToolbarBackground.configure(
            axis: .vertical,
            buttonCount: annotationButtons.count,
            buttonSize: Self.toolbarButtonSize,
            padding: Self.toolbarPadding,
            gap: Self.toolbarGap
        )
        actionBarBackground.configure(
            axis: .horizontal,
            buttonCount: actionButtons.count,
            buttonSize: Self.toolbarButtonSize,
            padding: Self.toolbarPadding,
            gap: Self.toolbarGap
        )
        annotationToolbarBackground.frame = annotationToolbarFrame(for: toolbarSize, beside: localSelectionRect)
        actionBarBackground.frame = actionBarFrame(for: actionBarSize, beside: localSelectionRect)
        layout(buttons: annotationButtons, in: annotationToolbarBackground.frame, axis: .vertical)
        layout(buttons: actionButtons, in: actionBarBackground.frame, axis: .horizontal)
        annotationToolbarBackground.isHidden = false
        actionBarBackground.isHidden = false
        annotationButtons.forEach { $0.isHidden = false }
        actionButtons.forEach { $0.isHidden = false }
    }

    fileprivate enum FloatingBarAxis {
        case horizontal
        case vertical
    }

    private func hideFloatingControls() {
        annotationToolbarBackground.isHidden = true
        actionBarBackground.isHidden = true
        hideShortcutHelp()
        [moveButton, arrowButton, textButton, rectangleButton, drawButton, highlightButton, colorButton, strokeButton, undoButton, copyButton, saveButton, closeButton].forEach {
            $0.isHidden = true
        }
    }

    private func configureShortcutHelp(for button: SolidActionButton) {
        guard let shortcutHelpText = button.shortcutHelpText else { return }
        button.hoverChanged = { [weak self, weak button] isHovering in
            guard let self, let button else { return }
            if isHovering {
                self.showShortcutHelp(shortcutHelpText, for: button)
            } else {
                self.hideShortcutHelp(for: button)
            }
        }
    }

    private func showShortcutHelp(_ text: String, for button: SolidActionButton) {
        shortcutHelpOwner = button
        shortcutHelpView.stringValue = text
        shortcutHelpView.sizeToFitHelp()

        let margin: CGFloat = 6
        let edgeInset: CGFloat = 8
        let helpSize = shortcutHelpView.frame.size
        let x = min(
            max(button.frame.midX - helpSize.width / 2, edgeInset),
            bounds.maxX - helpSize.width - edgeInset
        )
        let preferredY = button.frame.maxY + margin
        let fallbackY = button.frame.minY - helpSize.height - margin
        let y = preferredY + helpSize.height <= bounds.maxY - edgeInset ? preferredY : fallbackY

        shortcutHelpView.frame.origin = NSPoint(
            x: x,
            y: min(max(y, edgeInset), bounds.maxY - helpSize.height - edgeInset)
        )
        shortcutHelpView.isHidden = false
    }

    private func hideShortcutHelp(for button: SolidActionButton? = nil) {
        guard button == nil || shortcutHelpOwner === button else { return }
        shortcutHelpOwner = nil
        shortcutHelpView.isHidden = true
    }

    private func floatingBarSize(buttonCount: Int, axis: FloatingBarAxis) -> NSSize {
        let button = Self.toolbarButtonSize
        let padding = Self.toolbarPadding
        let gap = Self.toolbarGap

        switch axis {
        case .horizontal:
            return NSSize(
                width: padding * 2 + button.width * CGFloat(buttonCount) + gap * CGFloat(max(buttonCount - 1, 0)),
                height: padding * 2 + button.height
            )
        case .vertical:
            return NSSize(
                width: padding * 2 + button.width,
                height: padding * 2 + button.height * CGFloat(buttonCount) + gap * CGFloat(max(buttonCount - 1, 0))
            )
        }
    }

    private func annotationToolbarFrame(for toolbarSize: NSSize, beside selectionRect: NSRect) -> NSRect {
        let margin: CGFloat = 8
        let preferredY = clamp(
            selectionRect.maxY - toolbarSize.height,
            min: margin,
            max: bounds.maxY - toolbarSize.height - margin
        )
        let rightFrame = NSRect(
            x: selectionRect.maxX + margin,
            y: preferredY,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        if bounds.insetBy(dx: margin, dy: margin).contains(rightFrame) {
            return rightFrame
        }

        let leftFrame = NSRect(
            x: selectionRect.minX - toolbarSize.width - margin,
            y: preferredY,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        if bounds.insetBy(dx: margin, dy: margin).contains(leftFrame) {
            return leftFrame
        }

        let insideRightFrame = NSRect(
            x: selectionRect.maxX - toolbarSize.width - margin,
            y: preferredY,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        let insideLeftFrame = NSRect(
            x: selectionRect.minX + margin,
            y: preferredY,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        let fallbackFrame = selectionRect.midX < bounds.midX ? insideRightFrame : insideLeftFrame
        return clampedFrame(fallbackFrame, margin: margin)
    }

    private func actionBarFrame(for actionBarSize: NSSize, beside selectionRect: NSRect) -> NSRect {
        let margin: CGFloat = 8
        let preferredX = clamp(
            selectionRect.maxX - actionBarSize.width,
            min: margin,
            max: bounds.maxX - actionBarSize.width - margin
        )
        let belowFrame = NSRect(
            x: preferredX,
            y: selectionRect.minY - actionBarSize.height - margin,
            width: actionBarSize.width,
            height: actionBarSize.height
        )
        if bounds.insetBy(dx: margin, dy: margin).contains(belowFrame) {
            return belowFrame
        }

        let aboveFrame = NSRect(
            x: preferredX,
            y: selectionRect.maxY + margin,
            width: actionBarSize.width,
            height: actionBarSize.height
        )
        if bounds.insetBy(dx: margin, dy: margin).contains(aboveFrame) {
            return aboveFrame
        }

        let insideBottomFrame = NSRect(
            x: preferredX,
            y: selectionRect.minY + margin,
            width: actionBarSize.width,
            height: actionBarSize.height
        )
        let insideTopFrame = NSRect(
            x: preferredX,
            y: selectionRect.maxY - actionBarSize.height - margin,
            width: actionBarSize.width,
            height: actionBarSize.height
        )
        let fallbackFrame = selectionRect.midY < bounds.midY ? insideTopFrame : insideBottomFrame
        return clampedFrame(fallbackFrame, margin: margin)
    }

    private func clampedFrame(_ frame: NSRect, margin: CGFloat) -> NSRect {
        NSRect(
            x: clamp(frame.minX, min: margin, max: bounds.maxX - frame.width - margin),
            y: clamp(frame.minY, min: margin, max: bounds.maxY - frame.height - margin),
            width: frame.width,
            height: frame.height
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else {
            return minValue
        }

        return min(max(value, minValue), maxValue)
    }

    private func layout(buttons: [SolidActionButton], in barFrame: NSRect, axis: FloatingBarAxis) {
        let button = Self.toolbarButtonSize
        let padding = Self.toolbarPadding
        let gap = Self.toolbarGap

        for (index, control) in buttons.enumerated() {
            switch axis {
            case .horizontal:
                control.frame = NSRect(
                    x: barFrame.minX + padding + CGFloat(index) * (button.width + gap),
                    y: barFrame.minY + padding,
                    width: button.width,
                    height: button.height
                )
            case .vertical:
                control.frame = NSRect(
                    x: barFrame.minX + padding,
                    y: barFrame.maxY - padding - button.height - CGFloat(index) * (button.height + gap),
                    width: button.width,
                    height: button.height
                )
            }
        }
    }

    @objc private func moveButtonPressed() {
        commitActiveTextField()
        activeAnnotationTool = nil
        isMoveToolActive = true
        colorPopover?.close()
        strokePopover?.close()
        AppLogging.selection.debug("Move tool selected id=\(self.selectionState.captureID, privacy: .public)")
        refresh()
    }

    @objc private func arrowButtonPressed() {
        commitActiveTextField()
        toggleAnnotationTool(.arrow)
    }

    @objc private func textButtonPressed() {
        commitActiveTextField()
        toggleAnnotationTool(.text)
    }

    @objc private func rectangleButtonPressed() {
        commitActiveTextField()
        toggleAnnotationTool(.rectangle)
    }

    @objc private func drawButtonPressed() {
        commitActiveTextField()
        toggleAnnotationTool(.draw)
    }

    @objc private func highlightButtonPressed() {
        commitActiveTextField()
        toggleAnnotationTool(.highlight)
    }

    @objc private func colorButtonPressed() {
        commitActiveTextField()
        strokePopover?.close()
        let pickerView = ColorSwatchPickerView(
            colors: Self.availableColors,
            selectedColor: selectedColor,
            selectionChanged: { [weak self] color in
                guard let self else { return }
                selectedColor = color
                AppLogging.selection.debug("Annotation color selected id=\(self.selectionState.captureID, privacy: .public)")
                refresh()
                colorPopover?.close()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = pickerView.fittingSize
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = pickerView
        popover.show(relativeTo: colorButton.bounds, of: colorButton, preferredEdge: .minX)
        colorPopover = popover
    }

    @objc private func strokeButtonPressed() {
        commitActiveTextField()
        colorPopover?.close()
        let pickerView = StrokeWidthPickerView(
            strokeWidths: Self.availableStrokeWidths,
            selectedIndex: selectedStrokeIndex,
            selectionChanged: { [weak self] index in
                guard let self else { return }
                selectedStrokeIndex = index
                AppLogging.selection.debug("Annotation size selected id=\(self.selectionState.captureID, privacy: .public) width=\(Double(self.selectedStrokeWidth))")
                refresh()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = pickerView.fittingSize
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = pickerView
        popover.show(relativeTo: strokeButton.bounds, of: strokeButton, preferredEdge: .minX)
        strokePopover = popover
    }

    private func toggleAnnotationTool(_ tool: OverlayAnnotationTool) {
        if activeAnnotationTool == tool {
            activeAnnotationTool = nil
            isMoveToolActive = true
        } else {
            activeAnnotationTool = tool
            isMoveToolActive = false
        }
        AppLogging.selection.debug("Annotation tool selected id=\(self.selectionState.captureID, privacy: .public) tool=\(String(describing: self.activeAnnotationTool), privacy: .public)")
        refresh()
    }

    @objc private func undoButtonPressed() {
        undoLastAnnotation()
    }

    @objc private func copyButtonPressed() {
        copyCapturedPNG()
    }

    private func copyCapturedPNG() {
        commitActiveTextField()
        guard let capturedPNG = renderedPNGForCopy() else {
            AppLogging.export.debug("Copy ignored before PNG ready id=\(self.selectionState.captureID, privacy: .public)")
            NSSound.beep()
            return
        }

        AppLogging.export.debug("Overlay copy requested id=\(self.selectionState.captureID, privacy: .public) bytes=\(capturedPNG.count)")
        copy(capturedPNG)
    }

    func handleCommandKeyEquivalent(_ event: NSEvent, source: String) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return false
        }

        if event.keyCode == Self.cKeyCode || event.charactersIgnoringModifiers?.lowercased() == "c" {
            AppLogging.selection.debug("Cmd+C handled id=\(self.selectionState.captureID, privacy: .public) source=\(source, privacy: .public)")
            copyCapturedPNG()
            return true
        }

        if event.keyCode == Self.sKeyCode || event.charactersIgnoringModifiers?.lowercased() == "s" {
            AppLogging.selection.debug("Cmd+S handled id=\(self.selectionState.captureID, privacy: .public) source=\(source, privacy: .public)")
            saveCapturedPNG()
            return true
        }

        if event.keyCode == Self.zKeyCode || event.charactersIgnoringModifiers?.lowercased() == "z" {
            AppLogging.selection.debug("Cmd+Z handled id=\(self.selectionState.captureID, privacy: .public) source=\(source, privacy: .public)")
            undoLastAnnotation()
            return true
        }

        return false
    }

    @objc private func saveButtonPressed() {
        saveCapturedPNG()
    }

    private func saveCapturedPNG() {
        commitActiveTextField()
        guard let capturedPNG = renderedPNGForCopy() else {
            AppLogging.export.debug("Save ignored before PNG ready id=\(self.selectionState.captureID, privacy: .public)")
            NSSound.beep()
            return
        }

        AppLogging.export.debug("Overlay save requested id=\(self.selectionState.captureID, privacy: .public) bytes=\(capturedPNG.count)")
        save(capturedPNG)
    }

    @objc private func closeButtonPressed() {
        close()
    }

    private func undoLastAnnotation() {
        if activeTextField != nil {
            cancelActiveTextField()
            return
        }
        selectionState.undoLastAnnotation()
        refresh()
    }

    private func beginTextAnnotation(event: NSEvent) {
        commitActiveTextField()

        guard
            selectionState.capturedImage != nil,
            let selectionRect = selectionState.selectionRect,
            let canvas = selectionState.annotationCanvas
        else {
            return
        }

        let fullLocalSelectionRect = convertScreenRectToLocal(selectionRect)
        let localSelectionRect = fullLocalSelectionRect.intersection(bounds)
        guard !localSelectionRect.isEmpty else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        selectionState.beginAnnotation(
            tool: .text,
            at: canvas.point(fromScreen: screenPoint(for: event)),
            color: selectedColor,
            lineWidth: selectedStrokeWidth,
            fontSize: selectedTextFontSize
        )
        guard let draft = selectionState.draftAnnotation else { return }
        let field = AnnotationTextEditor(
            anchor: localPoint,
            pixelSize: draft.creationPixelSizeInCanvas,
            font: .systemFont(ofSize: draft.fontSize / draft.creationPixelSizeInCanvas.height, weight: .semibold),
            color: selectedColor,
            commit: { [weak self] in self?.commitActiveTextField() },
            exitMode: { [weak self] in self?.exitAnnotationMode() }
        )

        activeTextField = field
        addSubview(field)
        window?.makeFirstResponder(field)
        refresh()
    }

    private func commitActiveTextField() {
        guard let activeTextField else { return }
        // Clear ownership before resigning focus: textDidEndEditing can reenter.
        self.activeTextField = nil
        activeTextField.finishEditing()
        selectionState.updateDraftText(activeTextField.string)
        selectionState.commitDraftText()
        activeTextField.removeFromSuperview()
        window?.makeFirstResponder(self)
        refresh()
    }

    private func cancelActiveTextField() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        field.finishEditing()
        field.removeFromSuperview()
        selectionState.undoLastAnnotation()
        window?.makeFirstResponder(self)
        refresh()
    }

    private func exitAnnotationMode() {
        cancelActiveTextField()
        // Esc also exits a selected tool before any text has been placed.
        if selectionState.draftAnnotation != nil {
            selectionState.undoLastAnnotation()
        }
        activeAnnotationTool = nil
        isMoveToolActive = true
        window?.makeFirstResponder(self)
        refresh()
    }

    private func renderedPNGForCopy() -> Data? {
        guard let capturedPNG = selectionState.capturedPNG else { return nil }
        guard let capturedImage = selectionState.capturedImage else { return capturedPNG }
        guard let canvas = selectionState.annotationCanvas,
              let capturedSelectionRect = selectionState.capturedSelectionRect else { return nil }

        do {
            // A shortcut during a drag exports the last committed image/frame,
            // never an old image with the live drag's coordinate mapping.
            let data = try Renderer().renderPNG(
                baseImage: capturedImage,
                annotations: selectionState.annotations,
                canvas: canvas,
                selectionRect: capturedSelectionRect
            )
            AppLogging.export.notice("PNG rendered id=\(self.selectionState.captureID, privacy: .public) pixels=\(capturedImage.width)x\(capturedImage.height) annotations=\(self.selectionState.annotations.count) bytes=\(data.count)")
            CaptureDiagnostics.log("export basePixels=\(capturedImage.width)x\(capturedImage.height) annotations=\(selectionState.annotations.count)", captureID: selectionState.captureID)
            CaptureDiagnostics.recordPNG(data, stage: "export", captureID: selectionState.captureID)
            return data
        } catch {
            AppLogging.export.error("PNG render failed id=\(self.selectionState.captureID, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func selectionContains(_ point: NSPoint) -> Bool {
        guard let selectionRect = selectionState.selectionRect else { return false }
        return selectionRect.contains(point)
    }

    private var canResizeRegion: Bool {
        selectionState.capturedImage != nil
            && isMoveToolActive
            && activeAnnotationTool == nil
            && activeTextField == nil
            && selectionState.draftAnnotation == nil
    }

    private var canReselectRegion: Bool {
        selectionState.capturedImage != nil && !selectionState.hasCommittedOrDraftAnnotations
    }

    private func resizeHandle(at localPoint: NSPoint) -> RegionSelectionResizeHandle? {
        guard
            canResizeRegion,
            let selectionRect = selectionState.selectionRect
        else {
            return nil
        }

        let localSelectionRect = convertScreenRectToLocal(selectionRect)
        guard bounds.contains(localPoint), localSelectionRect.intersects(bounds) else { return nil }

        return RegionSelectionResizeHandle.allCases.first { handle in
            resizeHandleHitRect(for: handle, in: localSelectionRect).contains(localPoint)
        }
    }

    private func beginSelectionResize(handle: RegionSelectionResizeHandle) {
        guard let selectionRect = selectionState.selectionRect else { return }
        selectionResizeHandle = handle
        selectionResizeStartRect = selectionRect
        handle.cursor.set()
    }

    private func updateSelectionResize(to point: NSPoint) {
        guard
            let selectionResizeHandle,
            let selectionResizeStartRect
        else {
            return
        }

        selectionState.resizeAnchoredSelection(
            from: selectionResizeStartRect,
            dragging: selectionResizeHandle,
            to: point
        )
        selectionResizeHandle.cursor.set()
        refresh()
    }

    private func finishSelectionResize() {
        let finishedHandle = selectionResizeHandle
        selectionResizeHandle = nil
        selectionResizeStartRect = nil

        guard let selectionRect = selectionState.selectionRect else {
            refresh()
            return
        }

        AppLogging.selection.debug("Selection resized id=\(self.selectionState.captureID, privacy: .public) handle=\(String(describing: finishedHandle), privacy: .public) rect=\(String(describing: selectionRect), privacy: .public)")
        selectionCompleted(selectionRect)
    }

    private func beginSelectionMove(at point: NSPoint) {
        guard let selectionRect = selectionState.selectionRect else { return }
        selectionMoveStartPoint = point
        selectionMoveStartRect = selectionRect
        NSCursor.closedHand.set()
    }

    private func updateSelectionMove(to point: NSPoint) {
        guard
            let selectionMoveStartPoint,
            let selectionMoveStartRect
        else {
            return
        }

        selectionState.moveAnchoredSelection(
            from: selectionMoveStartRect,
            by: NSSize(
                width: point.x - selectionMoveStartPoint.x,
                height: point.y - selectionMoveStartPoint.y
            )
        )
        NSCursor.closedHand.set()
        refresh()
    }

    private func finishSelectionMove() {
        selectionMoveStartPoint = nil
        selectionMoveStartRect = nil
        NSCursor.openHand.set()

        guard let selectionRect = selectionState.selectionRect else {
            refresh()
            return
        }

        AppLogging.selection.debug("Selection moved id=\(self.selectionState.captureID, privacy: .public) rect=\(String(describing: selectionRect), privacy: .public)")
        selectionCompleted(selectionRect)
    }

    private func updatePendingReselection(to point: NSPoint) {
        guard let pendingReselectionStartPoint else { return }

        if !isReselectingRegion {
            guard hypot(point.x - pendingReselectionStartPoint.x, point.y - pendingReselectionStartPoint.y) >= 1 else {
                return
            }
            isReselectingRegion = true
            selectionState.beginSelection(at: pendingReselectionStartPoint)
        }

        selectionState.updateSelection(to: point)
        refresh()
    }

    private func finishPendingReselection(at point: NSPoint) {
        defer {
            pendingReselectionStartPoint = nil
            isReselectingRegion = false
        }

        guard isReselectingRegion else { return }

        selectionState.anchorSelection(at: point)
        refresh()

        if let selectionRect = selectionState.selectionRect, selectionRect.width >= 1, selectionRect.height >= 1 {
            AppLogging.selection.debug("Selection reselected id=\(self.selectionState.captureID, privacy: .public) rect=\(String(describing: selectionRect), privacy: .public)")
            selectionCompleted(selectionRect)
        } else {
            AppLogging.selection.debug("Ignored empty reselection id=\(self.selectionState.captureID, privacy: .public)")
        }
    }

    private func drawResizeHandles(in selectionRect: NSRect) {
        for handle in RegionSelectionResizeHandle.allCases {
            let frame = resizeHandleFrame(for: handle, in: selectionRect)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: frame).fill()

            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
            borderPath.lineWidth = 1
            borderPath.stroke()
        }
    }

    private func resizeHandleHitRect(for handle: RegionSelectionResizeHandle, in selectionRect: NSRect) -> NSRect {
        resizeHandleFrame(for: handle, in: selectionRect).insetBy(
            dx: -Self.resizeHandleHitOutset,
            dy: -Self.resizeHandleHitOutset
        )
    }

    private func resizeHandleFrame(for handle: RegionSelectionResizeHandle, in selectionRect: NSRect) -> NSRect {
        let center = resizeHandleCenter(for: handle, in: selectionRect)
        return NSRect(
            x: center.x - Self.resizeHandleSize.width / 2,
            y: center.y - Self.resizeHandleSize.height / 2,
            width: Self.resizeHandleSize.width,
            height: Self.resizeHandleSize.height
        )
    }

    private func resizeHandleCenter(for handle: RegionSelectionResizeHandle, in selectionRect: NSRect) -> NSPoint {
        switch handle {
        case .topLeft:
            return NSPoint(x: selectionRect.minX, y: selectionRect.maxY)
        case .top:
            return NSPoint(x: selectionRect.midX, y: selectionRect.maxY)
        case .topRight:
            return NSPoint(x: selectionRect.maxX, y: selectionRect.maxY)
        case .right:
            return NSPoint(x: selectionRect.maxX, y: selectionRect.midY)
        case .bottomRight:
            return NSPoint(x: selectionRect.maxX, y: selectionRect.minY)
        case .bottom:
            return NSPoint(x: selectionRect.midX, y: selectionRect.minY)
        case .bottomLeft:
            return NSPoint(x: selectionRect.minX, y: selectionRect.minY)
        case .left:
            return NSPoint(x: selectionRect.minX, y: selectionRect.midY)
        }
    }

    private func canvasPointForAnnotationEvent(_ event: NSEvent) -> CGPoint? {
        guard
            selectionState.capturedImage != nil,
            let canvas = selectionState.annotationCanvas,
            let selectionRect = selectionState.selectionRect
        else {
            return nil
        }

        let localSelectionRect = convertScreenRectToLocal(selectionRect)
        let visibleSelectionRect = localSelectionRect.intersection(bounds)
        guard !visibleSelectionRect.isEmpty else { return nil }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard visibleSelectionRect.contains(localPoint) else { return nil }

        return canvas.point(fromScreen: screenPoint(for: event))
    }

    private func drawAnnotations(in localSelectionRect: NSRect) {
        guard
            let canvas = selectionState.annotationCanvas,
            let selectionRect = selectionState.selectionRect,
            let context = NSGraphicsContext.current?.cgContext
        else { return }

        Renderer().drawAnnotations(
            selectionState.annotations + [selectionState.draftAnnotation].compactMap({ $0 }),
            canvas: canvas,
            selectionRect: selectionRect,
            in: context,
            destinationRect: localSelectionRect
        )
    }

    private var selectedStrokeWidth: CGFloat {
        Self.availableStrokeWidths[selectedStrokeIndex]
    }

    private static func nearestStrokeIndex(for width: CGFloat) -> Int {
        availableStrokeWidths.enumerated().min { lhs, rhs in
            abs(lhs.element - width) < abs(rhs.element - width)
        }?.offset ?? 1
    }

    private var selectedTextFontSize: CGFloat {
        selectedStrokeWidth * 7
    }

    private var selectedColorTitleColor: NSColor {
        guard let rgbColor = selectedColor.usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.299 * rgbColor.redComponent + 0.587 * rgbColor.greenComponent + 0.114 * rgbColor.blueComponent
        return luminance > 0.62 ? .black : .white
    }

    private func convertScreenRectToLocal(_ rect: NSRect) -> NSRect {
        guard let window else { return rect }

        let windowOrigin = window.convertPoint(fromScreen: rect.origin)
        let windowOppositeCorner = window.convertPoint(
            fromScreen: NSPoint(x: rect.maxX, y: rect.maxY)
        )
        let origin = convert(windowOrigin, from: nil)
        let oppositeCorner = convert(windowOppositeCorner, from: nil)

        return NSRect(
            x: min(origin.x, oppositeCorner.x),
            y: min(origin.y, oppositeCorner.y),
            width: abs(origin.x - oppositeCorner.x),
            height: abs(origin.y - oppositeCorner.y)
        )
    }

    private static let cKeyCode: UInt16 = 8
    private static let sKeyCode: UInt16 = 1
    private static let zKeyCode: UInt16 = 6
}

final class AnnotationTextEditor: NSTextView, NSTextViewDelegate {
    private let textLayout: AnnotationTextLayout
    private let anchor: NSPoint
    private let pixelSize: NSSize
    private let commit: () -> Void
    private let exitMode: () -> Void
    private var isCompleting = false

    init(
        anchor: NSPoint, pixelSize: NSSize, font: NSFont, color: NSColor,
        commit: @escaping () -> Void, exitMode: @escaping () -> Void
    ) {
        self.anchor = anchor
        self.pixelSize = pixelSize
        textLayout = AnnotationTextLayout(font: font, color: color)
        self.commit = commit
        self.exitMode = exitMode
        super.init(frame: .zero, textContainer: textLayout.container)

        delegate = self
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = .zero
        isRichText = false
        importsGraphics = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        focusRingType = .none
        self.font = font
        textColor = color
        insertionPointColor = color
        typingAttributes = AnnotationTextLayout.attributes(font: font, color: color)
        setAccessibilityLabel("Text annotation")
        resizeToFitText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cancelOperation(_ sender: Any?) {
        complete(exitMode)
    }

    func textDidEndEditing(_ notification: Notification) {
        // AppKit also posts this while programmatically editing a detached view.
        // Only focus loss in a window completes a live annotation.
        guard window != nil, notification.object as? NSTextView === self else { return }
        complete(commit)
    }

    override func didChangeText() {
        super.didChangeText()
        resizeToFitText()
    }

    func finishEditing() {
        isCompleting = true
    }

    private func resizeToFitText() {
        let content = textLayout.contentSize
        let lineHeight = textLayout.manager.defaultLineHeight(for: font ?? .systemFont(ofSize: 14))
        // Extra room keeps the insertion point visible at the end of long lines.
        let size = NSSize(width: max(24, content.width + 2), height: max(lineHeight, content.height))
        let screenSize = NSSize(width: size.width * pixelSize.width, height: size.height * pixelSize.height)
        frame = NSRect(x: anchor.x, y: anchor.y - screenSize.height, width: screenSize.width, height: screenSize.height)
        // Never substitute a smaller font: optical glyph metrics vary by size.
        setBoundsSize(size)
    }

    private func complete(_ action: () -> Void) {
        guard !isCompleting else { return }
        isCompleting = true
        action()
    }
}

final class StrokeWidthPickerView: NSView {
    private let strokeWidths: [CGFloat]
    private let selectionChanged: (Int) -> Void
    private let slider: NSSlider

    override var fittingSize: NSSize {
        NSSize(width: 58, height: 178)
    }

    init(strokeWidths: [CGFloat], selectedIndex: Int, selectionChanged: @escaping (Int) -> Void) {
        self.strokeWidths = strokeWidths
        self.selectionChanged = selectionChanged
        slider = NSSlider(
            value: Double(min(max(selectedIndex, 0), max(strokeWidths.count - 1, 0))),
            minValue: 0,
            maxValue: Double(max(strokeWidths.count - 1, 0)),
            target: nil,
            action: nil
        )

        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 58, height: 178)))

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.numberOfTickMarks = strokeWidths.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .leading
        slider.isVertical = true
        slider.frame = NSRect(x: 17, y: 16, width: 24, height: 146)
        addSubview(slider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderChanged() {
        let index = min(max(Int(round(slider.doubleValue)), 0), max(strokeWidths.count - 1, 0))
        if Int(slider.doubleValue) != index {
            slider.doubleValue = Double(index)
        }
        selectionChanged(index)
    }
}

final class ColorSwatchPickerView: NSView {
    private let colors: [NSColor]
    private let selectedColor: NSColor
    private let selectionChanged: (NSColor) -> Void
    private let swatchSize = NSSize(width: 28, height: 28)
    private let swatchGap: CGFloat = 10
    private let columnCount = 4

    override var fittingSize: NSSize {
        NSSize(width: 172, height: 96)
    }

    init(colors: [NSColor], selectedColor: NSColor, selectionChanged: @escaping (NSColor) -> Void) {
        self.colors = colors
        self.selectedColor = selectedColor
        self.selectionChanged = selectionChanged

        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 172, height: 96)))

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, color) in colors.enumerated() {
            let rect = swatchRect(for: index)
            color.setFill()
            let swatchPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            swatchPath.fill()

            NSColor.separatorColor.setStroke()
            swatchPath.lineWidth = 1
            swatchPath.stroke()

            if color.matchesVisually(selectedColor) {
                NSColor.controlAccentColor.setStroke()
                let selectedPath = NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -4), xRadius: 8, yRadius: 8)
                selectedPath.lineWidth = 3
                selectedPath.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let index = colors.indices.first(where: { swatchRect(for: $0).contains(localPoint) }) else { return }
        selectionChanged(colors[index])
    }

    private func swatchRect(for index: Int) -> NSRect {
        let row = index / columnCount
        let column = index % columnCount
        let totalWidth = CGFloat(columnCount) * swatchSize.width + CGFloat(columnCount - 1) * swatchGap
        let originX = (bounds.width - totalWidth) / 2
        let originY = bounds.height - 16 - swatchSize.height - CGFloat(row) * (swatchSize.height + swatchGap)

        return NSRect(
            x: originX + CGFloat(column) * (swatchSize.width + swatchGap),
            y: originY,
            width: swatchSize.width,
            height: swatchSize.height
        )
    }
}

private extension NSColor {
    func matchesVisually(_ otherColor: NSColor) -> Bool {
        guard
            let lhs = usingColorSpace(.deviceRGB),
            let rhs = otherColor.usingColorSpace(.deviceRGB)
        else {
            return false
        }

        return abs(lhs.redComponent - rhs.redComponent) < 0.01
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.01
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.01
            && abs(lhs.alphaComponent - rhs.alphaComponent) < 0.01
    }
}

final class FloatingToolbarBackgroundView: NSView {
    private var axis: RegionCaptureOverlayView.FloatingBarAxis = .horizontal
    private var buttonCount = 0
    private var buttonSize = NSSize(width: 30, height: 30)
    private var padding: CGFloat = 5
    private var gap: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 10
        layer?.shadowOffset = NSSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func configure(
        axis: RegionCaptureOverlayView.FloatingBarAxis,
        buttonCount: Int,
        buttonSize: NSSize,
        padding: CGFloat,
        gap: CGFloat
    ) {
        self.axis = axis
        self.buttonCount = buttonCount
        self.buttonSize = buttonSize
        self.padding = padding
        self.gap = gap
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.setFill()
        backgroundPath.fill()

        NSColor.separatorColor.setStroke()
        let strokeRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSBezierPath(roundedRect: strokeRect, xRadius: 10, yRadius: 10).stroke()

        guard buttonCount > 1 else { return }

        for index in 1..<buttonCount {
            let dividerPath = NSBezierPath()
            switch axis {
            case .horizontal:
                let x = padding + CGFloat(index) * buttonSize.width + CGFloat(index - 1) * gap + gap / 2
                dividerPath.move(to: NSPoint(x: x, y: padding + 4))
                dividerPath.line(to: NSPoint(x: x, y: bounds.height - padding - 4))
            case .vertical:
                let y = bounds.height - padding - CGFloat(index) * buttonSize.height - CGFloat(index - 1) * gap - gap / 2
                dividerPath.move(to: NSPoint(x: padding + 4, y: y))
                dividerPath.line(to: NSPoint(x: bounds.width - padding - 4, y: y))
            }
            dividerPath.lineWidth = 1
            dividerPath.stroke()
        }
    }
}

final class OverlayShortcutHelpView: NSView {
    var stringValue: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            needsLayout = true
            needsDisplay = true
        }
    }

    private let label = NSTextField(labelWithString: "")
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func sizeToFitHelp() {
        let labelSize = label.intrinsicContentSize
        frame.size = NSSize(
            width: ceil(labelSize.width) + Self.horizontalPadding * 2,
            height: ceil(labelSize.height) + Self.verticalPadding * 2
        )
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: Self.horizontalPadding, dy: Self.verticalPadding)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        NSColor.separatorColor.setStroke()
        let strokeRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSBezierPath(roundedRect: strokeRect, xRadius: 7, yRadius: 7).stroke()
    }
}

final class SolidActionButton: NSButton {
    var isActive = false {
        didSet {
            needsDisplay = true
        }
    }

    var swatchColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    private let symbolImage: NSImage?
    fileprivate let shortcutHelpText: String?
    fileprivate var hoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    init(symbolName: String?, accessibilityDescription: String, helpText: String? = nil) {
        shortcutHelpText = helpText
        if let symbolName {
            symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        } else {
            symbolImage = nil
        }
        super.init(frame: .zero)
        setAccessibilityLabel(accessibilityDescription)
        let helpText = helpText ?? accessibilityDescription
        setAccessibilityHelp(helpText)
        toolTip = helpText
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged?(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged?(false)
        super.mouseExited(with: event)
    }

    private func configure() {
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        image = symbolImage
        image?.isTemplate = true
        alphaValue = 1
        title = ""
    }

    override func draw(_ dirtyRect: NSRect) {
        let buttonRect = bounds.insetBy(dx: 1, dy: 1)
        if isActive || isHighlighted {
            let fill = isActive
                ? NSColor.selectedControlColor
                : NSColor.controlColor
            fill.setFill()
            NSBezierPath(roundedRect: buttonRect, xRadius: 7, yRadius: 7).fill()
        }

        if let swatchColor {
            drawSwatch(color: swatchColor)
            return
        }

        contentTintColor = isActive ? .controlAccentColor : .labelColor
        super.draw(dirtyRect)
    }

    private func drawSwatch(color: NSColor) {
        let swatchRect = bounds.insetBy(dx: 8, dy: 8)
        color.setFill()
        let swatchPath = NSBezierPath(ovalIn: swatchRect)
        swatchPath.fill()

        NSColor.separatorColor.setStroke()
        swatchPath.lineWidth = 1
        swatchPath.stroke()
    }
}
