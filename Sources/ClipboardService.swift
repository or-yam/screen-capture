import AppKit

final class ClipboardService {
    func copyPNG(_ data: Data) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }
}
