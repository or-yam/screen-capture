import Foundation
import Testing
@testable import ScreenCaptureAll

struct AppReleaseTests {
    @Test(arguments: ["1.2.3", "0.0.0", "10.20.30"])
    func acceptsCanonicalVersions(value: String) throws {
        let version = try #require(AppRelease.Version(value))
        #expect(version.description == value)
    }

    @Test(arguments: ["1.2", "v1.2.3", "1.2.3-beta", "01.2.3", "1.-2.3", "+1.2.3", "1.2.3.4", "1..3", "1.2.3\n"])
    func rejectsVersionsTheInstallerCannotAccept(value: String) {
        #expect(AppRelease.Version(value) == nil)
    }

    @Test
    func comparesVersionsNumericallyAndDoesNotOfferDowngrades() throws {
        let older = try #require(AppRelease.Version("1.9.9"))
        let latest = try #require(AppRelease.Version("1.10.0"))
        let newerLocal = try #require(AppRelease.Version("2.0.0"))
        #expect(latest > older)
        #expect(!(latest > latest))
        #expect(!(latest > newerLocal))
    }

    @Test
    func acceptsReleaseWithoutStandaloneInstallerAsset() throws {
        // The GUI ships its own installer, including for older release layouts.
        let release = try decodeRelease()
        #expect(try release.validatedVersion().description == "1.2.3")
    }

    @Test(arguments: ["draft", "prerelease", "missingZIP", "missingChecksums", "duplicateZIP", "invalidTag"])
    func refusesIncompleteOrUnexpectedRelease(variation: String) throws {
        let release = try decodeRelease(variation: variation)
        #expect(throws: AppRelease.UpdateError.self) {
            try release.validatedVersion()
        }
    }

    private func decodeRelease(variation: String = "valid") throws -> AppRelease {
        var assets = [
            ["name": "ScreenCaptureAll-1.2.3-universal.zip"],
            ["name": "ScreenCaptureAll-1.2.3-universal-SHA256SUMS.txt"]
        ]
        if variation == "missingZIP" { assets.removeFirst() }
        if variation == "missingChecksums" { assets.removeLast() }
        if variation == "duplicateZIP" { assets.append(assets[0]) }
        let object: [String: Any] = [
            "tag_name": variation == "invalidTag" ? "v1.2.3-beta" : "v1.2.3",
            "draft": variation == "draft",
            "prerelease": variation == "prerelease",
            "assets": assets
        ]
        return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
