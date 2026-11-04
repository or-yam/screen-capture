import Foundation
import Testing
@testable import ScreenCaptureAll

struct InstallerDiskTests {
    @Test(arguments: [
        ("/Applications/ScreenCaptureAll.app", true),
        ("/Users/test/Applications/ScreenCaptureAll.app", true),
        ("/Volumes/ScreenCaptureAll/ScreenCaptureAll.app", false),
        ("/Users/test/Downloads/ScreenCaptureAll.app", false),
        ("/ApplicationsOther/ScreenCaptureAll.app", false),
        ("/Applications/ScreenCaptureAll", false)
    ])
    func onlyInstalledAppLocationsOfferEjection(path: String, expected: Bool) {
        #expect(InstallerDisk.isInApplications(
            URL(fileURLWithPath: path),
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) == expected)
    }

    @Test
    func findsOnlyTheMatchingReadOnlyInstaller() throws {
        let fixture = try InstallerFixture()
        let unrelated = try fixture.makeVolume("Unrelated", identifier: "com.example.other")
        let oldVersion = try fixture.makeVolume("Old", version: "0.9")
        let otherBuild = try fixture.makeVolume("OtherBuild", build: "2")
        let installer = try fixture.makeVolume("Installer")
        let result = InstallerDisk.matchingVolume(
            for: fixture.installedApp,
            among: [unrelated, oldVersion, otherBuild, installer],
            homeDirectory: fixture.home,
            isReadOnly: { _ in true }
        )
        #expect(result == installer)
    }

    @Test
    func writableVolumesAreNotOfferedForEjection() throws {
        let fixture = try InstallerFixture()
        let volume = try fixture.makeVolume("Writable")
        #expect(InstallerDisk.matchingVolume(
            for: fixture.installedApp,
            among: [volume],
            homeDirectory: fixture.home,
            isReadOnly: { _ in false }
        ) == nil)
    }

    @Test
    func aMatchingAppWithoutTheInstallerLayoutIsNotEnough() throws {
        let fixture = try InstallerFixture()
        let volume = try fixture.makeVolume("NotInstaller", applicationsLink: false)
        #expect(InstallerDisk.matchingVolume(
            for: fixture.installedApp,
            among: [volume],
            homeDirectory: fixture.home,
            isReadOnly: { _ in true }
        ) == nil)
    }

    @Test
    func applicationsLinkMustPointToTheRealApplicationsFolder() throws {
        let fixture = try InstallerFixture()
        let volume = try fixture.makeVolume("WrongLink", applicationsLink: false)
        try FileManager.default.createSymbolicLink(
            atPath: volume.appendingPathComponent("Applications").path,
            withDestinationPath: fixture.home.path
        )
        #expect(InstallerDisk.matchingVolume(
            for: fixture.installedApp,
            among: [volume],
            homeDirectory: fixture.home,
            isReadOnly: { _ in true }
        ) == nil)
    }

    @Test
    func runningFromTheImageNeverOffersToEjectItself() throws {
        let fixture = try InstallerFixture()
        let volume = try fixture.makeVolume("Installer")
        #expect(InstallerDisk.matchingVolume(
            for: volume.appendingPathComponent("ScreenCaptureAll.app"),
            among: [volume],
            homeDirectory: fixture.home,
            isReadOnly: { _ in true }
        ) == nil)
    }

    @Test
    func missingMountedImagesHideEjection() throws {
        let fixture = try InstallerFixture()
        #expect(InstallerDisk.matchingVolume(
            for: fixture.installedApp,
            among: [],
            homeDirectory: fixture.home
        ) == nil)
    }

    @Test
    func parsesOnlyMountedDiskImageEntities() throws {
        let plist: [String: Any] = ["images": [
            ["image-path": "/Users/test/Downloads/Installer.dmg", "system-entities": [
                ["dev-entry": "/dev/disk5"],
                ["mount-point": "/Volumes/ScreenCaptureAll"],
                ["mount-point": "relative/path"]
            ]],
            ["image-path": "/Users/test/Downloads/Unmounted.dmg"]
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(InstallerDisk.imageVolumes(from: data) == [
            URL(fileURLWithPath: "/Volumes/ScreenCaptureAll", isDirectory: true)
        ])
        #expect(InstallerDisk.imageVolumes(from: Data("invalid".utf8)).isEmpty)
    }
}

private final class InstallerFixture {
    let root: URL
    let home: URL
    let installedApp: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode/InstallerTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("Home", isDirectory: true)
        installedApp = home.appendingPathComponent("Applications/ScreenCaptureAll.app", isDirectory: true)
        try makeApp(at: installedApp)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeVolume(
        _ name: String,
        identifier: String = "com.oryam.ScreenCaptureAll",
        version: String = "1.0",
        build: String = "1",
        applicationsLink: Bool = true
    ) throws -> URL {
        let volume = root.appendingPathComponent(name, isDirectory: true)
        try makeApp(
            at: volume.appendingPathComponent("ScreenCaptureAll.app", isDirectory: true),
            identifier: identifier, version: version, build: build
        )
        if applicationsLink {
            try FileManager.default.createSymbolicLink(
                atPath: volume.appendingPathComponent("Applications").path,
                withDestinationPath: "/Applications"
            )
        }
        return volume
    }

    private func makeApp(
        at url: URL,
        identifier: String = "com.oryam.ScreenCaptureAll",
        version: String = "1.0",
        build: String = "1"
    ) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = [
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "CFBundlePackageType": "APPL"
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
}
