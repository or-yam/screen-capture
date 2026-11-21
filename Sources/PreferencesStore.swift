import AppKit

@MainActor
final class PreferencesStore: ObservableObject {
    static let annotationStrokeWidths: [CGFloat] = [2, 4, 8, 12]

    @Published var saveFolderURL: URL {
        didSet { defaults.set(saveFolderURL.path, forKey: Keys.saveFolderPath) }
    }

    @Published var defaultAnnotationColor: NSColor {
        didSet {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: defaultAnnotationColor,
                requiringSecureCoding: true
            ) else { return }

            defaults.set(data, forKey: Keys.defaultAnnotationColor)
        }
    }

    @Published var defaultAnnotationStrokeWidth: CGFloat {
        didSet { defaults.set(Double(defaultAnnotationStrokeWidth), forKey: Keys.defaultAnnotationStrokeWidth) }
    }

    @Published var showsSaveConfirmation: Bool {
        didSet { defaults.set(showsSaveConfirmation, forKey: Keys.showsSaveConfirmation) }
    }

    @Published var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon) }
    }

    var hasShownInitialPreferences: Bool {
        get { defaults.bool(forKey: Keys.hasShownInitialPreferences) }
        set { defaults.set(newValue, forKey: Keys.hasShownInitialPreferences) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedPath = defaults.string(forKey: Keys.saveFolderPath)
        saveFolderURL = savedPath.map(URL.init(fileURLWithPath:)) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
            .appendingPathComponent("Screenshots")

        defaultAnnotationColor = defaults.data(forKey: Keys.defaultAnnotationColor)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0) }
            ?? .systemRed

        let savedStrokeWidth = defaults.object(forKey: Keys.defaultAnnotationStrokeWidth) as? Double
        defaultAnnotationStrokeWidth = savedStrokeWidth.map { CGFloat($0) } ?? 4

        let savedShowsSaveConfirmation = defaults.object(forKey: Keys.showsSaveConfirmation) as? Bool
        showsSaveConfirmation = savedShowsSaveConfirmation ?? true

        let savedShowsMenuBarIcon = defaults.object(forKey: Keys.showsMenuBarIcon) as? Bool
        showsMenuBarIcon = savedShowsMenuBarIcon ?? true
    }
}

private enum Keys {
    static let hasShownInitialPreferences = "hasShownInitialPreferences"
    static let saveFolderPath = "saveFolderPath"
    static let defaultAnnotationColor = "defaultAnnotationColor"
    static let defaultAnnotationStrokeWidth = "defaultAnnotationStrokeWidth"
    static let showsSaveConfirmation = "showsSaveConfirmation"
    static let showsMenuBarIcon = "showsMenuBarIcon"
}
