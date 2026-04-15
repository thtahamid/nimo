import Foundation

enum NimoError: LocalizedError, Equatable {
    case bundledDylibMissing
    case bundledLauncherMissing
    case discordBinaryMissing(URL)
    case permissionDenied(URL, underlying: Error)
    case unexpected(Error)

    var errorDescription: String? {
        switch self {
        case .bundledDylibMissing:
            return "The bundled nimo.dylib could not be found inside the installer app."
        case .bundledLauncherMissing:
            return "The bundled launcher.sh could not be found inside the installer app."
        case .discordBinaryMissing(let url):
            return "Expected Discord binary was not found at \(url.path)."
        case .permissionDenied(let url, let underlying):
            return "Permission denied while modifying \(url.path). Underlying error: \(underlying.localizedDescription)"
        case .unexpected(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }

    static func == (lhs: NimoError, rhs: NimoError) -> Bool {
        switch (lhs, rhs) {
        case (.bundledDylibMissing, .bundledDylibMissing),
             (.bundledLauncherMissing, .bundledLauncherMissing):
            return true
        case let (.discordBinaryMissing(l), .discordBinaryMissing(r)):
            return l == r
        case let (.permissionDenied(lu, _), .permissionDenied(ru, _)):
            return lu == ru
        case let (.unexpected(l), .unexpected(r)):
            return (l as NSError) == (r as NSError)
        default:
            return false
        }
    }
}

/// Installs Nimo by building a modified **copy** of Discord.app at
/// `~/Applications/<Edition> (Nimo).app`. The original /Applications bundle is
/// never touched, which avoids the macOS App Management TCC prompt loop entirely.
final class InstallationManager: InstallationPerforming {
    private let fileManager: FileManager
    private let dylibURLProvider: () -> URL?
    private let launcherURLProvider: () -> URL?
    private let codesign: (URL) -> Void
    private let wrapperParentURL: URL

    init(
        fileManager: FileManager = .default,
        dylibURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "nimo", withExtension: "dylib") },
        launcherURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "launcher", withExtension: "sh") },
        codesign: @escaping (URL) -> Void = InstallationManager.adhocCodesign,
        wrapperParentURL: URL = InstallationManager.defaultWrapperParent
    ) {
        self.fileManager = fileManager
        self.dylibURLProvider = dylibURLProvider
        self.launcherURLProvider = launcherURLProvider
        self.codesign = codesign
        self.wrapperParentURL = wrapperParentURL
    }

    static var defaultWrapperParent: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    // MARK: - Public API

    func wrapperURL(for installation: DiscordInstallation) -> URL {
        let name = "\(installation.edition.displayName) (Nimo).app"
        return wrapperParentURL.appendingPathComponent(name, isDirectory: true)
    }

    func isInstalled(at installation: DiscordInstallation) -> Bool {
        let wrapper = wrapperURL(for: installation)
        let macOS = wrapper.appendingPathComponent("Contents/MacOS")
        let dylib = macOS.appendingPathComponent("nimo.dylib")
        let real = macOS.appendingPathComponent("Discord.real")
        return fileManager.fileExists(atPath: dylib.path) && fileManager.fileExists(atPath: real.path)
    }

    func install(to installation: DiscordInstallation) throws {
        guard let bundledDylib = dylibURLProvider() else {
            NimoLogger.installer.error("Bundled nimo.dylib missing from app resources")
            throw NimoError.bundledDylibMissing
        }

        let source = installation.appURL
        let sourceBinary = source.appendingPathComponent("Contents/MacOS/Discord")
        guard fileManager.fileExists(atPath: sourceBinary.path) else {
            throw NimoError.discordBinaryMissing(sourceBinary)
        }

        let destination = wrapperURL(for: installation)

        do {
            // Ensure ~/Applications exists (user-owned — no TCC prompt).
            try fileManager.createDirectory(at: wrapperParentURL, withIntermediateDirectories: true)

            // Fresh install: remove any previous wrapper so auto-updated Discord is picked up.
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            // Copy the whole Discord.app into our home folder. Reading /Applications
            // is always allowed; writing under ~/Applications does not require App Management.
            try fileManager.copyItem(at: source, to: destination)

            // Now reshape the copy:
            let macOS = destination.appendingPathComponent("Contents/MacOS")
            let discord = macOS.appendingPathComponent("Discord")
            let discordReal = macOS.appendingPathComponent("Discord.real")
            let dylibDest = macOS.appendingPathComponent("nimo.dylib")

            // If source already had a prior in-place install (Discord.real present),
            // the real binary came through unchanged; just drop the leftover launcher.
            if fileManager.fileExists(atPath: discordReal.path) {
                if fileManager.fileExists(atPath: discord.path) {
                    try fileManager.removeItem(at: discord)
                }
            } else {
                try fileManager.moveItem(at: discord, to: discordReal)
            }

            // Copy bundled nimo.dylib next to it (replace if carried over from prior install).
            if fileManager.fileExists(atPath: dylibDest.path) {
                try fileManager.removeItem(at: dylibDest)
            }
            try fileManager.copyItem(at: bundledDylib, to: dylibDest)

            // Write the launcher script as the new main binary.
            try writeLauncher(to: discord)
        } catch let error as NimoError {
            throw error
        } catch {
            throw NimoError.permissionDenied(destination, underlying: error)
        }

        // Strip the original signature (with hardened runtime) and ad-hoc re-sign so
        // DYLD_INSERT_LIBRARIES takes effect and Gatekeeper still launches the bundle.
        codesign(destination)

        NimoLogger.installer.info("Wrapper created at \(destination.path, privacy: .public)")
    }

    func uninstall(from installation: DiscordInstallation) throws {
        let wrapper = wrapperURL(for: installation)
        guard fileManager.fileExists(atPath: wrapper.path) else { return }
        do {
            try fileManager.removeItem(at: wrapper)
        } catch {
            throw NimoError.permissionDenied(wrapper, underlying: error)
        }
        NimoLogger.installer.info("Wrapper removed at \(wrapper.path, privacy: .public)")
    }

    // MARK: - Helpers

    private func writeLauncher(to destination: URL) throws {
        let data: Data
        if let launcherURL = launcherURLProvider(),
           let contents = try? Data(contentsOf: launcherURL) {
            data = contents
        } else {
            guard let inline = Self.inlineLauncherTemplate.data(using: .utf8) else {
                throw NimoError.bundledLauncherMissing
            }
            data = inline
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: destination.path
        )
    }

    /// Clears quarantine and ad-hoc re-signs a bundle so DYLD_INSERT_LIBRARIES takes
    /// effect and Gatekeeper accepts the modified copy.
    static func adhocCodesign(_ bundle: URL) {
        run(path: "/usr/bin/xattr", args: ["-cr", bundle.path])
        // Strip the original signature to drop hardened runtime.
        run(path: "/usr/bin/codesign", args: ["--remove-signature", bundle.path])
        run(path: "/usr/bin/codesign", args: ["--force", "--deep", "--sign", "-", bundle.path])
    }

    @discardableResult
    private static func run(path: String, args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            NimoLogger.installer.error("\(path) failed to launch: \(error.localizedDescription, privacy: .public)")
            return -1
        }
    }

    private static let inlineLauncherTemplate = """
    #!/bin/bash
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    export DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/nimo.dylib"
    exec "$SCRIPT_DIR/Discord.real" "$@"
    """
}
