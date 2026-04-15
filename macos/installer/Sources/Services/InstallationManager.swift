import Foundation

enum NimoError: LocalizedError, Equatable {
    case bundledDylibMissing
    case bundledLauncherMissing
    case discordBinaryMissing(URL)
    case permissionDenied(URL, underlying: Error)
    case appManagementDenied(URL)
    case authorizationCancelled
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
            return "macOS is blocking Nimo from modifying Discord. Enable Nimo under System Settings → Privacy & Security → App Management, then retry."
        case .authorizationCancelled:
            return "Administrator authorization was cancelled — nothing was changed."
        case .unexpected(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }

    static func == (lhs: NimoError, rhs: NimoError) -> Bool {
        switch (lhs, rhs) {
        case (.bundledDylibMissing, .bundledDylibMissing),
             (.bundledLauncherMissing, .bundledLauncherMissing),
             (.authorizationCancelled, .authorizationCancelled):
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
    private let executor: PrivilegedExecuting

    init(
        fileManager: FileManager = .default,
        dylibURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "nimo", withExtension: "dylib") },
        launcherURLProvider: @escaping () -> URL? = { Bundle.main.url(forResource: "launcher", withExtension: "sh") },
        executor: PrivilegedExecuting = AppleScriptPrivilegedExecutor()
    ) {
        self.fileManager = fileManager
        self.dylibURLProvider = dylibURLProvider
        self.launcherURLProvider = launcherURLProvider
        self.executor = executor
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

        // Require a real Discord binary (or a pre-existing Discord.real from a prior install).
        if !fileManager.fileExists(atPath: discordReal.path),
           !fileManager.fileExists(atPath: discordBinary.path) {
            throw NimoError.discordBinaryMissing(discordBinary)
        }

        // Launcher: prefer the bundled file, otherwise write an inline template to a temp file.
        let launcherSource = try resolvedLauncherURL()
        defer { launcherSource.cleanup() }

        let commands: [String] = [
            "set -e",
            "DIR=\(shQuote(macOSDir.path))",
            "APP=\(shQuote(installation.appURL.path))",
            "if [ ! -e \"$DIR/Discord.real\" ]; then mv \"$DIR/Discord\" \"$DIR/Discord.real\"; fi",
            "rm -f \"$DIR/Discord\" \"$DIR/nimo.dylib\"",
            "cp \(shQuote(bundledDylib.path)) \"$DIR/nimo.dylib\"",
            "cp \(shQuote(launcherSource.url.path)) \"$DIR/Discord\"",
            "chmod 755 \"$DIR/Discord\" \"$DIR/Discord.real\"",
            "chmod 644 \"$DIR/nimo.dylib\"",
            // Clear quarantine on the whole bundle so Gatekeeper doesn't re-prompt.
            "xattr -cr \"$APP\" 2>/dev/null || true",
            // Ad-hoc re-sign so Gatekeeper accepts the modified bundle.
            "codesign --force --deep --sign - \"$APP\" 2>/dev/null || true"
        ]

        do {
            try executor.run(commands.joined(separator: "\n"))
        } catch is PrivilegedCancelled {
            throw NimoError.authorizationCancelled
        } catch let failure as PrivilegedFailure where Self.looksLikeAppManagementBlock(failure.message) {
            throw NimoError.appManagementDenied(installation.appURL)
        } catch {
            throw NimoError.permissionDenied(macOSDir, underlying: error)
        }

        NimoLogger.installer.info("Installed into \(installation.appURL.path, privacy: .public)")
    }

    func uninstall(from installation: DiscordInstallation) throws {
        let macOSDir = installation.macOSDirectoryURL

        let commands: [String] = [
            "set -e",
            "DIR=\(shQuote(macOSDir.path))",
            "APP=\(shQuote(installation.appURL.path))",
            "rm -f \"$DIR/nimo.dylib\" \"$DIR/Discord\"",
            "if [ -e \"$DIR/Discord.real\" ]; then mv \"$DIR/Discord.real\" \"$DIR/Discord\"; fi",
            "codesign --force --deep --sign - \"$APP\" 2>/dev/null || true"
        ]

        do {
            try executor.run(commands.joined(separator: "\n"))
        } catch is PrivilegedCancelled {
            throw NimoError.authorizationCancelled
        } catch let failure as PrivilegedFailure where Self.looksLikeAppManagementBlock(failure.message) {
            throw NimoError.appManagementDenied(installation.appURL)
        } catch {
            throw NimoError.permissionDenied(macOSDir, underlying: error)
        }

        NimoLogger.installer.info("Uninstalled from \(installation.appURL.path, privacy: .public)")
    }

    // MARK: - Helpers

    private struct LauncherSource {
        let url: URL
        let isTemporary: Bool
        func cleanup() {
            if isTemporary {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func resolvedLauncherURL() throws -> LauncherSource {
        if let bundled = launcherURLProvider(), fileManager.fileExists(atPath: bundled.path) {
            return LauncherSource(url: bundled, isTemporary: false)
        }
        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("nimo-launcher-\(UUID().uuidString).sh")
        guard let data = Self.inlineLauncherTemplate.data(using: .utf8) else {
            throw NimoError.bundledLauncherMissing
        }
        do {
            try data.write(to: tmp, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: tmp.path)
        } catch {
            throw NimoError.bundledLauncherMissing
        }
        return LauncherSource(url: tmp, isTemporary: true)
    }

    private func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// True when shell stderr indicates macOS App Management (Sonoma+) blocked
    /// the modification even though we elevated via osascript.
    static func looksLikeAppManagementBlock(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("operation not permitted") ||
               lower.contains("not permitted")
    }

    private static let inlineLauncherTemplate = """
    #!/bin/bash
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    export DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/nimo.dylib"
    exec "$SCRIPT_DIR/Discord.real" "$@"
    """
}
