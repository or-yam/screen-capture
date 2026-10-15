import AppKit
import Combine
import CoreGraphics
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: PreferencesStore
    @StateObject private var screenRecordingStatus = ScreenRecordingPermissionStatus()

    private static let annotationSwatches: [AnnotationSwatch] = [
        AnnotationSwatch(name: "Red", color: .systemRed),
        AnnotationSwatch(name: "Orange", color: .systemOrange),
        AnnotationSwatch(name: "Yellow", color: .systemYellow),
        AnnotationSwatch(name: "Green", color: .systemGreen),
        AnnotationSwatch(name: "Blue", color: .systemBlue),
        AnnotationSwatch(name: "Purple", color: .systemPurple),
        AnnotationSwatch(name: "White", color: .white),
        AnnotationSwatch(name: "Black", color: .black)
    ]

    var body: some View {
        Form {
            Section("Output") {
                LabeledContent("Save folder") {
                    HStack(spacing: 8) {
                        Text(preferences.saveFolderURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button("Change...", action: chooseSaveFolder)

                        Button(action: revealSaveFolder) {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!saveFolderValidation.isRevealable)
                        .help("Reveal in Finder")
                    }
                }

                folderStatusRow

                LabeledContent("Save confirmation") {
                    Toggle("Show after successful save", isOn: $preferences.showsSaveConfirmation)
                }
            }

            Section("Annotations") {
                LabeledContent("Default color") {
                    HStack(spacing: 8) {
                        ForEach(Self.annotationSwatches) { swatch in
                            swatchButton(for: swatch)
                        }
                    }
                }

                LabeledContent("Stroke width") {
                    HStack(spacing: 10) {
                        Picker("Stroke width", selection: $preferences.defaultAnnotationStrokeWidth) {
                            ForEach(PreferencesStore.annotationStrokeWidths, id: \.self) { width in
                                Text("\(Int(width))").tag(width)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)

                        Text("\(Int(preferences.defaultAnnotationStrokeWidth)) px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
            }

            Section("Capture") {
                LabeledContent("Shortcut") {
                    HStack(spacing: 4) {
                        KeyCap("Cmd")
                        KeyCap("Shift")
                        KeyCap("S")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Command Shift S")
                }

                LabeledContent("Menu bar icon") {
                    Toggle("Show app icon in menu bar", isOn: $preferences.showsMenuBarIcon)
                }

                LabeledContent("Screen Recording") {
                    HStack(spacing: 8) {
                        Label(
                            screenRecordingStatus.isAllowed ? "Allowed" : "Not allowed",
                            systemImage: screenRecordingStatus.isAllowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(screenRecordingStatusStyle)

                        Button("Open System Settings", action: openScreenRecordingSettings)
                    }
                }

                if !screenRecordingStatus.isAllowed {
                    Label(
                        "Captures fail until Screen Recording is allowed.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 520)
        .onAppear(perform: refreshScreenRecordingStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshScreenRecordingStatus()
        }
    }

    private var saveFolderValidation: SaveFolderValidation {
        SaveFolderValidation(url: preferences.saveFolderURL)
    }

    private var screenRecordingStatusStyle: AnyShapeStyle {
        screenRecordingStatus.isAllowed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange)
    }

    private var folderStatusRow: some View {
        Label(saveFolderValidation.message, systemImage: saveFolderValidation.systemImage)
            .foregroundStyle(saveFolderValidation.style)
            .font(.callout)
    }

    private func swatchButton(for swatch: AnnotationSwatch) -> some View {
        let isSelected = swatch.color.matchesVisually(preferences.defaultAnnotationColor)

        return Button {
            preferences.defaultAnnotationColor = swatch.color
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: swatch.color))
                .frame(width: 24, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Color(nsColor: swatch.color.readableTitleColor))
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(swatch.name) annotation color")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(swatch.name)
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveFolderURL = url
        }
    }

    private func revealSaveFolder() {
        guard saveFolderValidation.isRevealable else { return }
        NSWorkspace.shared.activateFileViewerSelecting([preferences.saveFolderURL])
    }

    private func refreshScreenRecordingStatus() {
        screenRecordingStatus.isAllowed = CGPreflightScreenCaptureAccess()
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class ScreenRecordingPermissionStatus: ObservableObject {
    @Published var isAllowed = false
}

private struct AnnotationSwatch: Identifiable {
    let name: String
    let color: NSColor

    var id: String { name }
}

private struct KeyCap: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct SaveFolderValidation {
    let message: String
    let systemImage: String
    let style: AnyShapeStyle
    let isRevealable: Bool

    init(url: URL) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if !exists {
            message = "Folder does not exist yet. Saving will try to create it."
            systemImage = "folder.badge.plus"
            style = AnyShapeStyle(.secondary)
            isRevealable = false
            return
        }

        guard isDirectory.boolValue else {
            message = "Selected path is not a folder. Choose another location."
            systemImage = "exclamationmark.triangle.fill"
            style = AnyShapeStyle(.orange)
            isRevealable = false
            return
        }

        let isReadable = FileManager.default.isReadableFile(atPath: url.path)
        let isWritable = FileManager.default.isWritableFile(atPath: url.path)
        guard isReadable && isWritable else {
            message = "Folder is not accessible for saving. Choose another location."
            systemImage = "exclamationmark.triangle.fill"
            style = AnyShapeStyle(.orange)
            isRevealable = true
            return
        }

        message = "Folder is ready."
        systemImage = "checkmark.circle.fill"
        style = AnyShapeStyle(.secondary)
        isRevealable = true
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

    var readableTitleColor: NSColor {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.299 * rgbColor.redComponent + 0.587 * rgbColor.greenComponent + 0.114 * rgbColor.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}
