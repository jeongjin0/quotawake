import XCTest
@testable import QuotaWakeCore

final class ObserveIfStaleTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testObserveIfStaleObservesToolWhenStateOlderThanMaxAge() throws {
        let fixture = try makeFixture()
        try saveEnabledCodexOnlySettings(fixture)
        try fixture.quotaStateStore.save(Self.observedState(
            tool: .codex,
            observedAt: Self.now.addingTimeInterval(-120)
        ))

        let observer = StubQuotaObserver(tool: .codex)
        let runner = RecordingToolRunner()
        let poller = makePoller(fixture: fixture, runner: runner, observer: observer, now: { Self.now })

        try poller.observeIfStale(maxAgeSeconds: 55)

        XCTAssertEqual(observer.observeCount, 1)
        let state = try XCTUnwrap(fixture.quotaStateStore.load(tool: .codex))
        XCTAssertEqual(state.observedAt, Self.now, "Fresh observation must be saved")
        XCTAssertEqual(state.source, .codexLocalAppServer)
    }

    func testObserveIfStaleSkipsToolWhenStateIsFresh() throws {
        let fixture = try makeFixture()
        try saveEnabledCodexOnlySettings(fixture)
        try fixture.quotaStateStore.save(Self.observedState(
            tool: .codex,
            observedAt: Self.now.addingTimeInterval(-20)
        ))

        let observer = StubQuotaObserver(tool: .codex)
        let poller = makePoller(fixture: fixture, runner: RecordingToolRunner(), observer: observer, now: { Self.now })

        try poller.observeIfStale(maxAgeSeconds: 55)

        XCTAssertEqual(observer.observeCount, 0)
    }

    func testObserveIfStaleObservesWhenNoStateExists() throws {
        let fixture = try makeFixture()
        try saveEnabledCodexOnlySettings(fixture)

        let observer = StubQuotaObserver(tool: .codex)
        let poller = makePoller(fixture: fixture, runner: RecordingToolRunner(), observer: observer, now: { Self.now })

        try poller.observeIfStale(maxAgeSeconds: 55)

        XCTAssertEqual(observer.observeCount, 1)
        XCTAssertNotNil(try fixture.quotaStateStore.load(tool: .codex))
    }

    func testObserveIfStaleRunsWhenReadinessPausedAndLaunchAtLoginOff() throws {
        let fixture = try makeFixture()
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.codex.enabled = true
        settings.tools.claude.enabled = false
        settings.background.launchAtLoginEnabled = false
        settings.readiness.paused = true
        try fixture.settingsStore.save(settings)
        try fixture.quotaStateStore.save(Self.observedState(
            tool: .codex,
            observedAt: Self.now.addingTimeInterval(-120)
        ))

        let observer = StubQuotaObserver(tool: .codex)
        let poller = makePoller(fixture: fixture, runner: RecordingToolRunner(), observer: observer, now: { Self.now })

        try poller.observeIfStale(maxAgeSeconds: 55)

        XCTAssertEqual(observer.observeCount, 1, "Display freshness must not depend on readiness automation being on")
    }

    func testObserveIfStaleSkipsBeforeFirstRunCompleted() throws {
        let fixture = try makeFixture()
        var settings = AppSettings.default
        settings.firstRunCompleted = false
        settings.tools.codex.enabled = true
        settings.tools.claude.enabled = false
        try fixture.settingsStore.save(settings)

        let observer = StubQuotaObserver(tool: .codex)
        let poller = makePoller(fixture: fixture, runner: RecordingToolRunner(), observer: observer, now: { Self.now })

        try poller.observeIfStale(maxAgeSeconds: 55)

        XCTAssertEqual(observer.observeCount, 0)
    }

    func testObserveIfStaleBacksOffAfterFailedObservation() throws {
        let fixture = try makeFixture()
        try saveEnabledCodexOnlySettings(fixture)

        let observer = StubQuotaObserver(tool: .codex, classification: .unknownFailure)
        var currentNow = Self.now
        let poller = makePoller(fixture: fixture, runner: RecordingToolRunner(), observer: observer, now: { currentNow })

        try poller.observeIfStale(maxAgeSeconds: 55)
        XCTAssertEqual(observer.observeCount, 1)

        currentNow = currentNow.addingTimeInterval(60)
        try poller.observeIfStale(maxAgeSeconds: 55)
        XCTAssertEqual(observer.observeCount, 1, "A failed observation must back off past the display cadence")

        currentNow = currentNow.addingTimeInterval(301)
        try poller.observeIfStale(maxAgeSeconds: 55)
        XCTAssertEqual(observer.observeCount, 2, "Retry resumes after the failure backoff elapses")
    }

    func testObserveIfStaleOnlyObservesStaleEnabledTools() throws {
        let fixture = try makeFixture(tools: [.codex, .claude])
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.codex.enabled = true
        settings.tools.claude.enabled = false
        try fixture.settingsStore.save(settings)
        // Both tools have stale state; only the enabled one may be observed.
        try fixture.quotaStateStore.save(Self.observedState(
            tool: .codex,
            observedAt: Self.now.addingTimeInterval(-120)
        ))
        try fixture.quotaStateStore.save(Self.observedState(
            tool: .claude,
            observedAt: Self.now.addingTimeInterval(-120)
        ))

        var observedTools: [ToolKind] = []
        let observers: [ToolKind: StubQuotaObserver] = [
            .codex: StubQuotaObserver(tool: .codex),
            .claude: StubQuotaObserver(tool: .claude)
        ]
        let poller = QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: {
                [
                    fixture.command(tool: .codex),
                    fixture.command(tool: .claude)
                ]
            },
            runner: RecordingToolRunner(),
            quotaObserverProvider: { command, _ in
                observedTools.append(command.tool)
                return observers[command.tool]
            },
            now: { Self.now }
        )

        try poller.observeIfStale(maxAgeSeconds: 55)
        XCTAssertEqual(observedTools, [.codex], "Disabled tools must not be observed")
        XCTAssertEqual(observers[.codex]?.observeCount, 1)
        XCTAssertEqual(observers[.claude]?.observeCount, 0)

        // The freshly observed state is now current, so a second pass without
        // time advancing must observe nothing.
        try poller.observeIfStale(maxAgeSeconds: 55)
        XCTAssertEqual(observers[.codex]?.observeCount, 1, "Fresh state must not be re-observed")
    }

    func testObserveIfStaleRepeatedSuccessesWithChangingSummaryAppendOneLogEntry() throws {
        let fixture = try makeFixture()
        try saveEnabledCodexOnlySettings(fixture)

        let observer = StubQuotaObserver(tool: .codex) { count in
            "codex quota window observed, \(40 + count)% used"
        }
        var currentNow = Self.now
        let poller = makePoller(fixture: fixture, runner: RecordingToolRunner(), observer: observer, now: { currentNow })

        for _ in 0..<3 {
            try poller.observeIfStale(maxAgeSeconds: 55)
            currentNow = currentNow.addingTimeInterval(60)
        }

        XCTAssertEqual(observer.observeCount, 3)
        let observeLogs = try fixture.logStore.readAll().filter { $0.eventId.hasPrefix("quota-observe-") }
        XCTAssertEqual(observeLogs.count, 1, "Same-outcome observations must not append a log row per pass even when the summary moves")
    }

    func testObserveIfStaleNeverInvokesProviderRunner() throws {
        let fixture = try makeFixture()
        try saveEnabledCodexOnlySettings(fixture)
        try fixture.quotaStateStore.save(Self.observedState(
            tool: .codex,
            observedAt: Self.now.addingTimeInterval(-120)
        ))

        let observer = StubQuotaObserver(tool: .codex)
        let runner = RecordingToolRunner()
        let poller = makePoller(fixture: fixture, runner: runner, observer: observer, now: { Self.now })

        try poller.observeIfStale(maxAgeSeconds: 55)

        XCTAssertEqual(observer.observeCount, 1)
        XCTAssertTrue(runner.requests.isEmpty, "observeIfStale must never send a provider prompt")
    }

    // MARK: - Fixture

    private func saveEnabledCodexOnlySettings(_ fixture: Fixture) throws {
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.codex.enabled = true
        settings.tools.claude.enabled = false
        try fixture.settingsStore.save(settings)
    }

    private func makePoller(
        fixture: Fixture,
        runner: RecordingToolRunner,
        observer: StubQuotaObserver,
        now: @escaping () -> Date
    ) -> QuotaReadinessPoller {
        QuotaReadinessPoller(
            paths: fixture.paths,
            settingsStore: fixture.settingsStore,
            logStore: fixture.logStore,
            quotaStateStore: fixture.quotaStateStore,
            commandsProvider: { [fixture.command(tool: .codex)] },
            runner: runner,
            quotaObserverProvider: { _, _ in observer },
            now: now
        )
    }

    private func makeFixture(tools: [ToolKind] = [.codex]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "QuotaWakeObserveIfStaleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        tempDirectories.append(root)
        let paths = QuotaWakePaths(applicationSupportDirectory: root.appendingPathComponent("ApplicationSupport", isDirectory: true))
        return Fixture(
            paths: paths,
            settingsStore: SettingsStore(paths: paths),
            logStore: RunLogStore(paths: paths),
            quotaStateStore: QuotaWindowStateStore(paths: paths),
            binDirectory: binDirectory
        )
    }

    private static func observedState(tool: ToolKind, observedAt: Date) -> QuotaWindowState {
        QuotaWindowState(
            tool: tool,
            source: .codexLocalAppServer,
            confidence: .observedLocalQuota,
            classification: .sent,
            observedAt: observedAt,
            usedPercent: 40,
            remainingPercent: 60,
            summary: "quota window observed"
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_782_690_600)

    private struct Fixture {
        let paths: QuotaWakePaths
        let settingsStore: SettingsStore
        let logStore: RunLogStore
        let quotaStateStore: QuotaWindowStateStore
        let binDirectory: URL

        func command(tool: ToolKind) -> ResolvedToolCommand {
            ResolvedToolCommand(
                tool: tool,
                executableURL: binDirectory.appendingPathComponent(tool.rawValue, isDirectory: false),
                status: .found,
                childPATH: "\(binDirectory.path):/usr/bin:/bin",
                searchedDirectories: [binDirectory]
            )
        }
    }
}

private final class RecordingToolRunner: ToolRunning {
    private(set) var requests: [ToolRunRequest] = []

    func run(_ request: ToolRunRequest) throws -> RunLogEntry {
        requests.append(request)
        throw NSError(domain: "RecordingToolRunner", code: 1)
    }
}

private final class StubQuotaObserver: QuotaWindowObserving {
    private let tool: ToolKind
    private let classification: QuotaSourceClassification
    private let summaryProvider: (Int) -> String
    private(set) var observeCount = 0

    init(
        tool: ToolKind,
        classification: QuotaSourceClassification = .sent,
        summaryProvider: @escaping (Int) -> String = { _ in "quota window observed" }
    ) {
        self.tool = tool
        self.classification = classification
        self.summaryProvider = summaryProvider
    }

    func observe(observedAt: Date) -> QuotaWindowState {
        observeCount += 1
        let failed: Bool
        switch classification {
        case .quotaUnavailable, .unknownFailure:
            failed = true
        default:
            failed = false
        }
        return QuotaWindowState(
            tool: tool,
            source: failed ? .none : .codexLocalAppServer,
            confidence: failed ? .unknown : .observedLocalQuota,
            classification: classification,
            observedAt: observedAt,
            summary: summaryProvider(observeCount)
        )
    }
}
