import Foundation

enum NimoError: LocalizedError, Equatable {
    case bundledDylibMissing
    case bundledLauncherMissing
    case discordBinaryMissing(URL)
    case permissionDenied(URL, underlying: Error)
    case appManagementDenied(URL)
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
        case .appManagementDenied:
            return "macOS is blocking Nimo from modifying Discord. Enable Nimo under System Settings → Privacy & Security → App Management, then quit and reopen Nimo before retrying."
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
        case let (.appManagementDenied(l), .appManagementDenied(r)):
            return l == r
        case let (.unexpected(l), .unexpected(r)):
            return (l as NSError) == (r as NSError)
        default:
            return false
        }
    }
}

final class InstallationManager: InstallationPerforming {
    private let fileManager: FileManager
    private let dylibURLProvider: () -> URL?
    private let launcherURLProvider: () -> URL?
    /// Closure used to ad-hoc re-sign a modified bundle. Tests override to a no-op.
    private let codesign: (URL) -> Void

    init(
        fileManager: FileManager = .default,
        dylibURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "nimo", withExtension: "dylib") },
        launcherURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "launcher", withExtension: "sh") },
        codesign: @escaping (URL) -> Void = InstallationManager.adhocCodesign
    ) {
        self.fileManager = fileManager
        self.dylibURLProvider = dylibURLProvider
        self.launcherURLProvider = launcherURLProvider
        self.codesign = codesign
    }

    // MARK: - Public API

    func isInstalled(at installation: DiscordInstallation) -> Bool {
        let macOSDir = installation.macOSDirectoryURL
        let real = macOSDir.appendingPathComponent("Discord.real").path
        let dylib = macOSDir.appendingPathComponent("nimo.dylib").path
        return fileManager.fileExists(atPath: real) && fileManager.fileExists(atPath: dylib)
    }

    func install(to installation: DiscordInstallation) throws {
        guard let bundledDylib = dylibURLProvider() else {
            NimoLogger.installer.error("Bundled nimo.dylib missing from app resources")
            throw NimoError.bundledDylibMissing
        }

        let macOSDir = installation.macOSDirectoryURL
        let discordBinary = macOSDir.appendingPathComponent("Discord")
        let discordReal = macOSDir.appendingPathComponent("Discord.real")
        let dylibDest = macOSDir.appendingPathComponent("nimo.dylib")

        // 1. Back up Discord -> Discord.real (once).
        if !fileManager.fileExists(atPath: discordReal.path) {
            guard fileManager.fileExists(atPath: discordBinary.path) else {
                throw NimoError.discordBinaryMissing(discordBinary)
            }
            try wrapFilesystem(at: installation.appURL) {
                try fileManager.moveItem(at: discordBinary, to: discordReal)
            }
        } else if fileManager.fileExists(atPath: discordBinary.path) {
            // Earlier failed install left the old Discord binary around — remove it.
            try? fileManager.removeItem(at: discordBinary)
        }

        // 2. Copy nimo.dylib into place.
        try wrapFilesystem(at: installation.appURL) {
            if fileManager.fileExists(atPath: dylibDest.path) {
                try fileManager.removeItem(at: dylibDest)
            }
            try fileManager.copyItem(at: bundledDylib, to: dylibDest)
        }

        // 3. Write launcher.sh as the new Discord binary.
        try writeLauncher(to: discordBinary, appURL: installation.appURL)

        // 4. Ad-hoc re-sign so Gatekeeper still accepts the bundle.
        codesign(installation.appURL)

        NimoLogger.installer.info("Installed into \(installation.appURL.path, privacy: .public)")
    }

    func uninstall(from installation: DiscordInstallation) throws {
        let macOSDir = installation.macOSDirectoryURL
        let discordBinary = macOSDir.appendingPathComponent("Discord")
        let discordReal = macOSDir.appendingPathComponent("Discord.real")
        let dylibDest = macOSDir.appendingPathComponent("nimo.dylib")

        if fileManager.fileExists(atPath: dylibDest.path) {
            try wrapFilesystem(at: installation.appURL) {
                try fileManager.removeItem(at: dylibDest)
            }
        }
        if fileManager.fileExists(atPath: discordBinary.path) {
            try wrapFilesystem(at: installation.appURL) {
                try fileManager.removeItem(at: discordBinary)
            }
        }
        if fileManager.fileExists(atPath: discordReal.path) {
            try wrapFilesystem(at: installation.appURL) {
                try fileManager.moveItem(at: discordReal, to: discordBinary)
            }
        }

        codesign(installation.appURL)

        NimoLogger.installer.info("Uninstalled from \(installation.appURL.path, privacy: .public)")
    }

    // MARK: - Helpers

    /// Runs a block of FileManager operations and translates permission failures
    /// into the App Management diagnostic we want to show the user.
    private func wrapFilesystem(at appURL: URL, _ block: () throws -> Void) throws {
        do {
            try block()
        } catch let error as NSError where Self.isPermissionDenied(error) {
            throw NimoError.appManagementDenied(appURL)
        } catch {
            throw NimoError.permissionDenied(appURL, underlying: error)
        }
    }

    private static func isPermissionDenied(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain, error.code == 1 /* EPERM */ || error.code == 13 /* EACCES */ {
            return true
        }
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return true
            default:
                break
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionDenied(underlying)
        }
        return false
    }

    private func writeLauncher(to destination: URL, appURL: URL) throws {
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

        try wrapFilesystem(at: appURL) {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: destination.path
            )
        }
    }

    /// Ad-hoc code signs a bundle in place. Failures are logged but non-fatal — the
    /// install still proceeded; Gatekeeper may prompt on first launch but the app works.
    static func adhocCodesign(_ bundle: URL) {
        // Clear quarantine first so the bundle is not treated as downloaded content.
        run(path: "/usr/bin/xattr", args: ["-cr", bundle.path])
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
