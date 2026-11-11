import Foundation

struct AppRelease: Decodable, Sendable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
    }

    struct Asset: Decodable, Sendable {
        let name: String
    }

    func validatedVersion() throws -> Version {
        guard !draft, !prerelease, tagName.hasPrefix("v"),
              let version = Version(String(tagName.dropFirst())) else {
            throw UpdateError.invalidRelease
        }
        for name in [
            "ScreenCaptureAll-\(version)-universal.zip",
            "ScreenCaptureAll-\(version)-universal-SHA256SUMS.txt"
        ] {
            guard assets.filter({ $0.name == name }).count == 1 else {
                throw UpdateError.invalidRelease
            }
        }
        return version
    }

    static func latest(session: URLSession = .shared) async throws -> AppRelease {
        let url = URL(string: "https://api.github.com/repos/or-yam/screen-capture/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ScreenCaptureAll", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw UpdateError.releaseUnavailable
        }
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    struct Version: Comparable, CustomStringConvertible, Sendable {
        private let components: [Int]

        init?(_ value: String) {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let numbers = parts.compactMap { Int($0) }
            guard numbers.count == 3,
                  zip(parts, numbers).allSatisfy({ part, number in
                      number >= 0 && String(number) == part
                  }) else { return nil }
            components = numbers
        }

        var description: String { components.map(String.init).joined(separator: ".") }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.components.lexicographicallyPrecedes(rhs.components)
        }
    }

    enum UpdateError: LocalizedError {
        case invalidRelease
        case releaseUnavailable
        case unsupportedInstallation

        var errorDescription: String? {
            switch self {
            case .invalidRelease:
                "The release is not a stable version with a universal ZIP and checksums. Try again after the release is complete."
            case .releaseUnavailable:
                "GitHub could not provide the latest release. Check your connection and try again later."
            case .unsupportedInstallation:
                "Run the installed release from a writable folder, such as Applications, to update it. Diagnostic builds and apps running from a disk image cannot update themselves."
            }
        }
    }
}
