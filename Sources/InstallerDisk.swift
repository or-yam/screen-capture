import Foundation

enum InstallerDisk {
    static func find(for applicationURL: URL) async -> URL? {
        // hdiutil and bundle inspection must not block the menu bar's main actor.
        await Task.detached(priority: .utility) {
            guard isInApplications(applicationURL) else { return nil }
            return matchingVolume(for: applicationURL, among: mountedImageVolumes())
        }.value
    }

    static func isInApplications(
        _ applicationURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let url = applicationURL.resolvingSymlinksInPath().standardizedFileURL
        let directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        return url.pathExtension == "app" && directories.contains {
            url.deletingLastPathComponent() == $0.resolvingSymlinksInPath().standardizedFileURL
        }
    }

    static func matchingVolume(
        for applicationURL: URL,
        among volumes: [URL],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isReadOnly: (URL) -> Bool = {
            (try? $0.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
        }
    ) -> URL? {
        guard isInApplications(applicationURL, homeDirectory: homeDirectory),
              let installed = Bundle(url: applicationURL),
              let identifier = installed.bundleIdentifier,
              let version = installed.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = installed.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return nil
        }

        return volumes.first { volume in
            let applicationsLink = volume.appendingPathComponent("Applications")
            guard isReadOnly(volume),
                  (try? FileManager.default.destinationOfSymbolicLink(atPath: applicationsLink.path)) != nil,
                  applicationsLink.resolvingSymlinksInPath().standardizedFileURL
                    == URL(fileURLWithPath: "/Applications", isDirectory: true),
                  let installer = Bundle(url: volume.appendingPathComponent(applicationURL.lastPathComponent)) else {
                return false
            }
            return installer.bundleIdentifier == identifier
                && installer.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
                && installer.object(forInfoDictionaryKey: "CFBundleVersion") as? String == build
        }
    }

    static func imageVolumes(from data: Data) -> [URL] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = plist as? [String: Any],
              let images = info["images"] as? [[String: Any]] else { return [] }
        return images.flatMap { image -> [URL] in
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            return entities.compactMap { entity in
                guard let path = entity["mount-point"] as? String, path.hasPrefix("/") else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
    }

    private static func mountedImageVolumes() -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return imageVolumes(from: data)
        } catch {
            return []
        }
    }
}
