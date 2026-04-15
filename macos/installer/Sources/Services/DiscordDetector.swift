import Foundation

final class DiscordDetector: DiscordDetecting {
    private let fileManager: FileManager
    private let searchDirectories: [URL]

    init(
        fileManager: FileManager = .default,
        searchDirectories: [URL] = DiscordDetector.defaultSearchDirectories(fileManager: .default)
    ) {
        self.fileManager = fileManager
        self.searchDirectories = searchDirectories
    }

    static func defaultSearchDirectories(fileManager: FileManager = .default) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    func detect() -> [DiscordInstallation] {
        var seenPaths = Set<String>()
        var results: [DiscordInstallation] = []

        for directory in searchDirectories {
            for edition in DiscordInstallation.Edition.allCases {
                let appURL = directory.appendingPathComponent(edition.bundleName, isDirectory: true)
                let standardized = appURL.standardizedFileURL.path
                guard !seenPaths.contains(standardized) else { continue }

                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let macOSDir = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
                // Require either Discord binary or Discord.real to exist (otherwise it's not a real bundle).
                let discordBinary = macOSDir.appendingPathComponent("Discord").path
                let discordReal = macOSDir.appendingPathComponent("Discord.real").path
                guard fileManager.fileExists(atPath: discordBinary) || fileManager.fileExists(atPath: discordReal) else {
                    continue
                }

                let installed = isInstalled(at: macOSDir)
                seenPaths.insert(standardized)
                results.append(
                    DiscordInstallation(
                        edition: edition,
                        appURL: appURL,
                        isInstalled: installed
                    )
                )
                NimoLogger.detector.debug("Detected \(edition.displayName, privacy: .public) at \(appURL.path, privacy: .public) installed=\(installed, privacy: .public)")
            }
        }

        return results
    }

    private func isInstalled(at macOSDir: URL) -> Bool {
        let realPath = macOSDir.appendingPathComponent("Discord.real").path
        let dylibPath = macOSDir.appendingPathComponent("nimo.dylib").path
        return fileManager.fileExists(atPath: realPath) && fileManager.fileExists(atPath: dylibPath)
    }
}
