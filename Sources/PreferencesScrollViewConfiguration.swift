import AppKit
import SwiftUI

/// Configures only the settings form's enclosing scroll view.
struct PreferencesScrollViewConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> PreferencesScrollViewConfigurationView {
        PreferencesScrollViewConfigurationView()
    }

    func updateNSView(_ nsView: PreferencesScrollViewConfigurationView, context: Context) {
        nsView.configureScrollView()
    }
}
