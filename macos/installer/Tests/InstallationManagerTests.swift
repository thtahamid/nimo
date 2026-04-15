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
        let macOSDir: URL
        let originalBinaryContents: Data
        let dylibURL: URL
        let launcherURL: URL
    }

    private func makeFixture(originalContents: String = "original-discord-binary") throws -> Fixture {
        let appURL = tempDir.appendingPathComponent("Discord.app", isDirectory: true)
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

        let installation = DiscordInstallation(
            edition: .stable,
            appURL: appURL,
            isInstalled: false
        )
        return Fixture(
            installation: installation,
            macOSDir: macOS,
            originalBinaryContents: originalData,
            dylibURL: dylib,
            launcherURL: launcher
        )
    }

    private func makeManager(
        dylib: URL?,
        launcher: URL?
    ) -> InstallationManager {
        InstallationManager(
            fileManager: fm,
            dylibURLProvider: { dylib },
            launcherURLProvider: { launcher },
            executor: LocalShellExecutor()
        )
    }

    // MARK: - Tests

    func testInstallMovesBinaryAndCopiesDylib() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL)

        try manager.install(to: fx.installation)

        let real = fx.macOSDir.appendingPathComponent("Discord.real")
        let dylibDest = fx.macOSDir.appendingPathComponent("nimo.dylib")
        let launcherDest = fx.macOSDir.appendingPathComponent("Discord")

        XCTAssertTrue(fm.fileExists(atPath: real.path))
        XCTAssertTrue(fm.fileExists(atPath: dylibDest.path))
        XCTAssertTrue(fm.fileExists(atPath: launcherDest.path))

        // Original binary contents should now be in Discord.real.
        let realContents = try Data(contentsOf: real)
        XCTAssertEqual(realContents, fx.originalBinaryContents)

        // Launcher should have 0o755 permissions.
        let attrs = try fm.attributesOfItem(atPath: launcherDest.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.uint16Value, 0o755)
    }

    func testInstallIsIdempotentForBackup() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL)

        try manager.install(to: fx.installation)

        let real = fx.macOSDir.appendingPathComponent("Discord.real")
        let firstRealContents = try Data(contentsOf: real)

        // Running install again must not overwrite Discord.real with the launcher script.
        try manager.install(to: fx.installation)

        let secondRealContents = try Data(contentsOf: real)
        XCTAssertEqual(firstRealContents, secondRealContents)
        XCTAssertEqual(secondRealContents, fx.originalBinaryContents)
    }

    func testUninstallRestoresOriginal() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: fx.dylibURL, launcher: fx.launcherURL)

        try manager.install(to: fx.installation)
        try manager.uninstall(from: fx.installation)

        let binary = fx.macOSDir.appendingPathComponent("Discord")
        let real = fx.macOSDir.appendingPathComponent("Discord.real")
        let dylibDest = fx.macOSDir.appendingPathComponent("nimo.dylib")

        XCTAssertTrue(fm.fileExists(atPath: binary.path))
        XCTAssertFalse(fm.fileExists(atPath: real.path))
        XCTAssertFalse(fm.fileExists(atPath: dylibDest.path))

        let restored = try Data(contentsOf: binary)
        XCTAssertEqual(restored, fx.originalBinaryContents)
    }

    func testInstallFailsWhenDylibMissing() throws {
        let fx = try makeFixture()
        let manager = makeManager(dylib: nil, launcher: fx.launcherURL)

        XCTAssertThrowsError(try manager.install(to: fx.installation)) { error in
            guard case NimoError.bundledDylibMissing = error else {
                XCTFail("Expected .bundledDylibMissing, got \(error)")
                return
            }
        }
    }
}
