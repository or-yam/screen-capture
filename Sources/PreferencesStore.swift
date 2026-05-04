import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var defaultAction: DefaultAction {
        didSet { defaults.set(defaultAction.rawValue, forKey: Keys.defaultAction) }
    }

    @Published var copyAfterSave: Bool {
        didSet { defaults.set(copyAfterSave, forKey: Keys.copyAfterSave) }
    }

    @Published var showFloatingToolbar: Bool {
        didSet { defaults.set(showFloatingToolbar, forKey: Keys.showFloatingToolbar) }
    }

    @Published var saveFolderURL: URL {
        didSet { defaults.set(saveFolderURL.path, forKey: Keys.saveFolderPath) }
    }

    private let defaults = UserDefaults.standard

    init() {
        defaultAction = DefaultAction(rawValue: defaults.string(forKey: Keys.defaultAction) ?? "") ?? .copy
        copyAfterSave = defaults.object(forKey: Keys.copyAfterSave) as? Bool ?? true
        showFloatingToolbar = defaults.object(forKey: Keys.showFloatingToolbar) as? Bool ?? true
        let savedPath = defaults.string(forKey: Keys.saveFolderPath)
        saveFolderURL = savedPath.map(URL.init(fileURLWithPath:)) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
            .appendingPathComponent("Screenshots")
    }
}

enum DefaultAction: String, CaseIterable, Identifiable {
    case copy = "Copy"
    case save = "Save"
    case askEveryTime = "Ask every time"

    var id: String { rawValue }
}

private enum Keys {
    static let defaultAction = "defaultAction"
    static let copyAfterSave = "copyAfterSave"
    static let showFloatingToolbar = "showFloatingToolbar"
    static let saveFolderPath = "saveFolderPath"
}
