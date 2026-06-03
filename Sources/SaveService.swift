import Foundation

@MainActor
final class SaveService {
    private let preferences: PreferencesStore

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    func savePNG(_ data: Data) throws -> URL {
        NSLog("SaveService: saving PNG to folder \(preferences.saveFolderURL.path), \(data.count) bytes.")
        try FileManager.default.createDirectory(
            at: preferences.saveFolderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let outputURL = preferences.saveFolderURL.appendingPathComponent(filename())
        try data.write(to: outputURL, options: .atomic)
        NSLog("SaveService: wrote PNG to \(outputURL.path).")
        return outputURL
    }

    private func filename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }
}
