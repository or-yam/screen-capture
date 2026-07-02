import AppKit

@MainActor
final class RegionCaptureOverlayController {
    var onCopy: ((Data) -> Void)?
    var onSave: ((Data) -> Void)?

    private var windows: [RegionCaptureOverlayWindow] = []
    private var selectionState = RegionSelectionState()

    func start(
        snapshots: [DisplaySnapshot],
        defaultAnnotationColor: NSColor,
        defaultAnnotationStrokeWidth: CGFloat
    ) {
        NSLog("RegionCapture: starting overlay session.")
        cancel()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            NSLog("RegionCapture: no screens available; aborting overlay session.")
            return
        }

        selectionState = RegionSelectionState(snapshots: snapshots)
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
        NSLog("RegionCapture: cancelling overlay session; closing \(windows.count) windows.")
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        selectionState.reset()
    }

    func cancelFromUserAction() {
        NSLog("Region capture cancelled by user.")
        cancel()
    }

    func hideForCapture() {
        NSLog("RegionCapture: hiding overlay windows for ScreenCaptureKit capture.")
        for window in windows {
            window.orderOut(nil)
        }
    }

    func showAfterCapture() {
        NSLog("RegionCapture: restoring overlay windows after capture.")
        for window in windows {
            window.orderFrontRegardless()
        }
        focusPrimaryOverlay(reason: "capture restore")
    }

    func showCaptureError(_ error: Error) {
        NSLog("RegionCapture: capture failed: \(error.localizedDescription)")
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
        NSLog("RegionCapture: save failed: \(error.localizedDescription)")
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
                NSLog("RegionCapture: selected frozen region ready, \(image.width)x\(image.height), \(pngData.count) PNG bytes.")
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
            NSLog("RegionCapture: no overlay window to focus for \(reason).")
            return
        }

        window.makeKey()
        window.makeFirstResponder(window.overlayView)
        NSLog(
            "RegionCapture: focused primary overlay for \(reason); isKeyWindow=\(window.isKeyWindow), firstResponder=\(String(describing: window.firstResponder))."
        )
    }
}

@MainActor
final class RegionSelectionState {
    private(set) var snapshots: [DisplaySnapshot]
    private(set) var anchorPoint: NSPoint?
    private(set) var currentPoint: NSPoint?
    private(set) var canonicalSelectionRect: NSRect?
    private(set) var isSelectionAnchored = false
    private(set) var capturedPNG: Data?
    private(set) var capturedImage: CGImage?
    private(set) var annotations: [OverlayAnnotation] = []
    private(set) var draftAnnotation: OverlayAnnotation?

    private var annotationDragAnchorInImageSpace: CGPoint?

    init(snapshots: [DisplaySnapshot] = []) {
        self.snapshots = snapshots
    }

    var selectionRect: NSRect? {
        if let canonicalSelectionRect {
            return canonicalSelectionRect
        }

        guard let anchorPoint, let currentPoint else { return nil }
        return Self.normalizedRect(from: anchorPoint, to: currentPoint)
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
        annotations = []
        draftAnnotation = nil
        annotationDragAnchorInImageSpace = nil
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
        annotations = []
        draftAnnotation = nil
        annotationDragAnchorInImageSpace = nil
    }

    func setCapturedImageFromFrozenSnapshots(for rect: CGRect) throws {
        let image = try Self.cropFrozenSnapshots(snapshots, to: rect)
        let pngData = try PNGEncoder.encode(image)
        capturedImage = image
        capturedPNG = pngData
    }

    func beginAnnotation(tool: OverlayAnnotationTool, at point: CGPoint, color: NSColor, lineWidth: CGFloat, fontSize: CGFloat? = nil) {
        guard capturedImage != nil else { return }

        annotationDragAnchorInImageSpace = point
        switch tool {
        case .arrow:
            draftAnnotation = OverlayAnnotation(
                kind: .arrow,
                pointsInImageSpace: [point, point],
                color: color,
                lineWidth: lineWidth
            )
        case .rectangle:
            draftAnnotation = OverlayAnnotation(
                kind: .rectangle,
                rectInImageSpace: CGRect(origin: point, size: .zero),
                color: color,
                lineWidth: lineWidth
            )
        case .draw:
            draftAnnotation = OverlayAnnotation(
                kind: .draw,
                pointsInImageSpace: [point],
                color: color,
                lineWidth: lineWidth
            )
        case .highlight:
            draftAnnotation = OverlayAnnotation(
                kind: .highlight,
                pointsInImageSpace: [point],
                color: color.withAlphaComponent(0.35),
                lineWidth: lineWidth * 3
            )
        case .text:
            draftAnnotation = OverlayAnnotation(
                kind: .text,
                text: "",
                textPositionInImageSpace: point,
                color: color,
                fontSize: fontSize ?? Self.defaultTextFontSize
            )
        }
    }

    func updateAnnotation(to point: CGPoint) {
        guard let annotationDragAnchorInImageSpace, let draftAnnotation else { return }

        switch draftAnnotation.kind {
        case .arrow:
            self.draftAnnotation = OverlayAnnotation(
                id: draftAnnotation.id,
                kind: .arrow,
                pointsInImageSpace: [annotationDragAnchorInImageSpace, point],
                color: draftAnnotation.color,
                lineWidth: draftAnnotation.lineWidth
            )
        case .rectangle:
            self.draftAnnotation = OverlayAnnotation(
                id: draftAnnotation.id,
                kind: .rectangle,
                rectInImageSpace: Self.normalizedRect(from: annotationDragAnchorInImageSpace, to: point),
                color: draftAnnotation.color,
                lineWidth: draftAnnotation.lineWidth
            )
        case .draw, .highlight:
            var points = draftAnnotation.pointsInImageSpace
            if points.last.map({ hypot($0.x - point.x, $0.y - point.y) >= 1 }) ?? true {
                points.append(point)
            }
            self.draftAnnotation = OverlayAnnotation(
                id: draftAnnotation.id,
                kind: draftAnnotation.kind,
                pointsInImageSpace: points,
                color: draftAnnotation.color,
                lineWidth: draftAnnotation.lineWidth
            )
        case .text:
            return
        }
    }

    func commitAnnotation() {
        defer {
            annotationDragAnchorInImageSpace = nil
            draftAnnotation = nil
        }

        guard let draftAnnotation else { return }
        guard draftAnnotation.kind != .text else { return }
        if let rect = draftAnnotation.rectInImageSpace, rect.width < 1 || rect.height < 1 {
            return
        }
        if draftAnnotation.kind == .arrow,
           let start = draftAnnotation.pointsInImageSpace.first,
           let end = draftAnnotation.pointsInImageSpace.last,
           hypot(start.x - end.x, start.y - end.y) < 1 {
            return
        }
        if draftAnnotation.pointsInImageSpace.count == 1 {
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
            annotationDragAnchorInImageSpace = nil
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
            annotationDragAnchorInImageSpace = nil
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
        annotations = []
        draftAnnotation = nil
        annotationDragAnchorInImageSpace = nil
    }

    private static func cropFrozenSnapshots(_ snapshots: [DisplaySnapshot], to rect: CGRect) throws -> CGImage {
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

        let outputScale = intersectingSnapshots
            .map { CGFloat($0.snapshot.image.width) / $0.snapshot.display.frameInAppKitScreenSpace.width }
            .max() ?? 1
        let outputWidth = max(1, Int(ceil(selectionRect.width * outputScale)))
        let outputHeight = max(1, Int(ceil(selectionRect.height * outputScale)))
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
                x: (intersection.minX - selectionRect.minX) * outputScale,
                y: (intersection.minY - selectionRect.minY) * outputScale,
                width: intersection.width * outputScale,
                height: intersection.height * outputScale
            )
            context.draw(croppedImage, in: destinationRect)
        }

        guard let outputImage = context.makeImage() else {
            throw RenderError.missingCGImage
        }

        return outputImage
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
    var rectInImageSpace: CGRect?
    var pointsInImageSpace: [CGPoint]
    var text: String
    var textPositionInImageSpace: CGPoint?
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat

    init(
        id: UUID = UUID(),
        kind: OverlayAnnotationTool,
        rectInImageSpace: CGRect? = nil,
        pointsInImageSpace: [CGPoint] = [],
        text: String = "",
        textPositionInImageSpace: CGPoint? = nil,
        color: NSColor = .systemRed,
        lineWidth: CGFloat = 4,
        fontSize: CGFloat = 28
    ) {
        self.id = id
        self.kind = kind
        self.rectInImageSpace = rectInImageSpace?.standardized
        self.pointsInImageSpace = pointsInImageSpace
        self.text = text
        self.textPositionInImageSpace = textPositionInImageSpace
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
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
    private var selectedColor: NSColor
    private var selectedStrokeIndex: Int
    private var colorPopover: NSPopover?
    private var strokePopover: NSPopover?
    private var activeTextField: AnnotationTextField?
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
        NSLog("RegionCapture: overlay view moved to window; requested first responder.")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            colorPopover?.close()
            strokePopover?.close()
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

        let localSelectionRect = convertScreenRectToLocal(selectionRect).intersection(bounds)
        if !localSelectionRect.isEmpty {
            addCursorRect(localSelectionRect, cursor: .arrow)
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
        if let activeTextField {
            let localPoint = convert(event.locationInWindow, from: nil)
            if !activeTextField.frame.contains(localPoint) {
                commitActiveTextField()
            }
        }
        if let activeAnnotationTool, let imagePoint = imagePointForAnnotationEvent(event) {
            if activeAnnotationTool == .text {
                beginTextAnnotation(event: event)
                return
            }
            selectionState.beginAnnotation(
                tool: activeAnnotationTool,
                at: imagePoint,
                color: selectedColor,
                lineWidth: selectedStrokeWidth
            )
            refresh()
            return
        }
        if selectionState.capturedImage != nil {
            return
        }

        if selectionState.isSelectionAnchored, selectionContains(point) {
            return
        }

        NSLog("RegionCapture: selection started at \(point).")
        selectionState.beginSelection(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        if activeAnnotationTool != nil, activeAnnotationTool != .text, let imagePoint = imagePointForAnnotationEvent(event) {
            selectionState.updateAnnotation(to: imagePoint)
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
        if activeAnnotationTool != nil, activeAnnotationTool != .text, let imagePoint = imagePointForAnnotationEvent(event) {
            selectionState.updateAnnotation(to: imagePoint)
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
            NSLog("RegionCapture: selection completed: \(selectionRect).")
            selectionCompleted(selectionRect)
        } else {
            NSLog("RegionCapture: ignored empty selection.")
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if activeTextField != nil {
                cancelActiveTextField()
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

        let localSelectionRect = convertScreenRectToLocal(selectionRect).intersection(bounds)
        guard !localSelectionRect.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: localSelectionRect).addClip()
        if let capturedImage = selectionState.capturedImage {
            NSImage(cgImage: capturedImage, size: localSelectionRect.size).draw(in: localSelectionRect)
        } else if drewFrozenBackground {
            drawFrozenSnapshots(in: localSelectionRect)
        } else {
            NSColor.clear.setFill()
            bounds.fill(using: .copy)
        }
        NSGraphicsContext.restoreGraphicsState()

        drawAnnotations(in: localSelectionRect)

        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: localSelectionRect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        NSColor.systemBlue.setStroke()
        let accentPath = NSBezierPath(rect: localSelectionRect.insetBy(dx: 1, dy: 1))
        accentPath.lineWidth = 1
        accentPath.stroke()
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
            colorPopover?.close()
            strokePopover?.close()
            hideFloatingControls()
            return
        }

        let localSelectionRect = convertScreenRectToLocal(selectionRect).intersection(bounds)
        guard !localSelectionRect.isEmpty else {
            activeAnnotationTool = nil
            colorPopover?.close()
            strokePopover?.close()
            hideFloatingControls()
            return
        }

        drawButton.isActive = activeAnnotationTool == .draw
        highlightButton.isActive = activeAnnotationTool == .highlight
        arrowButton.isActive = activeAnnotationTool == .arrow
        textButton.isActive = activeAnnotationTool == .text
        rectangleButton.isActive = activeAnnotationTool == .rectangle
        colorButton.swatchColor = selectedColor

        let annotationButtons = [drawButton, highlightButton, arrowButton, textButton, rectangleButton, colorButton, strokeButton, undoButton]
        let actionButtons = [copyButton, saveButton, closeButton]
        let toolbarSize = floatingBarSize(buttonCount: annotationButtons.count, axis: .vertical)
        let actionBarSize = floatingBarSize(buttonCount: actionButtons.count, axis: .horizontal)
        annotationToolbarBackground.frame = annotationToolbarFrame(for: toolbarSize, beside: localSelectionRect)
        actionBarBackground.frame = actionBarFrame(for: actionBarSize, beside: localSelectionRect)
        layout(buttons: annotationButtons, in: annotationToolbarBackground.frame, axis: .vertical)
        layout(buttons: actionButtons, in: actionBarBackground.frame, axis: .horizontal)
        annotationToolbarBackground.isHidden = false
        actionBarBackground.isHidden = false
        annotationButtons.forEach { $0.isHidden = false }
        actionButtons.forEach { $0.isHidden = false }
    }

    private enum FloatingBarAxis {
        case horizontal
        case vertical
    }

    private func hideFloatingControls() {
        annotationToolbarBackground.isHidden = true
        actionBarBackground.isHidden = true
        hideShortcutHelp()
        [arrowButton, textButton, rectangleButton, drawButton, highlightButton, colorButton, strokeButton, undoButton, copyButton, saveButton, closeButton].forEach {
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
        let outsideX = selectionRect.maxX + margin
        let insideX = selectionRect.maxX - toolbarSize.width - margin
        let preferredX = outsideX + toolbarSize.width <= bounds.maxX - margin ? outsideX : insideX
        let preferredY = selectionRect.maxY - toolbarSize.height

        return NSRect(
            x: min(max(preferredX, margin), bounds.maxX - toolbarSize.width - margin),
            y: min(max(preferredY, margin), bounds.maxY - toolbarSize.height - margin),
            width: toolbarSize.width,
            height: toolbarSize.height
        )
    }

    private func actionBarFrame(for actionBarSize: NSSize, beside selectionRect: NSRect) -> NSRect {
        let margin: CGFloat = 8
        let preferredX = selectionRect.maxX - actionBarSize.width
        let outsideY = selectionRect.minY - actionBarSize.height - margin
        let insideY = selectionRect.minY + margin
        let preferredY = outsideY >= margin ? outsideY : insideY

        return NSRect(
            x: min(max(preferredX, margin), bounds.maxX - actionBarSize.width - margin),
            y: min(max(preferredY, margin), bounds.maxY - actionBarSize.height - margin),
            width: actionBarSize.width,
            height: actionBarSize.height
        )
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
                NSLog("RegionCapture: selected annotation color \(selectedColor).")
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
                NSLog("RegionCapture: selected annotation size \(selectedStrokeWidth).")
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
        activeAnnotationTool = activeAnnotationTool == tool ? nil : tool
        NSLog("RegionCapture: annotation tool \(String(describing: activeAnnotationTool)) selected.")
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
            NSLog("RegionCapture: copy requested before captured PNG was ready.")
            NSSound.beep()
            return
        }

        NSLog("RegionCapture: copy requested for captured PNG, \(capturedPNG.count) bytes.")
        copy(capturedPNG)
    }

    func handleCommandKeyEquivalent(_ event: NSEvent, source: String) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return false
        }

        if event.keyCode == Self.cKeyCode || event.charactersIgnoringModifiers?.lowercased() == "c" {
            NSLog("RegionCapture: Cmd+C handled by \(source).")
            copyCapturedPNG()
            return true
        }

        if event.keyCode == Self.sKeyCode || event.charactersIgnoringModifiers?.lowercased() == "s" {
            NSLog("RegionCapture: Cmd+S handled by \(source).")
            saveCapturedPNG()
            return true
        }

        if event.keyCode == Self.zKeyCode || event.charactersIgnoringModifiers?.lowercased() == "z" {
            NSLog("RegionCapture: Cmd+Z handled by \(source).")
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
            NSLog("RegionCapture: save requested before captured PNG was ready.")
            NSSound.beep()
            return
        }

        NSLog("RegionCapture: save requested for rendered PNG, \(capturedPNG.count) bytes.")
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
            let capturedImage = selectionState.capturedImage,
            let selectionRect = selectionState.selectionRect
        else {
            return
        }

        let localSelectionRect = convertScreenRectToLocal(selectionRect).intersection(bounds)
        guard !localSelectionRect.isEmpty else { return }

        let field = AnnotationTextField(
            commit: { [weak self] in self?.commitActiveTextField() },
            cancel: { [weak self] in self?.cancelActiveTextField() }
        )
        let localPoint = convert(event.locationInWindow, from: nil)
        let fontSize = previewTextFontSize(for: capturedImage, in: localSelectionRect)
        let fieldWidth = min(max(localSelectionRect.width - (localPoint.x - localSelectionRect.minX), 120), min(280, localSelectionRect.width))
        let fieldHeight = max(fontSize + 10, 32)
        let fieldX = min(localPoint.x, localSelectionRect.maxX - fieldWidth)
        let adjustedImagePoint = CGPoint(
            x: (fieldX - localSelectionRect.minX) / localSelectionRect.width * CGFloat(capturedImage.width),
            y: (localSelectionRect.maxY - localPoint.y) / localSelectionRect.height * CGFloat(capturedImage.height)
        )
        selectionState.beginAnnotation(
            tool: .text,
            at: adjustedImagePoint,
            color: selectedColor,
            lineWidth: selectedStrokeWidth,
            fontSize: selectedTextFontSize
        )
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = selectedColor
        field.frame = NSRect(
            x: fieldX,
            y: max(localSelectionRect.minY, localPoint.y - fieldHeight),
            width: fieldWidth,
            height: fieldHeight
        )

        activeTextField = field
        addSubview(field)
        window?.makeFirstResponder(field)
        refresh()
    }

    private func commitActiveTextField() {
        guard let activeTextField else { return }
        selectionState.updateDraftText(activeTextField.stringValue)
        selectionState.commitDraftText()
        activeTextField.removeFromSuperview()
        self.activeTextField = nil
        window?.makeFirstResponder(self)
        refresh()
    }

    private func cancelActiveTextField() {
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        selectionState.undoLastAnnotation()
        window?.makeFirstResponder(self)
        refresh()
    }

    private func renderedPNGForCopy() -> Data? {
        guard let capturedPNG = selectionState.capturedPNG else { return nil }
        guard let capturedImage = selectionState.capturedImage else { return capturedPNG }

        do {
            return try Renderer().renderPNG(baseImage: capturedImage, annotations: selectionState.annotations)
        } catch {
            NSLog("RegionCapture: annotated PNG render failed: \(error.localizedDescription)")
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

    private func imagePointForAnnotationEvent(_ event: NSEvent) -> CGPoint? {
        guard
            let capturedImage = selectionState.capturedImage,
            let selectionRect = selectionState.selectionRect
        else {
            return nil
        }

        let localSelectionRect = convertScreenRectToLocal(selectionRect).intersection(bounds)
        guard !localSelectionRect.isEmpty else { return nil }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard localSelectionRect.contains(localPoint) else { return nil }

        let xRatio = (localPoint.x - localSelectionRect.minX) / localSelectionRect.width
        let yRatio = (localSelectionRect.maxY - localPoint.y) / localSelectionRect.height
        return CGPoint(
            x: min(max(xRatio, 0), 1) * CGFloat(capturedImage.width),
            y: min(max(yRatio, 0), 1) * CGFloat(capturedImage.height)
        )
    }

    private func drawAnnotations(in localSelectionRect: NSRect) {
        guard let capturedImage = selectionState.capturedImage else { return }

        for annotation in selectionState.annotations + [selectionState.draftAnnotation].compactMap({ $0 }) {
            if annotation.kind == .text {
                drawTextAnnotation(annotation, in: localSelectionRect, image: capturedImage)
                continue
            }

            let path = previewPath(for: annotation, in: localSelectionRect, image: capturedImage)
            annotation.color.setStroke()
            path.lineWidth = previewLineWidth(for: annotation, in: localSelectionRect, image: capturedImage)
            path.lineCapStyle = annotation.kind == .rectangle ? .butt : .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    private func previewPath(for annotation: OverlayAnnotation, in localSelectionRect: NSRect, image: CGImage) -> NSBezierPath {
        if let rect = annotation.rectInImageSpace {
            return NSBezierPath(rect: previewRect(for: rect, in: localSelectionRect, image: image))
        }

        let path = NSBezierPath()
        let points = annotation.pointsInImageSpace.map { previewPoint(for: $0, in: localSelectionRect, image: image) }
        guard let firstPoint = points.first else { return path }
        if annotation.kind == .arrow, let endPoint = points.last {
            appendArrow(from: firstPoint, to: endPoint, lineWidth: previewLineWidth(for: annotation, in: localSelectionRect, image: image), to: path)
            return path
        }

        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        return path
    }

    private func drawTextAnnotation(_ annotation: OverlayAnnotation, in localSelectionRect: NSRect, image: CGImage) {
        guard let position = annotation.textPositionInImageSpace, !annotation.text.isEmpty else { return }

        let point = previewPoint(for: position, in: localSelectionRect, image: image)
        let fontSize = previewTextFontSize(for: annotation, in: localSelectionRect, image: image)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: annotation.color
        ]
        annotation.text.draw(at: NSPoint(x: point.x, y: point.y - fontSize), withAttributes: attributes)
    }

    private func appendArrow(from startPoint: NSPoint, to endPoint: NSPoint, lineWidth: CGFloat, to path: NSBezierPath) {
        path.move(to: startPoint)
        path.line(to: endPoint)

        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        guard hypot(dx, dy) >= 1 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(lineWidth * 4, 10)
        let headAngle = CGFloat.pi / 7
        let firstHeadPoint = NSPoint(
            x: endPoint.x - headLength * cos(angle - headAngle),
            y: endPoint.y - headLength * sin(angle - headAngle)
        )
        let secondHeadPoint = NSPoint(
            x: endPoint.x - headLength * cos(angle + headAngle),
            y: endPoint.y - headLength * sin(angle + headAngle)
        )

        path.move(to: endPoint)
        path.line(to: firstHeadPoint)
        path.move(to: endPoint)
        path.line(to: secondHeadPoint)
    }

    private func previewRect(for imageRect: CGRect, in localSelectionRect: NSRect, image: CGImage) -> NSRect {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        return NSRect(
            x: localSelectionRect.minX + imageRect.minX / imageWidth * localSelectionRect.width,
            y: localSelectionRect.maxY - imageRect.maxY / imageHeight * localSelectionRect.height,
            width: imageRect.width / imageWidth * localSelectionRect.width,
            height: imageRect.height / imageHeight * localSelectionRect.height
        )
    }

    private func previewPoint(for imagePoint: CGPoint, in localSelectionRect: NSRect, image: CGImage) -> NSPoint {
        NSPoint(
            x: localSelectionRect.minX + imagePoint.x / CGFloat(image.width) * localSelectionRect.width,
            y: localSelectionRect.maxY - imagePoint.y / CGFloat(image.height) * localSelectionRect.height
        )
    }

    private func previewLineWidth(for annotation: OverlayAnnotation, in localSelectionRect: NSRect, image: CGImage) -> CGFloat {
        max(1, annotation.lineWidth * localSelectionRect.width / CGFloat(image.width))
    }

    private func previewTextFontSize(for annotation: OverlayAnnotation, in localSelectionRect: NSRect, image: CGImage) -> CGFloat {
        previewTextFontSize(forImageFontSize: annotation.fontSize, image: image, in: localSelectionRect)
    }

    private func previewTextFontSize(for image: CGImage, in localSelectionRect: NSRect) -> CGFloat {
        previewTextFontSize(forImageFontSize: selectedTextFontSize, image: image, in: localSelectionRect)
    }

    private func previewTextFontSize(forImageFontSize fontSize: CGFloat, image: CGImage, in localSelectionRect: NSRect) -> CGFloat {
        max(12, fontSize * localSelectionRect.width / CGFloat(image.width))
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

final class AnnotationTextField: NSTextField, NSTextFieldDelegate {
    private let commit: () -> Void
    private let cancel: () -> Void
    private var isCompleting = false

    init(commit: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.commit = commit
        self.cancel = cancel
        super.init(frame: .zero)

        delegate = self
        isBordered = true
        isBezeled = true
        drawsBackground = true
        backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.9)
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            complete(commit)
            return
        }

        if event.keyCode == 53 {
            complete(cancel)
            return
        }

        super.keyDown(with: event)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        complete(commit)
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
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 10
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 10
        layer?.shadowOffset = NSSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        let background = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
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
                ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                : NSColor.controlColor.withAlphaComponent(0.35)
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
