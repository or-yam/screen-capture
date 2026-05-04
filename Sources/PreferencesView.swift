import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Picker("Default action", selection: $preferences.defaultAction) {
                ForEach(DefaultAction.allCases) { action in
                    Text(action.rawValue).tag(action)
                }
            }

            Toggle("Copy after save", isOn: $preferences.copyAfterSave)
            Toggle("Show floating toolbar", isOn: $preferences.showFloatingToolbar)

            HStack {
                Text("Save folder")
                Spacer()
                Text(preferences.saveFolderURL.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose") {
                    chooseSaveFolder()
                }
            }

            Text("Shortcut: Option-Shift-4")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520)
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveFolderURL = url
        }
    }
}
