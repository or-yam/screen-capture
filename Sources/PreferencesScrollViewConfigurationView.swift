import AppKit

final class PreferencesScrollViewConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollView()
    }

    func configureScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        // Keep the system's scrollbar visibility preference; only reduce its size.
        scrollView.verticalScroller?.controlSize = .small
    }
}
