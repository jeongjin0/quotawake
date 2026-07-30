import Foundation
import XCTest
@testable import QuotaWakeCLI
@testable import QuotaWakeCore

final class CLIApplicationTests: XCTestCase {
    func testSetupAndStatusUseIsolatedCrossPlatformHome() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let detector = CLIPathDetector(
            homeDirectory: fixture.root,
            commonBinDirectories: [fixture.binDirectory],
            environment: [:]
        )
        let context = QuotaWakeCLIContext(paths: fixture.paths, detector: detector)
        let snapshot = try context.setup(providers: [.claude])

        XCTAssertTrue(snapshot.setupComplete)
        XCTAssertFalse(snapshot.backgroundReadinessEnabled)
        XCTAssertEqual(snapshot.configPath, fixture.paths.settingsFile.path)
        XCTAssertEqual(snapshot.providers.first(where: { $0.provider == "claude" })?.cliStatus, "found")
        XCTAssertEqual(snapshot.providers.first(where: { $0.provider == "codex" })?.enabled, false)
    }

    func testStatusJSONIsStableAndDoesNotExposePrompt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var settings = AppSettings.default
        settings.prompt = "private readiness text"
        try SettingsStore(paths: fixture.paths).save(settings)

        let snapshot = try QuotaWakeCLIContext(paths: fixture.paths).status()
        let json = try CLIJSON.encode(snapshot)

        XCTAssertTrue(json.contains("\"configPath\""))
        XCTAssertFalse(json.contains("private readiness text"))
    }

    func testConfigRejectsUnknownKeysAndParsesBooleans() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let context = QuotaWakeCLIContext(paths: fixture.paths)

        let settings = try context.updateConfiguration(key: "readiness.paused", value: "yes")
        XCTAssertTrue(settings.readiness.paused)
        XCTAssertThrowsError(try context.updateConfiguration(key: "unknown", value: "true"))
    }

    func testSourceVersionMatchesVersionEnvironmentContract() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let environment = try String(
            contentsOf: repositoryRoot.appendingPathComponent("version.env"),
            encoding: .utf8
        )
        let versionLine = try XCTUnwrap(environment.split(separator: "\n").first { $0.hasPrefix("VERSION=") })
        XCTAssertEqual(String(versionLine.dropFirst("VERSION=".count)), QuotaWakeCore.currentVersion)
    }
}

private final class Fixture {
    let root: URL
    let binDirectory: URL
    let paths: QuotaWakePaths

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeCLITests-\(UUID().uuidString)", isDirectory: true)
        binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        paths = QuotaWakePaths(applicationSupportDirectory: root.appendingPathComponent("state", isDirectory: true))
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        #if os(Windows)
        let claude = binDirectory.appendingPathComponent("claude.cmd")
        try "@echo off\r\necho fake claude\r\n".write(to: claude, atomically: true, encoding: .utf8)
        #else
        let claude = binDirectory.appendingPathComponent("claude")
        try "#!/bin/sh\nprintf 'fake claude\\n'\n".write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        #endif
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
