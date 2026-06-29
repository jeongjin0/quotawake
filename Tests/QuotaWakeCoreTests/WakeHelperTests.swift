import XCTest
@testable import QuotaWakeCore

final class WakeHelperTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testRequestStoreWritesTimestampAndClearsFile() throws {
        let fixture = try makeFixture()
        let store = WakeRequestStore(requestFile: fixture.configuration.requestFile, calendar: Self.utcCalendar)

        let timestamp = try store.writeWakeRequest(at: date(2026, 6, 28, 6, 50))
        XCTAssertEqual(timestamp, "06/28/26 06:50:00")
        XCTAssertTrue(WakeRequestStore.isValidTimestamp(timestamp))
        XCTAssertEqual(try read(fixture.configuration.requestFile), timestamp)

        try store.clearWakeRequest()
        XCTAssertEqual(try read(fixture.configuration.requestFile), "")
    }

    func testRendererCreatesValidPlistAndHelperScript() throws {
        let fixture = try makeFixture()
        let renderer = WakeHelperRenderer()
        let plistData = try renderer.renderLaunchDaemonPlist(configuration: fixture.configuration)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])

        XCTAssertEqual(plist["Label"] as? String, fixture.configuration.label)
        XCTAssertEqual(plist["WatchPaths"] as? [String], [fixture.configuration.requestFile.path])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [fixture.configuration.rootHelper.path])
        XCTAssertEqual(plist["StandardOutPath"] as? String, fixture.configuration.logFile.path)
        XCTAssertEqual(plist["StandardErrorPath"] as? String, fixture.configuration.logFile.path)
        XCTAssertFalse(fixture.configuration.logFile.path.hasPrefix("/tmp/"))
        XCTAssertTrue(fixture.configuration.logFile.path.hasPrefix("/var/log/quotawake/"))

        let script = renderer.renderHelperScript(configuration: fixture.configuration)
        XCTAssertTrue(script.contains("LOG_FILE='\(fixture.configuration.logFile.path)'"))
        XCTAssertFalse(script.contains("/tmp/"))
        XCTAssertTrue(script.contains(#"/usr/bin/pmset schedule cancel wake "$OLD""#))
        XCTAssertTrue(script.contains(#"/usr/bin/pmset schedule wake "$WHEN""#))
        assertNoForbiddenCommands(in: script)
    }

    func testInstallerPlanEscapesPathsAndRollsBackOnlyQuotaWakeFiles() throws {
        let fixture = try makeFixture(rootName: "QuotaWake Wake 'Quoted'")
        let installer = WakeHelperInstaller()
        let plan = try installer.renderInstallPlan(configuration: fixture.configuration)

        XCTAssertTrue(plan.adminInstallScript.contains("write_embedded"))
        XCTAssertTrue(plan.adminInstallScript.contains("cleanup"))
        XCTAssertTrue(plan.adminInstallScript.contains("/bin/mkdir -p"))
        XCTAssertTrue(plan.adminInstallScript.contains("'/var/log/quotawake'"))
        XCTAssertFalse(plan.adminInstallScript.contains("/tmp/"))
        XCTAssertTrue(plan.adminInstallScript.contains("/bin/rm -f '\(fixture.configuration.rootHelper.path)' '\(fixture.configuration.rootPlist.path)'"))
        XCTAssertTrue(plan.adminInstallScript.contains("/bin/launchctl bootstrap system"))
        XCTAssertEqual(plan.osascriptArguments.first, "-e")
        XCTAssertTrue(plan.osascriptArguments.contains("do shell script item 1 of argv with administrator privileges"))
        XCTAssertEqual(plan.osascriptArguments.last, plan.adminInstallScript)
        try assertOSAScriptCanReceiveInstallScript(plan.adminInstallScript)
        assertNoForbiddenCommands(in: plan.adminInstallScript)
    }

    func testInstallerPlanDoesNotTrustMutableStagedFilesForRootInstall() throws {
        let fixture = try makeFixture()
        let plan = try WakeHelperInstaller().renderInstallPlan(configuration: fixture.configuration)
        let renderer = WakeHelperRenderer()
        let expectedHelper = Data(renderer.renderHelperScript(configuration: fixture.configuration).utf8)
            .base64EncodedString()
        let expectedPlist = try renderer.renderLaunchDaemonPlist(configuration: fixture.configuration)
            .base64EncodedString()

        XCTAssertFalse(plan.adminInstallScript.contains(fixture.configuration.stagedHelper.path))
        XCTAssertFalse(plan.adminInstallScript.contains(fixture.configuration.stagedPlist.path))
        XCTAssertFalse(plan.adminInstallScript.contains("/bin/cp"))
        XCTAssertTrue(plan.adminInstallScript.contains(expectedHelper))
        XCTAssertTrue(plan.adminInstallScript.contains(expectedPlist))
    }

    func testInstallStagesFilesThenRunsOSAScriptArguments() throws {
        let fixture = try makeFixture()
        let installer = WakeHelperInstaller()
        var capturedArguments: [String]?

        let plan = try installer.install(configuration: fixture.configuration) { arguments in
            capturedArguments = arguments
        }

        XCTAssertEqual(capturedArguments, plan.osascriptArguments)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.configuration.stagedHelper.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.configuration.stagedPlist.path))
    }

    func testUninstallPlanCancelsOnlyExactLastWakeAndRemovesQuotaWakeFiles() throws {
        let fixture = try makeFixture()
        let plan = try WakeHelperInstaller().renderInstallPlan(configuration: fixture.configuration)

        XCTAssertTrue(plan.adminUninstallScript.contains(#"/usr/bin/pmset schedule cancel wake "$OLD""#))
        XCTAssertTrue(plan.adminUninstallScript.contains(fixture.configuration.rootPlist.path))
        XCTAssertTrue(plan.adminUninstallScript.contains(fixture.configuration.rootHelper.path))
        XCTAssertTrue(plan.adminUninstallScript.contains(fixture.configuration.rootLastWakeFile.path))
        assertNoForbiddenCommands(in: plan.adminUninstallScript)
    }

    func testTimestampValidationRejectsInjection() throws {
        XCTAssertFalse(WakeRequestStore.isValidTimestamp("06/28/26 06:50:00; rm -rf /"))
        XCTAssertFalse(WakeRequestStore.isValidTimestamp("$(touch /tmp/owned)"))
        XCTAssertFalse(WakeRequestStore.isValidTimestamp("06/28/2026 06:50:00"))

        let fixture = try makeFixture()
        let script = WakeHelperRenderer().renderHelperScript(configuration: fixture.configuration)
        XCTAssertFalse(script.contains("rm -rf"))
        assertNoForbiddenCommands(in: script)
    }

    func testWakeCoordinatorWritesLeadRequestOnlyWhenEnabledAndInstalled() throws {
        let fixture = try makeFixture()
        let store = WakeRequestStore(requestFile: fixture.configuration.requestFile, calendar: Self.utcCalendar)
        let coordinator = WakeCoordinator(store: store, calendar: Self.utcCalendar)
        let nextRun = date(2026, 6, 28, 7, 0)

        let timestamp = try coordinator.updateWakeRequest(
            nextRun: nextRun,
            settings: WakeSettings(enabled: true, leadMinutes: 10, helperInstalled: true)
        )
        XCTAssertEqual(timestamp, "06/28/26 06:50:00")
        XCTAssertEqual(try read(fixture.configuration.requestFile), "06/28/26 06:50:00")

        let cleared = try coordinator.updateWakeRequest(
            nextRun: nextRun,
            settings: WakeSettings(enabled: false, leadMinutes: 10, helperInstalled: true)
        )
        XCTAssertNil(cleared)
        XCTAssertEqual(try read(fixture.configuration.requestFile), "")
    }

    func testInstallerStagesPlistAndHelperFiles() throws {
        let fixture = try makeFixture()
        let installer = WakeHelperInstaller()
        try installer.stageFiles(configuration: fixture.configuration)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.configuration.stagedHelper.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.configuration.stagedPlist.path))
        _ = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: fixture.configuration.stagedPlist),
            format: nil
        )

        if let evidenceDirectory = ProcessInfo.processInfo.environment["QUOTAWAKE_WAKE_EVIDENCE_DIR"] {
            let evidenceURL = URL(fileURLWithPath: evidenceDirectory, isDirectory: true)
            let evidencePaths = QuotaWakePaths(
                applicationSupportDirectory: evidenceURL.appendingPathComponent("ApplicationSupport", isDirectory: true)
            )
            let evidenceConfiguration = WakeHelperConfiguration(uid: 501, paths: evidencePaths)
            try FileManager.default.createDirectory(at: evidenceURL, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: evidenceURL.appendingPathComponent("wake-helper.plist"))
            try? FileManager.default.removeItem(at: evidenceURL.appendingPathComponent("wake-helper.sh"))
            try installer.stageFiles(configuration: evidenceConfiguration)
            let evidencePlan = try installer.renderInstallPlan(configuration: evidenceConfiguration)
            try FileManager.default.copyItem(
                at: evidenceConfiguration.stagedPlist,
                to: evidenceURL.appendingPathComponent("wake-helper.plist")
            )
            try FileManager.default.copyItem(
                at: evidenceConfiguration.stagedHelper,
                to: evidenceURL.appendingPathComponent("wake-helper.sh")
            )
            try evidencePlan.adminInstallScript.write(
                to: evidenceURL.appendingPathComponent("admin-install.sh"),
                atomically: true,
                encoding: .utf8
            )
            try evidencePlan.adminUninstallScript.write(
                to: evidenceURL.appendingPathComponent("admin-uninstall.sh"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func makeFixture(rootName: String = "QuotaWakeWakeHelperTests") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(rootName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempDirectories.append(root)
        let paths = QuotaWakePaths(applicationSupportDirectory: root.appendingPathComponent("ApplicationSupport", isDirectory: true))
        return Fixture(configuration: WakeHelperConfiguration(uid: 501, paths: paths))
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Self.utcCalendar.date(from: DateComponents(
            calendar: Self.utcCalendar,
            timeZone: Self.utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ))!
    }

    private func assertNoForbiddenCommands(in text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(text.contains("pmset schedule cancelall"), file: file, line: line)
        XCTAssertFalse(text.contains("pmset repeat"), file: file, line: line)
        XCTAssertFalse(text.contains("claude"), file: file, line: line)
        XCTAssertFalse(text.contains("codex"), file: file, line: line)
    }

    private func assertOSAScriptCanReceiveInstallScript(
        _ script: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript", isDirectory: false)
        process.arguments = [
            "-e",
            "on run argv",
            "-e",
            "return item 1 of argv",
            "-e",
            "end run",
            script
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, errorOutput, file: file, line: line)
        XCTAssertEqual(output, script.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private struct Fixture {
        let configuration: WakeHelperConfiguration
    }
}
