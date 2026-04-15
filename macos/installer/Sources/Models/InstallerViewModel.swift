import Foundation
import SwiftUI

/// Abstraction over Discord detection so tests can stub.
protocol DiscordDetecting {
    func detect() -> [DiscordInstallation]
}

/// Abstraction over the install/uninstall actions so tests can stub.
protocol InstallationPerforming {
    func install(to installation: DiscordInstallation) throws
    func uninstall(from installation: DiscordInstallation) throws
    func isInstalled(at installation: DiscordInstallation) -> Bool
}

@MainActor
final class InstallerViewModel: ObservableObject {
    @Published private(set) var installations: [DiscordInstallation] = []
    @Published private(set) var state: InstallationState = .idle
    @Published private(set) var lastError: NimoError?

    private let detector: DiscordDetecting
    private let installer: InstallationPerforming

    init(
        detector: DiscordDetecting = DiscordDetector(),
        installer: InstallationPerforming = InstallationManager()
    ) {
        self.detector = detector
        self.installer = installer
    }

    // MARK: - Derived state

    var isBusy: Bool {
        if case .working = state { return true }
        return false
    }

    var statusMessage: String? {
        switch state {
        case .idle, .working:
            return nil
        case .success(let message):
            return message
        case .failure(let message):
            return message
        }
    }

    var isErrorMessage: Bool {
        if case .failure = state { return true }
        return false
    }

    var statusCallout: StatusCallout? {
        switch state {
        case .idle, .working:
            return nil
        case .success(let message):
            return StatusCallout(kind: .success, message: message)
        case .failure(let message):
            if case .appManagementDenied = lastError,
               let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles") {
                return StatusCallout(
                    kind: .error,
                    message: message,
                    action: CalloutAction(title: "Open System Settings", url: url)
                )
            }
            return StatusCallout(kind: .error, message: message)
        }
    }

    var isAnyInstalled: Bool {
        installations.contains { $0.isInstalled }
    }

    var canInstall: Bool {
        !installations.isEmpty
    }

    // MARK: - Actions

    func refresh() {
        installations = detector.detect()
    }

    func install() {
        guard !installations.isEmpty else { return }
        state = .working
        let currentInstallations = installations
        let installer = self.installer
        Task.detached { [weak self] in
            do {
                for installation in currentInstallations where !installation.isInstalled {
                    try installer.install(to: installation)
                }
                await MainActor.run {
                    guard let self = self else { return }
                    self.refresh()
                    self.lastError = nil
                    self.state = .success("Installation complete.")
                }
            } catch {
                let nimoError = error as? NimoError
                let message = nimoError?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard let self = self else { return }
                    self.refresh()
                    self.lastError = nimoError
                    self.state = .failure(message)
                }
            }
        }
    }

    func uninstall() {
        guard !installations.isEmpty else { return }
        state = .working
        let currentInstallations = installations
        let installer = self.installer
        Task.detached { [weak self] in
            do {
                for installation in currentInstallations where installation.isInstalled {
                    try installer.uninstall(from: installation)
                }
                await MainActor.run {
                    guard let self = self else { return }
                    self.refresh()
                    self.lastError = nil
                    self.state = .success("Uninstall complete.")
                }
            } catch {
                let nimoError = error as? NimoError
                let message = nimoError?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard let self = self else { return }
                    self.refresh()
                    self.lastError = nimoError
                    self.state = .failure(message)
                }
            }
        }
    }
}
