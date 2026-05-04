import Foundation

final class GlobalShortcutManager {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        // Intentionally left as the next native integration point.
        // For MVP, capture is available from the menu bar while the editor/capture pipeline is built out.
    }
}
