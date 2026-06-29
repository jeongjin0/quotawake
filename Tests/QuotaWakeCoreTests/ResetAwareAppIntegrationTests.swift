import XCTest
@testable import QuotaWakeCore

#if canImport(Darwin)
import Darwin
#endif

final class ResetAwareAppIntegrationTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testSendNowLimitOutputUpdatesQuotaStateAndIdlePollSkipsWithoutExecutingProvider() throws {
        let fixture = try makeFixture()
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.claude.enabled = false
        settings.tools.codex.enabled = true
        settings.readiness.activeOnly = true
        settings.readiness.idleThresholdSeconds = 300
        try fixture.settingsStore.save(settings)

        let resetAt = Self.date("2026-06-28T23:50:00Z")
        let runner = RecordingToolRunner(results: [
            .codex: Self.runEntry(
                eventId: "manual-send-now-codex",
                status: .failed,
                timedOut: false,
                stderrSummary: "Usage limit reached. Resets at \(Self.iso.string(from: resetAt)). sk-proj-abcdefghijklmnop",
                errorSummary: "CLI exited with code 1"
            )
        ])
        let poller = QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: { [fixture.command] },
            runner: runner,
            activityEvaluator: SequenceActivityEvaluator([.idle(seconds: 360)]),
            now: { Self.now }
        )

        try poller.sendNow()
        XCTAssertEqual(runner.requests.count, 1)
        let state = try XCTUnwrap(fixture.quotaStateStore.load(tool: .codex))
        XCTAssertEqual(state.confidence, .exactReset)
        XCTAssertEqual(state.resetAt, resetAt)
        XCTAssertFalse(state.summary.contains("sk-proj-abcdefghijklmnop"))

        try poller.tick()
        XCTAssertEqual(runner.requests.count, 1, "Idle poll must not execute the fake provider")
        let logs = try fixture.logStore.readAll()
        XCTAssertEqual(logs.map(\.eventId), ["manual-send-now-codex", "reset-window-codex-2026-06-28T23:50:00Z"])
        XCTAssertEqual(logs.last?.status, .skippedMissedWindow)
        XCTAssertEqual(logs.last?.decisionSource, .activityGate)
        XCTAssertEqual(logs.last?.quotaConfidence, .exactReset)
        XCTAssertEqual(logs.last?.skipReason, "idle")
    }

    func testRapidTicksForSameResetWindowSendOnceThenLogDuplicateSkip() throws {
        let fixture = try makeFixture()
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.claude.enabled = false
        settings.tools.codex.enabled = true
        settings.readiness.activeOnly = true
        settings.readiness.minimumSendCooldownMinutes = 0
        try fixture.settingsStore.save(settings)
        try fixture.quotaStateStore.save(QuotaWindowState(
            tool: .codex,
            source: .cliMessageParser,
            confidence: .exactReset,
            classification: .limitReached(resetAt: Self.now),
            observedAt: Self.now.addingTimeInterval(-60),
            resetAt: Self.now,
            summary: "limit reset due"
        ))

        let runner = RecordingToolRunner(results: [
            .codex: Self.runEntry(
                status: .sent,
                timedOut: false,
                stdoutSummary: "ok",
                errorSummary: nil
            )
        ])
        let poller = QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: { [fixture.command] },
            runner: runner,
            activityEvaluator: SequenceActivityEvaluator([.active, .active]),
            now: { Self.now }
        )

        try poller.tick()
        try fixture.quotaStateStore.save(QuotaWindowState(
            tool: .codex,
            source: .cliMessageParser,
            confidence: .exactReset,
            classification: .limitReached(resetAt: Self.now),
            observedAt: Self.now,
            resetAt: Self.now,
            summary: "same reset still present"
        ))
        try poller.tick()

        XCTAssertEqual(runner.requests.count, 1)
        let logs = try fixture.logStore.readAll()
        XCTAssertEqual(logs.filter { $0.status == .sent }.count, 1)
        XCTAssertEqual(logs.last?.status, .skippedMissedWindow)
        XCTAssertEqual(logs.last?.decisionSource, .idempotency)
        XCTAssertEqual(logs.last?.skipReason, "duplicate_reset_window")
    }

    func testFailedAndTimedOutResetWindowAttemptsPreventImmediateRetry() throws {
        for attempt in [(RunStatus.failed, false), (.timedOut, true)] {
            let fixture = try makeFixture()
            var settings = AppSettings.default
            settings.firstRunCompleted = true
            settings.tools.claude.enabled = false
            settings.tools.codex.enabled = true
            settings.readiness.activeOnly = true
            settings.readiness.minimumSendCooldownMinutes = 0
            try fixture.settingsStore.save(settings)
            try fixture.quotaStateStore.save(QuotaWindowState(
                tool: .codex,
                source: .cliMessageParser,
                confidence: .exactReset,
                classification: .limitReached(resetAt: Self.now),
                observedAt: Self.now.addingTimeInterval(-60),
                resetAt: Self.now,
                summary: "limit reset due"
            ))

            let runner = RecordingToolRunner(results: [
                .codex: Self.runEntry(status: attempt.0, timedOut: attempt.1)
            ])
            let poller = QuotaReadinessPoller(
                paths: fixture.paths,
                settingsStore: fixture.settingsStore,
                logStore: fixture.logStore,
                quotaStateStore: fixture.quotaStateStore,
                commandsProvider: { [fixture.command] },
                runner: runner,
                activityEvaluator: SequenceActivityEvaluator([.active, .active]),
                now: { Self.now }
            )

            try poller.tick()
            try fixture.quotaStateStore.save(QuotaWindowState(
                tool: .codex,
                source: .cliMessageParser,
                confidence: .exactReset,
                classification: .limitReached(resetAt: Self.now),
                observedAt: Self.now,
                resetAt: Self.now,
                summary: "same reset still present"
            ))
            try poller.tick()

            XCTAssertEqual(runner.requests.count, 1, "\(attempt.0) should count as a provider attempt")
            let logs = try fixture.logStore.readAll()
            XCTAssertEqual(logs.last?.status, .skippedMissedWindow)
            XCTAssertEqual(logs.last?.decisionSource, .idempotency)
            XCTAssertEqual(logs.last?.skipReason, "duplicate_reset_window")
        }
    }

    func testObserveNeededTickUsesLocalQuotaSourcesWithoutProviderSend() throws {
        let fixture = try makeFixture(tools: [.codex, .claude])
        let fakeCodex = try makeFakeCodexQuotaExecutable(in: fixture.binDirectory, resetAt: "2026-06-29T05:30:00Z")
        let fakeClaude = try makeFakeClaudeQuotaExecutable(in: fixture.binDirectory, resetAt: "2026-06-29T06:00:00Z")
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.codex.enabled = true
        settings.tools.claude.enabled = true
        settings.readiness.resetEstimationMode = .localSignalsOnly
        try fixture.settingsStore.save(settings)

        let runner = RecordingToolRunner(results: [:])
        let poller = QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: {
                [
                    fixture.command(tool: .codex, executableURL: fakeCodex),
                    fixture.command(tool: .claude, executableURL: fakeClaude)
                ]
            },
            runner: runner,
            activityEvaluator: SequenceActivityEvaluator([.active]),
            now: { Self.now }
        )

        try poller.tick()

        XCTAssertTrue(runner.requests.isEmpty, "Observation must not send readiness prompts")
        let codexState = try XCTUnwrap(fixture.quotaStateStore.load(tool: .codex))
        let claudeState = try XCTUnwrap(fixture.quotaStateStore.load(tool: .claude))
        XCTAssertEqual(codexState.source, .codexLocalAppServer)
        XCTAssertEqual(codexState.confidence, .observedLocalQuota)
        XCTAssertEqual(claudeState.source, .claudeUsageProbe)
        XCTAssertEqual(claudeState.confidence, .exactReset)

        let logs = try fixture.logStore.readAll()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(Set(logs.map(\.skipReason)), ["quota_observed"])
        XCTAssertEqual(Set(logs.map(\.decisionSource)), [.providerState])
    }

    func testManualObserveUsesProductionObservationSeamWithoutProviderSend() throws {
        let fixture = try makeFixture(tools: [.codex])
        let fakeCodex = try makeFakeCodexQuotaExecutable(in: fixture.binDirectory, resetAt: "2026-06-29T07:00:00Z")
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.codex.enabled = true
        settings.tools.claude.enabled = false
        try fixture.settingsStore.save(settings)

        let runner = RecordingToolRunner(results: [:])
        let poller = QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: { [fixture.command(tool: .codex, executableURL: fakeCodex)] },
            runner: runner,
            now: { Self.now }
        )

        try poller.observeNow()

        XCTAssertTrue(runner.requests.isEmpty)
        let state = try XCTUnwrap(fixture.quotaStateStore.load(tool: .codex))
        XCTAssertEqual(state.source, .codexLocalAppServer)
        XCTAssertEqual(state.confidence, .observedLocalQuota)
        let log = try XCTUnwrap(fixture.logStore.readAll().last)
        XCTAssertEqual(log.status, .skippedMissedWindow)
        XCTAssertEqual(log.decisionSource, .providerState)
        XCTAssertEqual(log.skipReason, "quota_observed")
        XCTAssertEqual(log.quotaConfidence, .observedLocalQuota)
    }

    func testPollerPassesSavedIdleThresholdIntoProductionActivityGate() throws {
        let fixture = try makeFixture()
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.claude.enabled = false
        settings.tools.codex.enabled = true
        settings.readiness.activeOnly = true
        settings.readiness.idleThresholdSeconds = 900
        settings.readiness.minimumSendCooldownMinutes = 0
        try fixture.settingsStore.save(settings)
        try fixture.quotaStateStore.save(QuotaWindowState(
            tool: .codex,
            source: .cliMessageParser,
            confidence: .exactReset,
            classification: .limitReached(resetAt: Self.now),
            observedAt: Self.now.addingTimeInterval(-60),
            resetAt: Self.now,
            summary: "limit reset due"
        ))

        var capturedThreshold: Int?
        let runner = RecordingToolRunner(results: [
            .codex: Self.runEntry(status: .sent, timedOut: false, stdoutSummary: "ok")
        ])
        let poller = QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: { [fixture.command] },
            runner: runner,
            activityEvaluatorProvider: { readiness in
                capturedThreshold = readiness.idleThresholdSeconds
                return ActivityGate(
                    configuration: ActivityGateConfiguration(
                        idleThresholdSeconds: TimeInterval(readiness.idleThresholdSeconds),
                        unavailablePolicy: .failClosed
                    ),
                    idleReader: FixedIdleReader(seconds: 600),
                    powerStateProbe: FixedPowerStateProbe(result: .completed(exitCode: 0, stdout: ""))
                )
            },
            now: { Self.now }
        )

        try poller.tick()

        XCTAssertEqual(capturedThreshold, 900)
        XCTAssertEqual(runner.requests.count, 1, "600 idle seconds should be active under the saved 900s threshold")
        XCTAssertEqual(try fixture.logStore.readAll().last?.status, .sent)
    }

    private func makeFixture(tools: [ToolKind] = [.codex]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaWakeResetAwareAppIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        tempDirectories.append(root)
        let paths = QuotaWakePaths(applicationSupportDirectory: root.appendingPathComponent("ApplicationSupport", isDirectory: true))
        return Fixture(
            paths: paths,
            settingsStore: SettingsStore(paths: paths),
            logStore: RunLogStore(paths: paths, calendar: Self.utcCalendar),
            quotaStateStore: QuotaWindowStateStore(paths: paths),
            binDirectory: binDirectory,
            commands: Dictionary(uniqueKeysWithValues: tools.map { tool in
                (tool, ResolvedToolCommand(
                    tool: tool,
                    executableURL: binDirectory.appendingPathComponent(tool.rawValue, isDirectory: false),
                    status: .found,
                    childPATH: "\(binDirectory.path):/usr/bin:/bin",
                    searchedDirectories: [binDirectory]
                ))
            })
        )
    }

    private func makeFakeCodexQuotaExecutable(in directory: URL, resetAt: String) throws -> URL {
        let executable = directory.appendingPathComponent("codex", isDirectory: false)
        let script = """
        #!/bin/sh
        if [ "${1:-}" != "app-server" ]; then
          printf 'unexpected codex args\\n' >&2
          exit 2
        fi
        while IFS= read -r line; do
          case "$line" in
            *initialize*)
              printf '%s\\n' '{"id":1,"result":{"userAgent":"QuotaWake fake","codexHome":"/tmp/quotawake-fake"}}'
              ;;
            *rateLimits*)
              printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"resetsAt":"\(resetAt)","usedPercent":80,"windowDurationMins":300}}}}'
              exit 0
              ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        #if canImport(Darwin)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)
        #endif
        return executable
    }

    private func makeFakeClaudeQuotaExecutable(in directory: URL, resetAt: String) throws -> URL {
        let executable = directory.appendingPathComponent("claude", isDirectory: false)
        let script = """
        #!/bin/sh
        printf 'Current session: 61%% used. Resets at \(resetAt).\\n'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        #if canImport(Darwin)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)
        #endif
        return executable
    }

    private static func date(_ value: String) -> Date {
        iso.date(from: value)!
    }

    private static func runEntry(eventId: String = "placeholder", status: RunStatus, timedOut: Bool, stdoutSummary: String = "", stderrSummary: String? = nil, errorSummary: String? = nil) -> RunLogEntry {
        RunLogEntry(
            eventId: eventId,
            scheduledAt: now,
            startedAt: now,
            endedAt: now.addingTimeInterval(1),
            tool: .codex,
            commandPath: "/tmp/fake-codex",
            status: status,
            exitCode: status == .sent ? 0 : (timedOut ? nil : 1),
            durationMs: 1_000,
            timedOut: timedOut,
            stdoutSummary: stdoutSummary,
            stderrSummary: stderrSummary ?? (timedOut ? "timed out" : ""),
            prompt: "hi",
            errorSummary: errorSummary ?? (timedOut ? "Timed out" : nil),
            decisionSource: .quotaWindow,
            quotaConfidence: .exactReset,
            skipReason: nil
        )
    }

    private static let iso = ISO8601DateFormatter()
    private static let now = Date(timeIntervalSince1970: 1_782_690_600)

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private struct Fixture {
        let paths: QuotaWakePaths
        let settingsStore: SettingsStore
        let logStore: RunLogStore
        let quotaStateStore: QuotaWindowStateStore
        let binDirectory: URL
        let commands: [ToolKind: ResolvedToolCommand]

        var command: ResolvedToolCommand {
            command(tool: .codex, executableURL: commands[.codex]?.executableURL)
        }

        func command(tool: ToolKind, executableURL: URL?) -> ResolvedToolCommand {
            ResolvedToolCommand(
                tool: tool,
                executableURL: executableURL,
                status: executableURL == nil ? .missing : .found,
                childPATH: commands[tool]?.childPATH ?? "\(binDirectory.path):/usr/bin:/bin",
                searchedDirectories: commands[tool]?.searchedDirectories ?? [binDirectory]
            )
        }
    }
}

private final class RecordingToolRunner: ToolRunning {
    private let results: [ToolKind: RunLogEntry]
    private(set) var requests: [ToolRunRequest] = []

    init(results: [ToolKind: RunLogEntry]) {
        self.results = results
    }

    func run(_ request: ToolRunRequest) throws -> RunLogEntry {
        requests.append(request)
        guard var entry = results[request.command.tool] else {
            throw NSError(domain: "RecordingToolRunner", code: 1)
        }
        entry.eventId = request.eventId
        entry.scheduledAt = request.scheduledAt
        entry.prompt = request.prompt
        entry.decisionSource = request.decisionSource
        entry.quotaConfidence = request.quotaConfidence
        return entry
    }
}

private final class SequenceActivityEvaluator: ActivityEvaluating {
    private var values: [ActivityGateResult]

    init(_ values: [ActivityGateResult]) {
        self.values = values
    }

    func evaluate() -> ActivityGateResult {
        if values.isEmpty {
            return .active
        }
        return values.removeFirst()
    }
}

private struct FixedIdleReader: ActivityIdleReading {
    let seconds: TimeInterval?

    func secondsSinceLastInput() -> TimeInterval? {
        seconds
    }
}

private struct FixedPowerStateProbe: ActivityPowerStateProbing {
    let result: ActivityPowerStateCommandResult

    func sample() -> ActivityPowerStateCommandResult {
        result
    }
}
