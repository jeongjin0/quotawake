import Foundation

public struct QuotaReadinessEngine: Equatable, Sendable {
    // Blocked/unavailable provider states are re-observed after this age so a
    // one-time condition (logged out once, app-server briefly missing) cannot
    // wedge the tool until a manual observe.
    private let staleProviderStateSeconds: TimeInterval
    // A failed/timed-out send may retry after this backoff, up to the attempt
    // cap below, so one transient error cannot burn the entire 5h reset window
    // while a crash-looping CLI still cannot storm the provider.
    private let sendFailureRetrySeconds: TimeInterval
    private let maxSendAttemptsPerResetWindow: Int

    public init(
        staleProviderStateSeconds: TimeInterval = 900,
        sendFailureRetrySeconds: TimeInterval = 600,
        maxSendAttemptsPerResetWindow: Int = 3
    ) {
        self.staleProviderStateSeconds = staleProviderStateSeconds
        self.sendFailureRetrySeconds = sendFailureRetrySeconds
        self.maxSendAttemptsPerResetWindow = maxSendAttemptsPerResetWindow
    }

    public func evaluate(input: QuotaReadinessInput) -> QuotaReadinessDecision {
        guard input.toolSettings.enabled else {
            return .wait(QuotaReadinessWait(reason: .toolDisabled, nextCandidate: nil, source: .toolSettings))
        }

        switch candidate(from: input) {
        case .blocked:
            return .wait(QuotaReadinessWait(reason: .providerBlocked, nextCandidate: nil, source: .providerState))
        case .unavailable:
            return .wait(QuotaReadinessWait(reason: .quotaUnavailable, nextCandidate: nil, source: .providerState))
        case .observeNeeded(let observation):
            return .observeNeeded(observation)
        case .candidate(let candidate):
            return decision(for: candidate, input: input)
        }
    }

    private func decision(
        for candidate: QuotaReadinessCandidate,
        input: QuotaReadinessInput
    ) -> QuotaReadinessDecision {
        guard candidate.event.resetAt <= input.now else {
            return .wait(QuotaReadinessWait(
                reason: .resetNotDue,
                nextCandidate: candidate.event,
                source: candidate.source
            ))
        }
        if let activityWait = waitForActivity(input.activity, candidate: candidate.event, readiness: input.readiness) {
            return .wait(activityWait)
        }
        guard !input.completedResetWindowEventIds.contains(candidate.event.eventId) else {
            return .wait(QuotaReadinessWait(
                reason: .duplicateResetWindow,
                nextCandidate: candidate.event,
                source: .idempotency
            ))
        }
        if let attempts = input.failedSendAttempts[candidate.event.eventId] {
            guard attempts.count < maxSendAttemptsPerResetWindow else {
                return .wait(QuotaReadinessWait(
                    reason: .sendAttemptsExhausted,
                    nextCandidate: candidate.event,
                    source: .idempotency
                ))
            }
            let retryAt = attempts.lastAttemptAt.addingTimeInterval(sendFailureRetrySeconds)
            if input.now < retryAt {
                return .wait(QuotaReadinessWait(
                    reason: .sendRetryBackoff(until: retryAt),
                    nextCandidate: candidate.event,
                    source: .cooldown
                ))
            }
        }
        if let cooldownUntil = cooldownUntil(input), input.now < cooldownUntil {
            return .wait(QuotaReadinessWait(
                reason: .cooldown(until: cooldownUntil),
                nextCandidate: candidate.event,
                source: .cooldown
            ))
        }
        return .send(candidate.event)
    }

    private func candidate(from input: QuotaReadinessInput) -> QuotaReadinessCandidateResult {
        guard let quotaWindow = input.quotaWindow else {
            return estimatedCandidate(from: input)
        }
        guard quotaWindow.tool == input.tool else {
            return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .invalidQuotaState))
        }
        if isProviderBlocked(quotaWindow) {
            if isStale(quotaWindow, now: input.now) {
                return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .staleProviderState))
            }
            return .blocked
        }
        if quotaWindow.classification == .quotaUnavailable,
           input.readiness.resetEstimationMode != .allowFiveHourEstimate {
            if isStale(quotaWindow, now: input.now) {
                return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .staleProviderState))
            }
            return .unavailable
        }
        guard case let .limitReached(resetAt) = quotaWindow.classification,
              let candidateResetAt = quotaWindow.resetAt ?? Optional(resetAt) else {
            return estimatedCandidate(from: input)
        }
        guard quotaWindow.confidence != .unknown else {
            return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .unknownStrictMode))
        }
        if quotaWindow.confidence == .estimatedFiveHour,
           input.readiness.resetEstimationMode != .allowFiveHourEstimate {
            return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .unknownStrictMode))
        }
        let event = QuotaResetWindowEvent(
            eventId: QuotaResetWindowEvent.resetWindowId(tool: input.tool, resetAt: candidateResetAt),
            tool: input.tool,
            resetAt: candidateResetAt,
            source: quotaWindow.source,
            confidence: quotaWindow.confidence
        )
        let source: QuotaReadinessDecisionSource = quotaWindow.confidence == .estimatedFiveHour
            ? .estimatedFiveHour
            : .quotaWindow
        return .candidate(QuotaReadinessCandidate(event: event, source: source))
    }

    private func estimatedCandidate(from input: QuotaReadinessInput) -> QuotaReadinessCandidateResult {
        guard input.readiness.resetEstimationMode == .allowFiveHourEstimate else {
            return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .unknownStrictMode))
        }
        guard let lastSuccessAt = input.lastSuccessAt else {
            return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .missingLastSuccessForEstimate))
        }
        let state = QuotaWindowState.estimatedFiveHour(
            tool: input.tool,
            lastSuccessAt: lastSuccessAt,
            observedAt: input.now
        )
        guard let resetAt = state.resetAt else {
            return .observeNeeded(QuotaReadinessObservation(tool: input.tool, reason: .invalidQuotaState))
        }
        let event = QuotaResetWindowEvent(
            eventId: QuotaResetWindowEvent.resetWindowId(tool: input.tool, resetAt: resetAt),
            tool: input.tool,
            resetAt: resetAt,
            source: state.source,
            confidence: state.confidence
        )
        return .candidate(QuotaReadinessCandidate(event: event, source: .estimatedFiveHour))
    }

    private func waitForActivity(
        _ activity: ActivityGateResult,
        candidate: QuotaResetWindowEvent,
        readiness: WindowReadinessSettings
    ) -> QuotaReadinessWait? {
        switch activity {
        case .active:
            return nil
        case .idle(let seconds):
            guard readiness.activeOnly else {
                return nil
            }
            return QuotaReadinessWait(reason: .idle(seconds: seconds), nextCandidate: candidate, source: .activityGate)
        case .activityUnavailable:
            guard readiness.activeOnly else {
                return nil
            }
            return QuotaReadinessWait(reason: .activityUnavailable, nextCandidate: candidate, source: .activityGate)
        case .suppressedPowerState(let reason):
            return QuotaReadinessWait(
                reason: .suppressedPowerState(reason),
                nextCandidate: candidate,
                source: .activityGate
            )
        }
    }

    private func isStale(_ state: QuotaWindowState, now: Date) -> Bool {
        now.timeIntervalSince(state.observedAt) >= staleProviderStateSeconds
    }

    private func isProviderBlocked(_ state: QuotaWindowState) -> Bool {
        if state.confidence == .blocked {
            return true
        }
        switch state.classification {
        case .authRequired, .apiBillingEnvPresent, .usageLimitNoReset:
            return true
        case .sent, .limitReached, .quotaUnavailable, .unknownFailure:
            return false
        }
    }

    private func cooldownUntil(_ input: QuotaReadinessInput) -> Date? {
        guard let lastSentAt = input.lastSentAt else {
            return nil
        }
        return lastSentAt.addingTimeInterval(TimeInterval(input.readiness.minimumSendCooldownMinutes * 60))
    }
}

private struct QuotaReadinessCandidate: Equatable, Sendable {
    let event: QuotaResetWindowEvent; let source: QuotaReadinessDecisionSource
}

private enum QuotaReadinessCandidateResult: Equatable, Sendable {
    case candidate(QuotaReadinessCandidate), blocked, unavailable, observeNeeded(QuotaReadinessObservation)
}
