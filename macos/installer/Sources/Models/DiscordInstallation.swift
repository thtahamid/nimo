import Foundation

struct DiscordInstallation: Identifiable, Equatable {
    enum Edition: String, Equatable, CaseIterable {
        case stable
        case canary
        case ptb

        var displayName: String {
            switch self {
            case .stable: return "Discord"
            case .canary: return "Discord Canary"
            case .ptb: return "Discord PTB"
            }
        }

        /// Bundle filename (e.g., "Discord.app") to look for on disk.
        var bundleName: String {
            switch self {
            case .stable: return "Discord.app"
            case .canary: return "Discord Canary.app"
            case .ptb: return "Discord PTB.app"
            }
        }
    }

    var id: UUID = UUID()
    var edition: Edition
    var appURL: URL
    var isInstalled: Bool

    /// The `Contents/MacOS` directory inside the Discord app bundle.
    var macOSDirectoryURL: URL {
        appURL.appendingPathComponent("Contents/MacOS")
    }

    static func == (lhs: DiscordInstallation, rhs: DiscordInstallation) -> Bool {
        lhs.edition == rhs.edition &&
        lhs.appURL == rhs.appURL &&
        lhs.isInstalled == rhs.isInstalled
    }
}
