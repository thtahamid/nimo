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

final class InstallationManager: InstallationPerforming {
    private let fileManager: FileManager
    private let dylibURLProvider: () -> URL?
    private let launcherURLProvider: () -> URL?

    init(
        fileManager: FileManager = .default,
        dylibURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "nimo", withExtension: "dylib") },
        launcherURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "launcher", withExtension: "sh") }
    ) {
        self.fileManager = fileManager
        self.dylibURLProvider = dylibURLProvider
        self.launcherURLProvider = launcherURLProvider
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
        let dylibDestination = macOSDir.appendingPathComponent("nimo.dylib")

        // Step 1: rename Discord -> Discord.real (only if Discord.real does not exist yet).
        if !fileManager.fileExists(atPath: discordReal.path) {
            guard fileManager.fileExists(atPath: discordBinary.path) else {
                throw NimoError.discordBinaryMissing(discordBinary)
            }
            do {
                try fileManager.moveItem(at: discordBinary, to: discordReal)
            } catch {
                throw NimoError.permissionDenied(discordBinary, underlying: error)
            }
        } else {
            NimoLogger.installer.info("Discord.real already exists, skipping backup step")
            // If the old Discord binary still exists alongside Discord.real (from a prior failed install),
            // remove it so we can rewrite the launcher below.
            if fileManager.fileExists(atPath: discordBinary.path) {
                try? fileManager.removeItem(at: discordBinary)
            }
        }

        // Step 2: copy nimo.dylib into place (replace if already present).
        do {
            if fileManager.fileExists(atPath: dylibDestination.path) {
                try fileManager.removeItem(at: dylibDestination)
            }
            try fileManager.copyItem(at: bundledDylib, to: dylibDestination)
        } catch {
            throw NimoError.permissionDenied(dylibDestination, underlying: error)
        }

        // Step 3: write launcher.sh as Discord, chmod 755.
        try writeLauncher(to: discordBinary)

        NimoLogger.installer.info("Installed into \(installation.appURL.path, privacy: .public)")
    }

    func uninstall(from installation: DiscordInstallation) throws {
        let macOSDir = installation.macOSDirectoryURL
        let discordBinary = macOSDir.appendingPathComponent("Discord")
        let discordReal = macOSDir.appendingPathComponent("Discord.real")
        let dylibDestination = macOSDir.appendingPathComponent("nimo.dylib")

        // Remove nimo.dylib if present.
        if fileManager.fileExists(atPath: dylibDestination.path) {
            do {
                try fileManager.removeItem(at: dylibDestination)
            } catch {
                throw NimoError.permissionDenied(dylibDestination, underlying: error)
            }
        }

        // Remove launcher script at Discord path.
        if fileManager.fileExists(atPath: discordBinary.path) {
            do {
                try fileManager.removeItem(at: discordBinary)
            } catch {
                throw NimoError.permissionDenied(discordBinary, underlying: error)
            }
        }

        // Move Discord.real back to Discord.
        if fileManager.fileExists(atPath: discordReal.path) {
            do {
                try fileManager.moveItem(at: discordReal, to: discordBinary)
            } catch {
                throw NimoError.permissionDenied(discordReal, underlying: error)
            }
        }

        NimoLogger.installer.info("Uninstalled from \(installation.appURL.path, privacy: .public)")
    }

    // MARK: - Helpers

    private func writeLauncher(to destination: URL) throws {
        // Prefer the bundled launcher.sh resource. Fall back to an inline template if not present.
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

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: destination.path
            )
        } catch {
            throw NimoError.permissionDenied(destination, underlying: error)
        }
    }

    private static let inlineLauncherTemplate = """
    #!/bin/bash
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    export DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/nimo.dylib"
    exec "$SCRIPT_DIR/Discord.real" "$@"
    """
}
