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
    // Minimum spacing between automatic quota observations per tool, so an
    // unparseable or unavailable provider does not spawn a probe subprocess on
    // every poll tick. Manual observeNow() is not throttled.
    private let minimumObserveIntervalSeconds: TimeInterval
    // Retry spacing for observeIfStale after a failed observation (source
    // unavailable or unparseable output), so a broken local quota source does
    // not spawn a probe subprocess on every 60-second display refresh.
    private let failureRetryIntervalSeconds: TimeInterval
    private let lock = NSLock()
    private var workRunning = false

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
        now: @escaping () -> Date = Date.init,
        minimumObserveIntervalSeconds: TimeInterval = 600,
        failureRetryIntervalSeconds: TimeInterval = 300
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
        self.minimumObserveIntervalSeconds = minimumObserveIntervalSeconds
        self.failureRetryIntervalSeconds = failureRetryIntervalSeconds
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
            try appendRunEntryIfMissing(entry)
            try updateQuotaState(from: entry)
        }
    }

    public func tick() throws {
        guard beginExclusiveWork() else {
            return
        }
        defer { endExclusiveWork() }

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
        // Only successful sends complete a reset window; failed/timed-out
        // attempts feed the engine's bounded retry (backoff + attempt cap)
        // instead of permanently burning the window.
        let completedEventIds = Set(logs.filter { $0.status == .sent }.map(\.eventId))

        for command in commands where settings.tools[command.tool].enabled {
            do {
                try evaluateTool(
                    command: command,
                    settings: settings,
                    activity: activity,
                    logs: logs,
                    completedEventIds: completedEventIds
                )
            } catch {
                // One tool's failure (corrupt state file, log I/O error) must
                // not stop evaluation of the remaining tools this tick.
                continue
            }
        }
    }

    private func evaluateTool(
        command: ResolvedToolCommand,
        settings: AppSettings,
        activity: ActivityGateResult,
        logs: [RunLogEntry],
        completedEventIds: Set<String>
    ) throws {
        let currentTime = now()
        // A corrupt per-tool state file degrades to "no observation yet"; the
        // resulting observeNeeded decision re-probes and rewrites it.
        let quotaState = (try? quotaStateStore.load(tool: command.tool)) ?? nil
        let toolLogs = logs.filter { $0.tool == command.tool }
        let decision = engine.evaluate(input: QuotaReadinessInput(
            tool: command.tool,
            toolSettings: settings.tools[command.tool],
            quotaWindow: quotaState,
            activity: activity,
            readiness: settings.readiness,
            now: currentTime,
            lastSuccessAt: lastSuccessAt(in: toolLogs),
            lastSentAt: lastSuccessAt(in: toolLogs),
            completedResetWindowEventIds: completedEventIds,
            failedSendAttempts: failedSendAttempts(in: toolLogs)
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
            try appendRunEntryIfMissing(entry)
            try updateQuotaState(from: entry)
            // Verify the wake actually started a window: a fresh local quota
            // read right after a successful send should show the new 5h
            // session, which also updates the popover countdown immediately.
            // Read-only — no provider message. Failed sends skip it; their
            // bounded retry re-observes on its own cadence.
            if entry.status == .sent {
                try? observeQuotaWindow(
                    command: command,
                    prompt: settings.prompt,
                    scheduledAt: currentTime,
                    reason: .postSendVerification,
                    previousToolLogs: toolLogs,
                    dedupeOnOutcomeOnly: true
                )
            }
        case let .wait(wait):
            try appendSkipIfUseful(
                wait,
                command: command,
                prompt: settings.prompt,
                scheduledAt: currentTime,
                logs: toolLogs
            )
        case let .observeNeeded(observation):
            if let quotaState,
               currentTime.timeIntervalSince(quotaState.observedAt) < minimumObserveIntervalSeconds {
                return
            }
            try observeQuotaWindow(
                command: command,
                prompt: settings.prompt,
                scheduledAt: currentTime,
                reason: observation.reason,
                previousToolLogs: toolLogs
            )
        }
    }

    public func observeNow() throws {
        // Manual Reload runs on its own queue; skip instead of racing a tick
        // or send that is mid-flight — the caller's refresh still shows the
        // latest on-disk state.
        guard beginExclusiveWork() else {
            return
        }
        defer { endExclusiveWork() }

        let settings = try settingsStore.load()
        let commands = commandsProvider()
        let scheduledAt = now()

        for command in commands where settings.tools[command.tool].enabled {
            try observeQuotaWindow(
                command: command,
                prompt: settings.prompt,
                scheduledAt: scheduledAt,
                reason: .unknownStrictMode,
                previousToolLogs: []
            )
        }
    }

    // Display-freshness observe: re-probes local quota sources for enabled
    // tools whose stored state is older than maxAgeSeconds so the popover
    // stays current without a manual Reload. Deliberately not gated on
    // launchAtLoginEnabled or readiness.paused — observation is a local quota
    // read and never sends a provider message, and the displayed quota should
    // stay fresh even when readiness automation is off.
    // failureRetrySeconds overrides the failed-observation backoff for
    // user-intent moments (popover open), where a retry is bounded by how
    // often the user looks rather than by the background poll loop.
    public func observeIfStale(maxAgeSeconds: TimeInterval, failureRetrySeconds: TimeInterval? = nil) throws {
        guard beginExclusiveWork() else {
            return
        }
        defer { endExclusiveWork() }

        let settings = try settingsStore.load()
        guard settings.firstRunCompleted else {
            return
        }

        let logs = try logStore.readAll()
        let currentTime = now()

        for command in commandsProvider() where settings.tools[command.tool].enabled {
            do {
                if let state = (try? quotaStateStore.load(tool: command.tool)) ?? nil {
                    let threshold = isFailedObservation(state.classification)
                        ? (failureRetrySeconds ?? failureRetryIntervalSeconds)
                        : maxAgeSeconds
                    if currentTime.timeIntervalSince(state.observedAt) < threshold {
                        continue
                    }
                }
                try observeQuotaWindow(
                    command: command,
                    prompt: settings.prompt,
                    scheduledAt: currentTime,
                    reason: .staleProviderState,
                    previousToolLogs: logs.filter { $0.tool == command.tool },
                    dedupeOnOutcomeOnly: true
                )
            } catch {
                // One tool's failure (corrupt state file, log I/O error) must
                // not stop refreshing the remaining tools.
                continue
            }
        }
    }

    // Failed observations retry on the slower failureRetryIntervalSeconds
    // cadence; successful (including blocked-provider) observations refresh at
    // the caller's maxAgeSeconds.
    private func isFailedObservation(_ classification: QuotaSourceClassification) -> Bool {
        switch classification {
        case .quotaUnavailable, .unknownFailure:
            return true
        case .sent, .limitReached, .authRequired, .apiBillingEnvPresent, .usageLimitNoReset:
            return false
        }
    }

    private func beginExclusiveWork() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !workRunning else {
            return false
        }
        workRunning = true
        return true
    }

    private func endExclusiveWork() {
        lock.lock()
        workRunning = false
        lock.unlock()
    }

    private func appendSkipIfUseful(
        _ wait: QuotaReadinessWait,
        command: ResolvedToolCommand,
        prompt: String,
        scheduledAt: Date,
        logs: [RunLogEntry]
    ) throws {
        guard shouldLog(wait.reason) else {
            return
        }
        let reasonText = skipReasonText(wait.reason)
        let eventId = wait.nextCandidate?.eventId ?? "wait-\(command.tool.rawValue)-\(reasonText)"
        // Log skip transitions, not every poll tick: while the same candidate
        // stays gated for the same reason (idle overnight, cooldown), one entry
        // is enough. A new candidate, reason, or interleaved run logs again.
        if let latest = logs.last,
           latest.status == .skippedMissedWindow,
           latest.eventId == eventId,
           latest.skipReason == reasonText {
            return
        }
        let now = now()
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
            skipReason: reasonText
        )
        try logStore.append(entry)
    }

    private func appendRunEntryIfMissing(_ entry: RunLogEntry) throws {
        // The production ToolRunner persists its own run entries; skip the
        // append when this exact run is already the latest thing on disk.
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
        try quotaStateStore.save(mergedDisplayState(parsed: state))
    }

    // A signal-less result — a readiness send's "Hi!" output, a failed probe,
    // or the idle-provider `/usage` output after a window expired (0% used,
    // no session, no resets clause) — would clobber the richer observed
    // window shown in the popover, blanking the reset countdown until the
    // next successful probe. Keep the fresh summary/observedAt but carry the
    // previous observation's quota display fields forward. When the result
    // did contain quota signals (reset time, percentages), it wins as-is.
    //
    // Classification is also retained when the previous state held a
    // limitReached reset candidate and the fresh result is merely
    // uninformative (sent/unavailable/failed): otherwise the idle-provider
    // output that appears right after a reset passes would erase the due
    // candidate before the engine consumed it, and the wake would never
    // fire. Blocked classifications (auth, billing env) are real signals and
    // always win. Idempotency makes retaining a consumed candidate harmless.
    private func mergedDisplayState(parsed: QuotaWindowState) -> QuotaWindowState {
        guard let previous = (try? quotaStateStore.load(tool: parsed.tool)) ?? nil else {
            return parsed
        }
        // Retain a limitReached reset candidate across uninformative results.
        // This covers both shapes of the idle provider output: fully
        // signal-less text, and the fresh-session "0% used" line without a
        // resets clause (usedPercent parses but no reset time does). Blocked
        // classifications and a newly parsed reset are real signals and win.
        let retainsCandidate: Bool
        if case .limitReached = previous.classification {
            switch parsed.classification {
            case .sent, .quotaUnavailable, .unknownFailure:
                retainsCandidate = true
            case .limitReached, .authRequired, .apiBillingEnvPresent, .usageLimitNoReset:
                retainsCandidate = false
            }
        } else {
            retainsCandidate = false
        }
        let parsedHasDisplaySignals = parsed.resetAt != nil || parsed.usedPercent != nil || parsed.weeklyUsedPercent != nil
        guard retainsCandidate || !parsedHasDisplaySignals else {
            return parsed
        }
        guard retainsCandidate || previous.resetAt != nil || previous.usedPercent != nil || previous.weeklyUsedPercent != nil else {
            return parsed
        }
        // Field-wise: fresh values win where the result produced them, the
        // previous observation fills the gaps so the popover never blanks.
        let hasFreshSession = parsed.usedPercent != nil
        let hasFreshWeekly = parsed.weeklyUsedPercent != nil
        return QuotaWindowState(
            tool: parsed.tool,
            source: retainsCandidate ? previous.source : parsed.source,
            confidence: retainsCandidate ? previous.confidence : parsed.confidence,
            classification: retainsCandidate ? previous.classification : parsed.classification,
            observedAt: parsed.observedAt,
            resetAt: parsed.resetAt ?? previous.resetAt,
            usedPercent: hasFreshSession ? parsed.usedPercent : previous.usedPercent,
            remainingPercent: hasFreshSession ? parsed.remainingPercent : previous.remainingPercent,
            windowLabel: hasFreshSession ? (parsed.windowLabel ?? previous.windowLabel) : previous.windowLabel,
            weeklyUsedPercent: hasFreshWeekly ? parsed.weeklyUsedPercent : previous.weeklyUsedPercent,
            weeklyRemainingPercent: hasFreshWeekly ? parsed.weeklyRemainingPercent : previous.weeklyRemainingPercent,
            weeklyResetAt: hasFreshWeekly ? parsed.weeklyResetAt : previous.weeklyResetAt,
            weeklyWindowLabel: hasFreshWeekly ? parsed.weeklyWindowLabel : previous.weeklyWindowLabel,
            summary: parsed.summary
        )
    }

    private func observeQuotaWindow(
        command: ResolvedToolCommand,
        prompt: String,
        scheduledAt: Date,
        reason: QuotaReadinessObserveReason,
        previousToolLogs: [RunLogEntry],
        dedupeOnOutcomeOnly: Bool = false
    ) throws {
        let startedAt = now()
        guard let observer = quotaObserverProvider(command, paths) else {
            let endedAt = now()
            try appendObservationIfChanged(observationLogEntry(
                command: command,
                prompt: prompt,
                scheduledAt: scheduledAt,
                startedAt: startedAt,
                endedAt: endedAt,
                state: nil,
                skipReason: "quota_observe_unavailable",
                summary: "local quota source unavailable: \(observeReasonText(reason))"
            ), previousToolLogs: previousToolLogs, dedupeOnOutcomeOnly: dedupeOnOutcomeOnly)
            return
        }

        let state = observer.observe(observedAt: startedAt)
        try quotaStateStore.save(mergedDisplayState(parsed: state))
        let endedAt = now()
        try appendObservationIfChanged(observationLogEntry(
            command: command,
            prompt: prompt,
            scheduledAt: scheduledAt,
            startedAt: startedAt,
            endedAt: endedAt,
            state: state,
            skipReason: observationSkipReason(for: state),
            summary: state.summary
        ), previousToolLogs: previousToolLogs, dedupeOnOutcomeOnly: dedupeOnOutcomeOnly)
    }

    private func appendObservationIfChanged(
        _ entry: RunLogEntry,
        previousToolLogs: [RunLogEntry],
        dedupeOnOutcomeOnly: Bool = false
    ) throws {
        // Repeated observations with the same outcome (e.g. app-server still
        // unavailable) would otherwise append an identical entry per probe.
        // On the frequent display-refresh cadence (dedupeOnOutcomeOnly), a
        // moving usage percent in the summary must not append a row per
        // observation either, so the summary is ignored for dedupe there.
        if let latest = previousToolLogs.last,
           latest.status == .skippedMissedWindow,
           latest.eventId.hasPrefix("quota-observe-"),
           latest.skipReason == entry.skipReason,
           dedupeOnOutcomeOnly || latest.stdoutSummary == entry.stdoutSummary {
            return
        }
        try logStore.append(entry)
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
        case .staleProviderState:
            return "stale_provider_state"
        case .postSendVerification:
            return "post_send_verification"
        }
    }

    private func lastSuccessAt(in logs: [RunLogEntry]) -> Date? {
        logs.filter { $0.status == .sent }.map(\.endedAt).max()
    }

    private func failedSendAttempts(in logs: [RunLogEntry]) -> [String: QuotaSendAttemptHistory] {
        let failures = logs.filter { $0.status == .failed || $0.status == .timedOut }
        return Dictionary(grouping: failures, by: \.eventId).compactMapValues { entries in
            guard let lastAttemptAt = entries.map(\.endedAt).max() else {
                return nil
            }
            return QuotaSendAttemptHistory(count: entries.count, lastAttemptAt: lastAttemptAt)
        }
    }

    private func decisionSource(for event: QuotaResetWindowEvent) -> QuotaReadinessDecisionSource {
        event.confidence == .estimatedFiveHour ? .estimatedFiveHour : .quotaWindow
    }

    private func shouldLog(_ reason: QuotaReadinessSkipReason) -> Bool {
        switch reason {
        case .toolDisabled, .resetNotDue, .quotaUnavailable:
            return false
        case .idle, .activityUnavailable, .suppressedPowerState, .providerBlocked, .duplicateResetWindow,
             .cooldown, .sendRetryBackoff, .sendAttemptsExhausted:
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
        case .sendRetryBackoff:
            return "send_retry_backoff"
        case .sendAttemptsExhausted:
            return "send_attempts_exhausted"
        }
    }
}
