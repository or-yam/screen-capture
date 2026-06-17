import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            ColorPicker(
                "Default annotation color",
                selection: Binding(
                    get: { Color(nsColor: preferences.defaultAnnotationColor) },
                    set: { preferences.defaultAnnotationColor = NSColor($0) }
                ),
                supportsOpacity: false
            )

            Picker("Default stroke size", selection: $preferences.defaultAnnotationStrokeWidth) {
                ForEach(PreferencesStore.annotationStrokeWidths, id: \.self) { width in
                    Text("\(Int(width)) px").tag(width)
                }
            }
            .pickerStyle(.segmented)

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

            Text("Shortcut: Cmd-Shift-A")
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
