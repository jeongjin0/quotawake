import XCTest
@testable import QuotaWakeCore

final class ClaudeQuotaAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_512_800)

    func testObserveParsesClaudeUsageOutputFromBoundedProbe() throws {
        let runner = RecordingClaudeProbeRunner(result: QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: "Current session: 64% used. Resets at 2026-06-29T05:30:00Z.",
            stderr: "",
            startedAt: now,
            endedAt: now
        ))
        let adapter = ClaudeQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/claude"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner,
            parentEnvironment: ["ANTHROPIC_API_KEY": "sk-ant-fake", "PATH": "/bin"]
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.source, .claudeUsageProbe)
        XCTAssertEqual(state.confidence, .exactReset)
        XCTAssertEqual(state.classification, .limitReached(resetAt: try XCTUnwrap(Self.iso.date(from: "2026-06-29T05:30:00Z"))))
        XCTAssertTrue(try XCTUnwrap(runner.lastRequest?.arguments).contains("/usage"))
        XCTAssertNil(runner.lastRequest?.environment["ANTHROPIC_API_KEY"])
    }

    func testObserveClassifiesApiBillingEnvironmentWarning() {
        let runner = RecordingClaudeProbeRunner(result: QuotaProbeResult(
            exitCode: 1,
            timedOut: false,
            stdout: "ANTHROPIC_API_KEY environment variable is set",
            stderr: "",
            startedAt: now,
            endedAt: now
        ))
        let adapter = ClaudeQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/claude"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.classification, .apiBillingEnvPresent)
        XCTAssertEqual(state.confidence, .blocked)
    }

    func testObserveIgnoresNoisyUnrelatedStderrForNormalSuccess() {
        let runner = RecordingClaudeProbeRunner(result: QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: "ok",
            stderr: "warning: redraw failed",
            startedAt: now,
            endedAt: now
        ))
        let adapter = ClaudeQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/claude"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.classification, .sent)
        XCTAssertEqual(state.summary, "ok")
    }

    func testFakeClaudeUsageArtifactsStayOutsideQuotaWakeStateAndLogs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeClaudeArtifactBoundary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        let claudeConfigDirectory = root.appendingPathComponent("claude-config", isDirectory: true)
        let appSupportDirectory = root.appendingPathComponent("QuotaWake", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeConfigDirectory, withIntermediateDirectories: true)

        let fakeClaude = binDirectory.appendingPathComponent("claude", isDirectory: false)
        try Self.fakeClaudeUsageProbe.write(to: fakeClaude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaude.path)

        let paths = QuotaWakePaths(applicationSupportDirectory: appSupportDirectory)
        let adapter = ClaudeQuotaAdapter(
            executableURL: fakeClaude,
            runDirectory: paths.runDirectory,
            runner: QuotaProbeProcessRunner(),
            timeoutSeconds: 3,
            parentEnvironment: [
                "HOME": homeDirectory.path,
                "CLAUDE_CONFIG_DIR": claudeConfigDirectory.path,
                "PATH": "/usr/bin:/bin"
            ]
        )

        let state = adapter.observe(observedAt: now)
        try QuotaWindowStateStore(paths: paths).save(state)
        try RunLogStore(paths: paths, calendar: Self.utcCalendar).append(
            RunLogEntry(
                eventId: "quota-observe-claude-artifact-boundary",
                scheduledAt: now,
                startedAt: now,
                endedAt: now,
                tool: .claude,
                commandPath: fakeClaude.path,
                status: .skippedMissedWindow,
                exitCode: nil,
                durationMs: 0,
                timedOut: false,
                stdoutSummary: state.summary,
                stderrSummary: "",
                prompt: "hi",
                decisionSource: .providerState,
                quotaConfidence: state.confidence,
                skipReason: "quota_observed"
            ),
            pruneReferenceDate: now
        )

        XCTAssertEqual(state.source, .claudeUsageProbe)
        XCTAssertEqual(state.confidence, .exactReset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".claude/projects/private-workspace/session.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeConfigDirectory.appendingPathComponent("session.json").path))

        let persistedQuotaWakeText = try Self.concatenatedFileText(under: appSupportDirectory)
        for rawMarker in Self.rawClaudeArtifactMarkers {
            XCTAssertFalse(persistedQuotaWakeText.contains(rawMarker), "QuotaWake persisted raw Claude artifact marker: \(rawMarker)")
        }
        XCTAssertTrue(persistedQuotaWakeText.contains("<redacted>"))

        let runDirectoryFiles = try FileManager.default.contentsOfDirectory(
            at: paths.runDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(runDirectoryFiles.isEmpty)
    }

    private static let iso = ISO8601DateFormatter()

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let rawClaudeArtifactMarkers = [
        "PRIVATE_TRANSCRIPT_MARKER",
        "019f0b09-52c1-7443-bc80-0bdde9c5d918",
        "raw-claude-token-123",
        "raw-config-token-456",
        "/private-workspace/session.jsonl"
    ]

    private static let fakeClaudeUsageProbe = """
    #!/bin/sh
    set -eu
    mkdir -p "$HOME/.claude/projects/private-workspace" "$CLAUDE_CONFIG_DIR"
    printf '%s\\n' '{"transcript":"PRIVATE_TRANSCRIPT_MARKER","session_id":"019f0b09-52c1-7443-bc80-0bdde9c5d918","token":"raw-claude-token-123"}' > "$HOME/.claude/projects/private-workspace/session.jsonl"
    printf '%s\\n' '{"token":"raw-config-token-456","project":"/private-workspace/session.jsonl"}' > "$CLAUDE_CONFIG_DIR/session.json"
    printf '%s\\n' 'Current session: 64% used. Resets at 2026-06-29T05:30:00Z.'
    printf '%s\\n' 'session_id=019f0b09-52c1-7443-bc80-0bdde9c5d918 transcript: PRIVATE_TRANSCRIPT_MARKER project: /private-workspace/session.jsonl token=raw-claude-token-123'
    """

    private static func concatenatedFileText(under root: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        var text = ""
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            text += try String(contentsOf: fileURL, encoding: .utf8)
        }
        return text
    }
}

private final class RecordingClaudeProbeRunner: QuotaProbeRunning {
    let result: QuotaProbeResult
    private(set) var lastRequest: QuotaProbeRequest?

    init(result: QuotaProbeResult) {
        self.result = result
    }

    func run(_ request: QuotaProbeRequest) throws -> QuotaProbeResult {
        lastRequest = request
        return result
    }
}
