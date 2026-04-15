import XCTest
@testable import Nimo

final class DiscordDetectorTests: XCTestCase {
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

    /// Creates a fake Discord.app bundle skeleton at `searchDir/bundleName` and writes a stub `Discord`
    /// executable. Returns the `Contents/MacOS` directory URL.
    @discardableResult
    private func createFakeBundle(
        in searchDir: URL,
        bundleName: String,
        writeDiscordBinary: Bool = true
    ) throws -> URL {
        let app = searchDir.appendingPathComponent(bundleName, isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        if writeDiscordBinary {
            let binary = macOS.appendingPathComponent("Discord")
            try Data("#!/bin/sh\necho discord\n".utf8).write(to: binary)
        }
        return macOS
    }

    // MARK: - Tests

    func testDetectsDiscordStableInSearchDir() throws {
        try createFakeBundle(in: tempDir, bundleName: "Discord.app")

        let detector = DiscordDetector(fileManager: fm, searchDirectories: [tempDir])
        let results = detector.detect()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.edition, .stable)
        XCTAssertEqual(results.first?.isInstalled, false)
    }

    func testDetectsMultipleEditions() throws {
        try createFakeBundle(in: tempDir, bundleName: "Discord.app")
        try createFakeBundle(in: tempDir, bundleName: "Discord Canary.app")
        try createFakeBundle(in: tempDir, bundleName: "Discord PTB.app")

        let detector = DiscordDetector(fileManager: fm, searchDirectories: [tempDir])
        let results = detector.detect()

        XCTAssertEqual(results.count, 3)
        let editions = Set(results.map { $0.edition })
        XCTAssertEqual(editions, Set([.stable, .canary, .ptb]))
    }

    func testReturnsEmptyWhenNoneFound() {
        let detector = DiscordDetector(fileManager: fm, searchDirectories: [tempDir])
        XCTAssertTrue(detector.detect().isEmpty)
    }

    func testSkipsBundlesWithoutDiscordBinary() throws {
        try createFakeBundle(in: tempDir, bundleName: "Discord.app", writeDiscordBinary: false)

        let detector = DiscordDetector(fileManager: fm, searchDirectories: [tempDir])
        XCTAssertTrue(detector.detect().isEmpty)
    }
}
