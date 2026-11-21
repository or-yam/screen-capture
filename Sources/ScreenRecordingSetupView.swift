import SwiftUI

struct ScreenRecordingSetupView: View {
    let setup: ScreenRecordingSetup
    let startCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                setup.isAllowed ? "Screen Recording allowed" : "Screen Recording access needed",
                systemImage: setup.isAllowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(setup.isAllowed ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))

            if setup.isAllowed {
                Text("Ready to take a screenshot. Press Command–Shift–S, then drag to select a region.")
                Text("Use Command-C to copy or Command-S to save your screenshot.")
                    .foregroundStyle(.secondary)
                Button("Take a Screenshot", systemImage: "camera.viewfinder", action: startCapture)
                    .buttonStyle(.borderedProminent)
            } else {
                Text("ScreenCaptureAll needs Screen Recording access to capture the area you select.")

                instruction(1, "Open System Settings → Privacy & Security → Screen & System Audio Recording (called Screen Recording on some macOS versions).")
                Button("Open System Settings", systemImage: "gearshape", action: setup.openSystemSettings)
                    .buttonStyle(.borderedProminent)

                instruction(2, "Enable \(setup.appName). If it is missing, click + to add this exact app:")
                Text(setup.appURL.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        appPathButtons
                    }
                    VStack(alignment: .leading) {
                        appPathButtons
                    }
                }
                Text("In the file picker, press Command–Shift–G and paste the copied app path, then choose Open. This also works for hidden folders such as .build.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                instruction(3, "Return here to check access. Quit and reopen this app only if macOS asks you to.")
            }

            Button("Check Access Again", systemImage: "arrow.clockwise", action: setup.refresh)
            if let feedback = setup.actionFeedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: setup.refresh)
    }

    @ViewBuilder
    private var appPathButtons: some View {
        Button("Show App in Finder", systemImage: "folder", action: setup.showAppInFinder)
        Button("Copy App Path", systemImage: "doc.on.doc", action: setup.copyAppPath)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        Text("\(number). \(text)")
            .fixedSize(horizontal: false, vertical: true)
    }
}
