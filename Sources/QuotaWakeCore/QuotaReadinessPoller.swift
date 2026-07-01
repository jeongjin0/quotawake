import Foundation

public protocol ToolRunning: AnyObject {
    func run(_ request: ToolRunRequest) throws -> RunLogEntry
}

extension ToolRunner: ToolRunning {}

public protocol ActivityEvaluating {
    func evaluate() -> ActivityGateResult
}

extension ActivityGate: ActivityEvaluating {}

public enum ActivityEvaluatorProvider {
    public static func makeEvaluator(readiness: WindowReadinessSettings) -> ActivityEvaluating {
        ActivityGate(configuration: ActivityGateConfiguration(
            idleThresholdSeconds: TimeInterval(readiness.idleThresholdSeconds),
            unavailablePolicy: .failClosed
        ))
    }
}

public final class QuotaReadinessPoller {
    private let paths: QuotaWakePaths
    private let settingsStore: SettingsStore
    private let logStore: RunLogStore
    private let quotaStateStore: QuotaWindowStateStore
    private let commandsProvider: () -> [ResolvedToolCommand]
    private let runner: ToolRunning
    private let activityEvaluator: ActivityEvaluating?
    private let activityEvaluatorProvider: (WindowReadinessSettings) -> ActivityEvaluating
    private let quotaObserverProvider: (ResolvedToolCommand, QuotaWakePaths) -> QuotaWindowObserving?
    private let engine: QuotaReadinessEngine
    private let now: () -> Date
    private let lock = NSLock()
    private var tickRunning = false

    public init(
        paths: QuotaWakePaths = QuotaWakePaths(),
        settingsStore: SettingsStore = SettingsStore(),
        logStore: RunLogStore = RunLogStore(),
        quotaStateStore: QuotaWindowStateStore = QuotaWindowStateStore(),
        commandsProvider: @escaping () -> [ResolvedToolCommand],
        runner: ToolRunning,
        activityEvaluator: ActivityEvaluating? = nil,
        activityEvaluatorProvider: @escaping (WindowReadinessSettings) -> ActivityEvaluating = ActivityEvaluatorProvider.makeEvaluator,
        quotaObserverProvider: @escaping (ResolvedToolCommand, QuotaWakePaths) -> QuotaWindowObserving? = LocalQuotaWindowObserverProvider.makeObserver,
        engine: QuotaReadinessEngine = QuotaReadinessEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.logStore = logStore
        self.quotaStateStore = quotaStateStore
        self.commandsProvider = commandsProvider
        self.runner = runner
        self.activityEvaluator = activityEvaluator
        self.activityEvaluatorProvider = activityEvaluatorProvider
        self.quotaObserverProvider = quotaObserverProvider
        self.engine = engine
        self.now = now
    }

    public func sendNow() throws {
        let settings = try settingsStore.load()
        let commands = commandsProvider()
        let scheduledAt = now()

        for command in commands where settings.tools[command.tool].enabled {
            let eventId = "manual-send-now-\(command.tool.rawValue)"
            let entry = try runner.run(ToolRunRequest(
                command: command,
                prompt: settings.prompt,
                eventId: eventId,
                scheduledAt: scheduledAt,
                runDirectory: paths.runDirectory,
                decisionSource: .toolSettings,
                quotaConfidence: nil
            ))
            try appendIfMissing(entry)
            try updateQuotaState(from: entry)
        }
    }

    public func tick() throws {
        guard beginTick() else {
            return
        }
        defer { endTick() }

        let settings = try settingsStore.load()
        guard settings.firstRunCompleted else {
            return
        }
        guard settings.background.launchAtLoginEnabled else {
            return
        }
        guard !settings.readiness.paused else {
            return
        }

        let commands = commandsProvider()
        let logs = try logStore.readAll()
        let activity = (activityEvaluator ?? activityEvaluatorProvider(settings.readiness)).evaluate()
        let completedEventIds = Set(logs.filter { providerWasInvoked(status: $0.status) }.map(\.eventId))

        for command in commands where settings.tools[command.tool].enabled {
            let currentTime = now()
            let quotaState = try quotaStateStore.load(tool: command.tool)
            let toolLogs = logs.filter { $0.tool == command.tool }
            let decision = engine.evaluate(input: QuotaReadinessInput(
                tool: command.tool,
                toolSettings: settings.tools[command.tool],
                quotaWindow: quotaState,
                activity: activity,
                readiness: settings.readiness,
                now: currentTime,
                lastSuccessAt: lastSuccessAt(in: toolLogs),
                lastSentAt: lastProviderAttemptAt(in: toolLogs),
                completedResetWindowEventIds: completedEventIds
            ))

            switch decision {
            case let .send(event):
                let source = decisionSource(for: event)
                let entry = try runner.run(ToolRunRequest(
                    command: command,
                    prompt: settings.prompt,
                    eventId: event.eventId,
                    scheduledAt: currentTime,
                    runDirectory: paths.runDirectory,
                    decisionSource: source,
                    quotaConfidence: event.confidence
                ))
                try appendIfMissing(entry)
                try updateQuotaState(from: entry)
            case let .wait(wait):
                try appendSkipIfUseful(wait, command: command, prompt: settings.prompt, scheduledAt: currentTime)
            case let .observeNeeded(observation):
                try observeQuotaWindow(
                    command: command,
                    prompt: settings.prompt,
                    scheduledAt: currentTime,
                    reason: observation.reason
                )
            }
        }
    }

    public func observeNow() throws {
        let settings = try settingsStore.load()
        let commands = commandsProvider()
        let scheduledAt = now()

        for command in commands where settings.tools[command.tool].enabled {
            try observeQuotaWindow(
                command: command,
                prompt: settings.prompt,
                scheduledAt: scheduledAt,
                reason: .unknownStrictMode
            )
        }
    }

    private func beginTick() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !tickRunning else {
            return false
        }
        tickRunning = true
        return true
    }

    private func endTick() {
        lock.lock()
        tickRunning = false
        lock.unlock()
    }

    private func appendSkipIfUseful(
        _ wait: QuotaReadinessWait,
        command: ResolvedToolCommand,
        prompt: String,
        scheduledAt: Date
    ) throws {
        guard shouldLog(wait.reason) else {
            return
        }
        let now = now()
        let eventId = wait.nextCandidate?.eventId ?? "wait-\(command.tool.rawValue)-\(Int(now.timeIntervalSince1970))"
        let entry = RunLogEntry(
            eventId: eventId,
            scheduledAt: scheduledAt,
            startedAt: now,
            endedAt: now,
            tool: command.tool,
            commandPath: command.executableURL?.path ?? "",
            status: .skippedMissedWindow,
            exitCode: nil,
            durationMs: 0,
            timedOut: false,
            stdoutSummary: "",
            stderrSummary: "",
            prompt: prompt,
            errorSummary: nil,
            decisionSource: wait.source,
            quotaConfidence: wait.nextCandidate?.confidence,
            skipReason: skipReasonText(wait.reason)
        )
        try appendIfMissing(entry)
    }

    private func appendIfMissing(_ entry: RunLogEntry) throws {
        let alreadyLogged = try logStore.readAll().contains { logged in
            isSameLogEntry(logged, entry)
        }
        if !alreadyLogged {
            try logStore.append(entry)
        }
    }

    private func isSameLogEntry(_ logged: RunLogEntry, _ entry: RunLogEntry) -> Bool {
        logged.eventId == entry.eventId
            && logged.tool == entry.tool
            && logged.status == entry.status
            && abs(logged.startedAt.timeIntervalSince(entry.startedAt)) < 1
    }

    private func updateQuotaState(from entry: RunLogEntry) throws {
        let state = QuotaWindowParser.parse(
            tool: entry.tool,
            source: .cliMessageParser,
            stdout: entry.stdoutSummary,
            stderr: entry.stderrSummary,
            exitCode: entry.exitCode,
            timedOut: entry.timedOut,
            observedAt: entry.endedAt
        )
        try quotaStateStore.save(state)
    }

    private func observeQuotaWindow(
        command: ResolvedToolCommand,
        prompt: String,
        scheduledAt: Date,
        reason: QuotaReadinessObserveReason
    ) throws {
        let startedAt = now()
        guard let observer = quotaObserverProvider(command, paths) else {
            let endedAt = now()
            try appendIfMissing(observationLogEntry(
                command: command,
                prompt: prompt,
                scheduledAt: scheduledAt,
                startedAt: startedAt,
                endedAt: endedAt,
                state: nil,
                skipReason: "quota_observe_unavailable",
                summary: "local quota source unavailable: \(observeReasonText(reason))"
            ))
            return
        }

        let state = observer.observe(observedAt: startedAt)
        try quotaStateStore.save(state)
        let endedAt = now()
        try appendIfMissing(observationLogEntry(
            command: command,
            prompt: prompt,
            scheduledAt: scheduledAt,
            startedAt: startedAt,
            endedAt: endedAt,
            state: state,
            skipReason: observationSkipReason(for: state),
            summary: state.summary
        ))
    }

    private func observationLogEntry(
        command: ResolvedToolCommand,
        prompt: String,
        scheduledAt: Date,
        startedAt: Date,
        endedAt: Date,
        state: QuotaWindowState?,
        skipReason: String,
        summary: String
    ) -> RunLogEntry {
        RunLogEntry(
            eventId: "quota-observe-\(command.tool.rawValue)-\(Int(startedAt.timeIntervalSince1970))",
            scheduledAt: scheduledAt,
            startedAt: startedAt,
            endedAt: endedAt,
            tool: command.tool,
            commandPath: command.executableURL?.path ?? "",
            status: .skippedMissedWindow,
            exitCode: nil,
            durationMs: max(0, Int((endedAt.timeIntervalSince(startedAt) * 1_000).rounded())),
            timedOut: false,
            stdoutSummary: summary,
            stderrSummary: "",
            prompt: prompt,
            errorSummary: nil,
            decisionSource: .providerState,
            quotaConfidence: state?.confidence ?? .unknown,
            skipReason: skipReason
        )
    }

    private func observationSkipReason(for state: QuotaWindowState) -> String {
        switch state.classification {
        case .quotaUnavailable:
            return "quota_observe_unavailable"
        case .unknownFailure:
            return "quota_observe_failed"
        case .authRequired, .apiBillingEnvPresent, .usageLimitNoReset:
            return "quota_observe_blocked"
        case .sent, .limitReached:
            return "quota_observed"
        }
    }

    private func observeReasonText(_ reason: QuotaReadinessObserveReason) -> String {
        switch reason {
        case .unknownStrictMode:
            return "unknown_strict_mode"
        case .missingLastSuccessForEstimate:
            return "missing_last_success_for_estimate"
        case .invalidQuotaState:
            return "invalid_quota_state"
        }
    }

    private func lastSuccessAt(in logs: [RunLogEntry]) -> Date? {
        logs.filter { $0.status == .sent }.map(\.endedAt).max()
    }

    private func lastProviderAttemptAt(in logs: [RunLogEntry]) -> Date? {
        logs.filter { providerWasInvoked(status: $0.status) }.map(\.endedAt).max()
    }

    private func providerWasInvoked(status: RunStatus) -> Bool {
        switch status {
        case .sent, .failed, .timedOut:
            return true
        case .skippedOverlap, .skippedMissedWindow:
            return false
        }
    }

    private func decisionSource(for event: QuotaResetWindowEvent) -> QuotaReadinessDecisionSource {
        event.confidence == .estimatedFiveHour ? .estimatedFiveHour : .quotaWindow
    }

    private func shouldLog(_ reason: QuotaReadinessSkipReason) -> Bool {
        switch reason {
        case .toolDisabled, .resetNotDue, .quotaUnavailable:
            return false
        case .idle, .activityUnavailable, .suppressedPowerState, .providerBlocked, .duplicateResetWindow, .cooldown:
            return true
        }
    }

    private func skipReasonText(_ reason: QuotaReadinessSkipReason) -> String {
        switch reason {
        case .toolDisabled:
            return "tool_disabled"
        case .idle:
            return "idle"
        case .activityUnavailable:
            return "activity_unavailable"
        case .suppressedPowerState(let reason):
            return reason.rawValue
        case .resetNotDue:
            return "reset_not_due"
        case .providerBlocked:
            return "provider_blocked"
        case .quotaUnavailable:
            return "quota_unavailable"
        case .duplicateResetWindow:
            return "duplicate_reset_window"
        case .cooldown:
            return "cooldown"
        }
    }
}
