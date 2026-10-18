import Foundation
import Testing
@testable import ScreenCaptureAll

@MainActor
struct ScreenRecordingPermissionTests {
    @Test
    func firstLaunchRequestsMissingPermissionThenOpensSettings() {
        let fixture = PermissionFixture()
        fixture.controller.handleFirstLaunch()

        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 1)
        #expect(!fixture.controller.isAllowed)
    }

    @Test
    func allowedFirstLaunchIsSilent() {
        let fixture = PermissionFixture()
        fixture.allowed = true
        fixture.controller.handleFirstLaunch()

        #expect(fixture.controller.isAllowed)
        #expect(fixture.requestCount == 0)
        #expect(fixture.settingsOpenCount == 0)
    }

    @Test
    func grantDuringNativeRequestDoesNotOpenSettings() {
        let fixture = PermissionFixture()
        fixture.grantOnRequest = true
        fixture.controller.handleFirstLaunch()

        #expect(fixture.controller.isAllowed)
        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 0)
    }

    @Test
    func repeatedLaunchChecksDoNotRepeatSetup() {
        let fixture = PermissionFixture()
        fixture.controller.handleFirstLaunch()
        fixture.controller.handleFirstLaunch()
        fixture.makeController().handleFirstLaunch()

        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 1)
    }

    @Test
    func launchMarkerIsSavedBeforeNativeRequestCanRelaunchApp() {
        let fixture = PermissionFixture()
        fixture.onRequest = { [unowned fixture] in
            // Simulate a fresh process reaching launch handling during the native request.
            fixture.makeController().handleFirstLaunch()
        }
        fixture.controller.handleFirstLaunch()

        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 1)
    }

    @Test
    func overlappingActionsDoNotStackNativePermissionRequests() {
        let fixture = PermissionFixture()
        fixture.onRequest = { [unowned fixture] in
            #expect(!fixture.controller.requestAccess())
        }
        fixture.controller.requestAccess()
        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 1)
    }

    @Test
    func returnFromSettingsRechecksWithoutOpeningAnything() {
        let fixture = PermissionFixture()
        fixture.controller.handleFirstLaunch()
        fixture.allowed = true
        fixture.controller.refresh()
        #expect(fixture.controller.isAllowed)

        fixture.allowed = false
        fixture.controller.refresh()
        #expect(!fixture.controller.isAllowed)
        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 1)
    }

    @Test
    func revokedPermissionWaitsForCaptureRatherThanInterruptingLaunch() {
        let fixture = PermissionFixture()
        fixture.allowed = true
        fixture.controller.handleFirstLaunch()
        fixture.allowed = false
        let relaunched = fixture.makeController()
        relaunched.handleFirstLaunch()
        #expect(fixture.requestCount == 0)
        #expect(fixture.settingsOpenCount == 0)

        #expect(!relaunched.requestAccess())
        #expect(fixture.requestCount == 1)
        #expect(fixture.settingsOpenCount == 1)
    }

    @Test
    func captureWithPermissionDoesNotRequestOrOpenSettings() {
        let fixture = PermissionFixture()
        fixture.allowed = true
        #expect(fixture.controller.requestAccess())
        #expect(fixture.requestCount == 0)
        #expect(fixture.settingsOpenCount == 0)
    }

    @Test
    func permissionStillUnavailableAfterApprovalDoesNotClaimCaptureIsReady() {
        let fixture = PermissionFixture()
        fixture.requestResult = true
        #expect(!fixture.controller.requestAccess())
        #expect(!fixture.controller.isAllowed)
        // macOS owns the required restart prompt; don't stack another Settings launch on it.
        #expect(fixture.settingsOpenCount == 0)
    }
}

@MainActor
private final class PermissionFixture {
    private let suiteName = "ScreenCaptureAll.PermissionTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    var allowed = false
    var grantOnRequest = false
    var requestResult = false
    var requestCount = 0
    var settingsOpenCount = 0
    var onRequest: (() -> Void)?
    lazy var controller = makeController()

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeController() -> ScreenRecordingPermissionController {
        ScreenRecordingPermissionController(
            defaults: defaults,
            preflight: { [unowned self] in allowed },
            request: { [unowned self] in
                requestCount += 1
                onRequest?()
                if grantOnRequest { allowed = true }
                return requestResult || allowed
            },
            openSettings: { [unowned self] in settingsOpenCount += 1 }
        )
    }
}
