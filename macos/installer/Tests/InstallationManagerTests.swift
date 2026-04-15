import XCTest
@testable import Nimo

final class InstallationManagerTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir, fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private struct Fixture {
        let installation: DiscordInstallation
        let sourceMacOSDir: URL
        let wrapperParent: URL
        let originalBinaryContents: Data
        let dylibURL: URL
        let launcherURL: URL
    }

    private func makeFixture(originalContents: String = "original-discord-binary") throws -> Fixture {
        let sourceApps = tempDir.appendingPathComponent("source-apps", isDirectory: true)
        try fm.createDirectory(at: sourceApps, withIntermediateDirectories: true)
        let appURL = sourceApps.appendingPathComponent("Discord.app", isDirectory: true)
        let macOS = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)

        let binary = macOS.appendingPathComponent("Discord")
        let originalData = Data(originalContents.utf8)
        try originalData.write(to: binary)

        let dylib = tempDir.appendingPathComponent("nimo.dylib")
        try Data("fake dylib contents".utf8).write(to: dylib)

        let launcher = tempDir.appendingPathComponent("launcher.sh")
        let launcherText = """
        #!/bin/bash
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        export DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/nimo.dylib"
        exec "$SCRIPT_DIR/Discord.real" "$@"
        """
        try Data(launcherText.utf8).write(to: launcher)

        let wrapperParent = tempDir.appendingPathComponent("user-apps", isDirectory: true)

        let installation = DiscordInstallation(
            edition: .stable,
            appURL: appURL,
            isInstalled: false
        )
        return Fixture(
            installation: installation,
            sourceMacOSDir: macOS,
            wrapperParent: wrapperParent,
            originalBinaryContents: originalData,
            dylibURL: dylib,
            launcherURL: launcher
        )
    }

    private func makeManager(
        dylib: URL?,
        launcher: URL?,
        wrapperParent: URL
    ) -> InstallationManager {
        InstallationManager(
            fileManager: fm,
            dylibURLProvider: { dylib },
            launcherURLProvider: { launcher },
            codesign: { _ in },
            wrapperParentURL: wrapperParent
        )
    }

    // MARK: - Tests

    func testInstallCreatesWrapperWithLauncherAndDylib() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL, wrapperParent: fx.wrapperParent)

        try manager.install(to: fx.installation)

        let wrapper = fx.wrapperParent.appendingPathComponent("Discord (Nimo).app")
        let macOS = wrapper.appendingPathComponent("Contents/MacOS")
        let real = macOS.appendingPathComponent("Discord.real")
        let dylibDest = macOS.appendingPathComponent("nimo.dylib")
        let launcherDest = macOS.appendingPathComponent("Discord")

        XCTAssertTrue(fm.fileExists(atPath: wrapper.path))
        XCTAssertTrue(fm.fileExists(atPath: real.path))
        XCTAssertTrue(fm.fileExists(atPath: dylibDest.path))
        XCTAssertTrue(fm.fileExists(atPath: launcherDest.path))

        // Discord.real contains the original binary bytes.
        let realContents = try Data(contentsOf: real)
        XCTAssertEqual(realContents, fx.originalBinaryContents)

        // Launcher is executable (0o755).
        let attrs = try fm.attributesOfItem(atPath: launcherDest.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.uint16Value, 0o755)
    }

    func testInstallLeavesOriginalBundleUntouched() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL, wrapperParent: fx.wrapperParent)

        try manager.install(to: fx.installation)

        // Source /Applications-style bundle is unchanged.
        let sourceDiscord = fx.sourceMacOSDir.appendingPathComponent("Discord")
        XCTAssertTrue(fm.fileExists(atPath: sourceDiscord.path))
        XCTAssertFalse(fm.fileExists(atPath: fx.sourceMacOSDir.appendingPathComponent("Discord.real").path))
        XCTAssertFalse(fm.fileExists(atPath: fx.sourceMacOSDir.appendingPathComponent("nimo.dylib").path))
        XCTAssertEqual(try Data(contentsOf: sourceDiscord), fx.originalBinaryContents)
    }

    func testInstallIsIdempotent() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL, wrapperParent: fx.wrapperParent)

        try manager.install(to: fx.installation)
        try manager.install(to: fx.installation)

        let wrapper = fx.wrapperParent.appendingPathComponent("Discord (Nimo).app")
        let real = wrapper.appendingPathComponent("Contents/MacOS/Discord.real")
        let realContents = try Data(contentsOf: real)
        XCTAssertEqual(realContents, fx.originalBinaryContents)
    }

    func testUninstallRemovesWrapperOnly() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL, wrapperParent: fx.wrapperParent)

        try manager.install(to: fx.installation)
        try manager.uninstall(from: fx.installation)

        let wrapper = fx.wrapperParent.appendingPathComponent("Discord (Nimo).app")
        XCTAssertFalse(fm.fileExists(atPath: wrapper.path))

        // Original bundle still intact.
        XCTAssertTrue(fm.fileExists(atPath: fx.sourceMacOSDir.appendingPathComponent("Discord").path))
    }

    func testIsInstalledReflectsWrapperState() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL, wrapperParent: fx.wrapperParent)

        XCTAssertFalse(manager.isInstalled(at: fx.installation))

        try manager.install(to: fx.installation)
        XCTAssertTrue(manager.isInstalled(at: fx.installation))

        try manager.uninstall(from: fx.installation)
        XCTAssertFalse(manager.isInstalled(at: fx.installation))
    }

    func testInstallFailsWhenDylibMissing() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: nil, launcher: fx.launcherURL, wrapperParent: fx.wrapperParent)

        XCTAssertThrowsError(try manager.install(to: fx.installation)) { error in
            guard case NimoError.bundledDylibMissing = error else {
                XCTFail("Expected .bundledDylibMissing, got \(error)")
                return
            }
        }
    }
}
