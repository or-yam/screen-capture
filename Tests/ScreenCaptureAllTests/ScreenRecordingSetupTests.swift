import AppKit
import Testing
@testable import ScreenCaptureAll

@MainActor
struct ScreenRecordingSetupTests {
    @Test(arguments: [false, true], [false, true])
    func launchChecksPermissionEvenWhenInitialPreferencesWereShown(
        hasShownInitialPreferences: Bool,
        hasAccess: Bool
    ) throws {
        let suiteName = "ScreenRecordingSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasShownInitialPreferences = hasShownInitialPreferences
        var checkCount = 0
        let setup = ScreenRecordingSetup(checkAccess: {
            checkCount += 1
            return hasAccess
        })

        #expect(setup.prepareForLaunch(preferences: preferences) == (!hasShownInitialPreferences || !hasAccess))
        #expect(checkCount == 1)
        #expect(setup.isAllowed == hasAccess)
        #expect(preferences.hasShownInitialPreferences)
    }

    @Test
    func retainedSettingsSurviveMissingPermissionAndReadyRelaunches() throws {
        let suiteName = "ScreenRecordingSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previousInstall = PreferencesStore(defaults: defaults)
        previousInstall.hasShownInitialPreferences = true
        previousInstall.saveFolderURL = URL(fileURLWithPath: "/tmp/My Screenshots")
        previousInstall.defaultAnnotationColor = .systemBlue
        previousInstall.defaultAnnotationStrokeWidth = 12
        previousInstall.showsSaveConfirmation = false
        previousInstall.showsMenuBarIcon = false

        var hasAccess = false
        let setup = ScreenRecordingSetup(checkAccess: { hasAccess })
        let reinstalled = PreferencesStore(defaults: defaults)
        #expect(setup.prepareForLaunch(preferences: reinstalled))

        hasAccess = true
        setup.refresh()
        #expect(setup.isAllowed)
        let nextLaunchDefaults = try #require(UserDefaults(suiteName: suiteName))
        let readyLaunch = PreferencesStore(defaults: nextLaunchDefaults)
        #expect(!setup.prepareForLaunch(preferences: readyLaunch))
        #expect(readyLaunch.saveFolderURL == previousInstall.saveFolderURL)
        #expect(readyLaunch.defaultAnnotationColor == previousInstall.defaultAnnotationColor)
        #expect(readyLaunch.defaultAnnotationStrokeWidth == 12)
        #expect(!readyLaunch.showsSaveConfirmation)
        #expect(!readyLaunch.showsMenuBarIcon)

        hasAccess = false
        let revokedLaunch = PreferencesStore(defaults: nextLaunchDefaults)
        #expect(setup.prepareForLaunch(preferences: revokedLaunch))
        #expect(!setup.isAllowed)
        #expect(!revokedLaunch.showsMenuBarIcon)
    }

    @Test
    func openingSettingsDoesNotReportPermissionGranted() {
        var openedURL: URL?
        var hasAccess = false
        let setup = ScreenRecordingSetup(
            checkAccess: { hasAccess },
            openURL: { openedURL = $0; return true }
        )
        setup.refresh()
        setup.openSystemSettings()

        #expect(openedURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        #expect(!setup.isAllowed)
        #expect(setup.actionFeedback == nil)
        hasAccess = true
        #expect(!setup.isAllowed)
        setup.refresh()
        #expect(setup.isAllowed)
        hasAccess = false
        setup.refresh()
        #expect(!setup.isAllowed)
    }

    @Test
    func settingsHandoffFailureOffersManualInstructions() {
        let setup = ScreenRecordingSetup(checkAccess: { false }, openURL: { _ in false })
        setup.openSystemSettings()
        #expect(setup.actionFeedback?.contains("Privacy & Security") == true)
        #expect(!setup.isAllowed)
    }

    @Test(arguments: [
        "/Applications/ScreenCaptureAll.app",
        "/Users/test/Custom Apps/ScreenCaptureAll.app",
        "/Users/test/project/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app"
    ])
    func pathActionsUseTheRunningBundleLocation(path: String) {
        let appURL = URL(fileURLWithPath: path)
        var revealedURL: URL?
        var copiedText: String?
        let setup = ScreenRecordingSetup(
            appURL: appURL,
            checkAccess: { false },
            revealURL: { revealedURL = $0 },
            copyText: { copiedText = $0; return true }
        )
        setup.showAppInFinder()
        setup.copyAppPath()

        #expect(revealedURL == appURL)
        #expect(copiedText == path)
        #expect(setup.appURL == appURL)
        #expect(setup.actionFeedback == "App path copied.")
    }

    @Test
    func copyFailureDoesNotReportSuccess() {
        let setup = ScreenRecordingSetup(checkAccess: { false }, copyText: { _ in false })
        setup.copyAppPath()
        #expect(setup.actionFeedback?.hasPrefix("Could not copy") == true)
    }
}
