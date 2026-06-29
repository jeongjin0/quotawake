import XCTest
@testable import QuotaWakeCore

final class SettingsAndLogsTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testDefaultSettingsMatchMVPContract() {
        let settings = AppSettings.default

        XCTAssertGreaterThanOrEqual(settings.schemaVersion, 2)
        XCTAssertFalse(settings.firstRunCompleted)
        XCTAssertEqual(settings.prompt, "hi")
        XCTAssertTrue(settings.tools.claude.enabled)
        XCTAssertTrue(settings.tools.codex.enabled)
        XCTAssertNil(settings.tools.claude.manualPath)
        XCTAssertNil(settings.tools.codex.manualPath)
        XCTAssertTrue(settings.schedule.weekdays.isEmpty)
        XCTAssertTrue(settings.schedule.times.isEmpty)
        XCTAssertTrue(settings.schedule.paused)
        XCTAssertFalse(settings.background.launchAtLoginEnabled)
        XCTAssertFalse(settings.wake.enabled)
        XCTAssertFalse(settings.wake.helperInstalled)
        XCTAssertTrue(settings.readiness.activeOnly)
        XCTAssertEqual(settings.readiness.idleThresholdSeconds, 300)
        XCTAssertEqual(settings.readiness.minimumSendCooldownMinutes, 30)
        XCTAssertEqual(settings.readiness.resetEstimationMode, .localSignalsOnly)
    }

    func testLegacyV1SettingsFixtureMigratesScheduleWakeOutOfActiveModel() throws {
        let data = Self.legacySettingsFixture.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertGreaterThanOrEqual(settings.schemaVersion, 2)
        XCTAssertTrue(settings.firstRunCompleted)
        XCTAssertEqual(settings.prompt, "ready")
        XCTAssertEqual(settings.tools.claude.manualPath, "/usr/local/bin/claude")
        XCTAssertEqual(settings.tools.codex.manualPath, "/opt/homebrew/bin/codex")
        XCTAssertTrue(settings.background.launchAtLoginEnabled)
        XCTAssertTrue(settings.schedule.weekdays.isEmpty)
        XCTAssertTrue(settings.schedule.times.isEmpty)
        XCTAssertTrue(settings.schedule.paused)
        XCTAssertFalse(settings.wake.enabled)
        XCTAssertFalse(settings.wake.helperInstalled)
        XCTAssertNil(settings.wake.lastRequestedWake)
    }

    func testSettingsStoreMigratesLegacyFixtureAndSavesWithoutLegacyScheduleWakeKeys() throws {
        let paths = try makePaths()
        try Self.legacySettingsFixture.write(to: paths.settingsFile, atomically: true, encoding: .utf8)
        let store = SettingsStore(paths: paths)

        let migrated = try store.load()
        try store.save(migrated)
        let saved = try String(contentsOf: paths.settingsFile, encoding: .utf8)

        XCTAssertGreaterThanOrEqual(migrated.schemaVersion, 2)
        XCTAssertFalse(saved.contains("\"schedule\""))
        XCTAssertFalse(saved.contains("\"wake\""))
        XCTAssertTrue(saved.contains("\"readiness\""))
    }

    func testSettingsStoreRoundTripsWithAtomicWrite() throws {
        let paths = try makePaths()
        let store = SettingsStore(paths: paths)

        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.prompt = "ready"
        settings.tools[.codex].manualPath = "/opt/homebrew/bin/codex"
        settings.background.launchAtLoginEnabled = true
        settings.readiness.idleThresholdSeconds = 120

        try store.save(settings)

        XCTAssertEqual(try store.load(), settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.settingsFile.path))

        let supportFiles = try FileManager.default.contentsOfDirectory(
            at: paths.applicationSupportDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(supportFiles.contains { $0.lastPathComponent.hasSuffix(".tmp") })
    }

    func testRunLogStoreRedactsAndTruncatesSensitiveOutput() throws {
        let paths = try makePaths()
        let store = RunLogStore(paths: paths, calendar: Self.utcCalendar)
        let longText = String(repeating: "x", count: 5_000)

        try store.append(
            makeEntry(
                stdoutSummary: "Authorization: Bearer abc\n\(longText)",
                stderrSummary: "session id: 019f0b09-52c1-7443-bc80-0bdde9c5d918",
                errorSummary: "password leaked"
            ),
            pruneReferenceDate: Self.referenceDate
        )

        let entries = try store.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].stdoutSummary.contains("Bearer abc"))
        XCTAssertFalse(entries[0].stderrSummary.contains("019f0b09"))
        XCTAssertFalse(entries[0].errorSummary?.contains("password") ?? true)
        XCTAssertTrue(entries[0].stdoutSummary.contains("[REDACTED]"))
        XCTAssertEqual(entries[0].stdoutSummary.count, RunLogSanitizer.summaryLimit)
        XCTAssertEqual(entries[0].stderrSummary, "session id: [REDACTED]")
        XCTAssertEqual(entries[0].errorSummary, "[REDACTED]")
    }

    func testRunLogSanitizerRedactsBareProviderSecretsAndSessionIds() {
        let sanitized = RunLogSanitizer.sanitize("""
        provider emitted sk-ant-admin01 and continued
        generic token sk-proj-abcdefghijklmnopqrstuvwxyz is hidden
        session_id=019f0b09-52c1-7443-bc80-0bdde9c5d918 after retry
        sessionId: sess_abc123xyz next
        session id 0123456789abcdef final
        normal readiness output stays visible
        """)

        XCTAssertFalse(sanitized.contains("sk-ant-admin01"))
        XCTAssertFalse(sanitized.contains("sk-proj-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(sanitized.contains("019f0b09-52c1-7443-bc80-0bdde9c5d918"))
        XCTAssertFalse(sanitized.contains("sess_abc123xyz"))
        XCTAssertFalse(sanitized.contains("0123456789abcdef"))
        XCTAssertTrue(sanitized.contains("provider emitted [REDACTED] and continued"))
        XCTAssertTrue(sanitized.contains("generic token [REDACTED] is hidden"))
        XCTAssertTrue(sanitized.contains("session_id=[REDACTED] after retry"))
        XCTAssertTrue(sanitized.contains("sessionId: [REDACTED] next"))
        XCTAssertTrue(sanitized.contains("session id [REDACTED] final"))
        XCTAssertTrue(sanitized.contains("normal readiness output stays visible"))
    }

    func testRunLogStorePrunesOnlyLastThirtyLocalLogDays() throws {
        let paths = try makePaths()
        let store = RunLogStore(paths: paths, calendar: Self.utcCalendar)

        for offset in stride(from: 30, through: 0, by: -1) {
            let date = try XCTUnwrap(Self.utcCalendar.date(
                byAdding: .day,
                value: -offset,
                to: Self.referenceDate
            ))
            try store.append(makeEntry(id: "event-\(offset)", startedAt: date), pruneReferenceDate: Self.referenceDate)
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .sorted()

        XCTAssertEqual(files.count, 30)
        XCTAssertFalse(files.contains("2026-05-28.jsonl"))
        XCTAssertEqual(files.first, "2026-05-29.jsonl")
        XCTAssertEqual(files.last, "2026-06-27.jsonl")
        XCTAssertEqual(try store.readAll().count, 30)
    }

    private func makePaths() throws -> QuotaWakePaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempDirectories.append(root)
        return QuotaWakePaths(applicationSupportDirectory: root)
    }

    private func makeEntry(
        id: String = "event",
        startedAt: Date = referenceDate,
        stdoutSummary: String = "ok",
        stderrSummary: String = "",
        errorSummary: String? = nil
    ) -> RunLogEntry {
        RunLogEntry(
            eventId: id,
            scheduledAt: startedAt,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1),
            tool: .claude,
            commandPath: "/usr/local/bin/claude",
            status: .sent,
            exitCode: 0,
            durationMs: 1_000,
            timedOut: false,
            stdoutSummary: stdoutSummary,
            stderrSummary: stderrSummary,
            prompt: "hi",
            errorSummary: errorSummary
        )
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_782_518_400)

    private static let legacySettingsFixture = """
    {
      "schemaVersion": 1,
      "firstRunCompleted": true,
      "prompt": "ready",
      "tools": {
        "claude": { "enabled": true, "manualPath": "/usr/local/bin/claude" },
        "codex": { "enabled": true, "manualPath": "/opt/homebrew/bin/codex" }
      },
      "schedule": {
        "paused": false,
        "weekdays": [2, 3, 4, 5, 6],
        "times": [{ "hour": 6, "minute": 0 }],
        "missedRunGraceMinutes": 15
      },
      "background": { "launchAtLoginEnabled": true },
      "wake": {
        "enabled": true,
        "leadMinutes": 10,
        "helperInstalled": true,
        "lastRequestedWake": "2026-06-28T05:50:00Z"
      }
    }
    """
}
