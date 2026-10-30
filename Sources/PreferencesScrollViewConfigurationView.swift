import AppKit

final class PreferencesScrollViewConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollView()
    }

    func configureScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        // Overlay scrollers stay at the window edge without consuming a content gutter.
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
    }
}
