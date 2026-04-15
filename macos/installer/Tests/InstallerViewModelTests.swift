import XCTest
@testable import Nimo

@MainActor
final class InstallerViewModelTests: XCTestCase {

    // MARK: - Stubs

    private final class StubDetector: DiscordDetecting {
        var stubbedInstallations: [DiscordInstallation]
        var callCount: Int = 0

        init(_ installations: [DiscordInstallation]) {
            self.stubbedInstallations = installations
        }

        func detect() -> [DiscordInstallation] {
            callCount += 1
            return stubbedInstallations
        }
    }

    private final class StubInstaller: InstallationPerforming {
        var installHandler: ((DiscordInstallation) throws -> Void)?
        var uninstallHandler: ((DiscordInstallation) throws -> Void)?
        var isInstalledHandler: ((DiscordInstallation) -> Bool)?

        func install(to installation: DiscordInstallation) throws {
            try installHandler?(installation)
        }

        func uninstall(from installation: DiscordInstallation) throws {
            try uninstallHandler?(installation)
        }

        func isInstalled(at installation: DiscordInstallation) -> Bool {
            isInstalledHandler?(installation) ?? false
        }
    }

    private struct StubError: LocalizedError {
        let errorDescription: String?
    }

    // MARK: - Helpers

    private func makeInstallation(installed: Bool = false) -> DiscordInstallation {
        DiscordInstallation(
            edition: .stable,
            appURL: URL(fileURLWithPath: "/tmp/Discord.app"),
            isInstalled: installed
        )
    }

    /// Waits for the view model to leave the .working state.
    private func waitForIdle(_ vm: InstallerViewModel, timeout: TimeInterval = 2.0) async {
        let start = Date()
        while vm.isBusy {
            if Date().timeIntervalSince(start) > timeout { return }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    // MARK: - Tests

    func testRefreshPopulatesInstallations() {
        let installation = makeInstallation()
        let detector = StubDetector([installation])
        let installer = StubInstaller()
        let vm = InstallerViewModel(detector: detector, installer: installer)

        XCTAssertTrue(vm.installations.isEmpty)
        vm.refresh()
        XCTAssertEqual(vm.installations.count, 1)
        XCTAssertEqual(vm.installations.first?.edition, .stable)
        XCTAssertEqual(detector.callCount, 1)
    }

    func testInstallSetsSuccessStateOnHappyPath() async {
        let detector = StubDetector([makeInstallation()])
        let installer = StubInstaller()
        var installCalls = 0
        installer.installHandler = { _ in installCalls += 1 }

        let vm = InstallerViewModel(detector: detector, installer: installer)
        vm.refresh()

        vm.install()
        await waitForIdle(vm)

        XCTAssertEqual(installCalls, 1)
        if case .success = vm.state {
            // ok
        } else {
            XCTFail("Expected .success, got \(vm.state)")
        }
        XCTAssertFalse(vm.isErrorMessage)
        XCTAssertNotNil(vm.statusMessage)
    }

    func testInstallSetsFailureStateOnError() async {
        let detector = StubDetector([makeInstallation()])
        let installer = StubInstaller()
        installer.installHandler = { _ in
            throw StubError(errorDescription: "boom")
        }

        let vm = InstallerViewModel(detector: detector, installer: installer)
        vm.refresh()

        vm.install()
        await waitForIdle(vm)

        if case .failure(let message) = vm.state {
            XCTAssertEqual(message, "boom")
        } else {
            XCTFail("Expected .failure, got \(vm.state)")
        }
        XCTAssertTrue(vm.isErrorMessage)
        XCTAssertEqual(vm.statusMessage, "boom")
    }
}
