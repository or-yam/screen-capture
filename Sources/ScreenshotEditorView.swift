import AppKit
import SwiftUI

struct ScreenshotEditorView: View {
    @StateObject var model: AnnotationModel

    let renderer: Renderer
    let clipboardService: ClipboardService
    let saveService: SaveService
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Image(nsImage: model.baseImage)
                .resizable()
                .scaledToFit()
                .overlay(alignment: .topLeading) {
                    AnnotationOverlay(annotations: model.annotations)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 480)
        .onExitCommand(perform: close)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Arrow") { model.selectedTool = .arrow }
            Button("Circle") { model.selectedTool = .ellipse }
            Button("Rect") { model.selectedTool = .rectangle }
            Button("Text") { model.addSampleText() }
            Button("Pen") { model.selectedTool = .pen }
            Button("Blur") { model.selectedTool = .blur }
            ColorPicker("Color", selection: $model.selectedColor)
            Button("Undo") { model.undo() }
            Spacer()
            Button("Copy") { copy() }
                .keyboardShortcut("c", modifiers: .command)
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Done") { saveAndCopy() }
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(10)
    }

    private func renderedPNG() throws -> Data {
        try renderer.renderPNG(baseImage: model.baseImage, annotations: model.annotations)
    }

    private func copy() {
        do {
            try clipboardService.copyPNG(renderedPNG())
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func save() {
        do {
            _ = try saveService.savePNG(renderedPNG())
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func saveAndCopy() {
        save()
        copy()
        close()
    }
}

struct AnnotationOverlay: View {
    let annotations: [Annotation]

    var body: some View {
        Canvas { context, _ in
            for annotation in annotations {
                annotation.draw(in: &context)
            }
        }
    }
}
