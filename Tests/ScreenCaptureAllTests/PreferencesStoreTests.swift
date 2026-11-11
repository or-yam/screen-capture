import Foundation
import Testing
@testable import ScreenCaptureAll

@MainActor
struct PreferencesStoreTests {
    @Test
    func initialPreferencesPresentationIsRememberedAcrossLaunches() throws {
        let suiteName = "ScreenCaptureAllTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = PreferencesStore(defaults: defaults)
        #expect(!firstLaunch.hasShownInitialPreferences)

        firstLaunch.hasShownInitialPreferences = true

        let nextLaunchDefaults = try #require(UserDefaults(suiteName: suiteName))
        let nextLaunch = PreferencesStore(defaults: nextLaunchDefaults)
        #expect(nextLaunch.hasShownInitialPreferences)
    }

    @Test
    func existingPreferencesDoNotSuppressInitialPresentation() throws {
        let suiteName = "ScreenCaptureAllTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let previousVersion = PreferencesStore(defaults: defaults)
        previousVersion.showsSaveConfirmation = false

        let upgradedVersion = PreferencesStore(defaults: defaults)
        #expect(!upgradedVersion.showsSaveConfirmation)
        #expect(!upgradedVersion.hasShownInitialPreferences)
    }
}
