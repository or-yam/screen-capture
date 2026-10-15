import AppKit

@MainActor
protocol CaptureOverlay: AnyObject {
    var onCopy: ((Data) -> Void)? { get set }
    var onSave: ((Data) -> Void)? { get set }
    var captureID: String { get }

    func start(
        captureID: String,
        snapshots: [DisplaySnapshot],
        defaultAnnotationColor: NSColor,
        defaultAnnotationStrokeWidth: CGFloat
    )
    func cancel()
    func showCaptureError(_ error: Error)
    func showSaveError(_ error: Error)
}
