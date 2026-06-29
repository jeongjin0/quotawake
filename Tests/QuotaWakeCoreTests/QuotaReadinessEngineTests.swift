import XCTest
@testable import QuotaWakeCore

final class QuotaReadinessEngineTests: XCTestCase {
    private let engine = QuotaReadinessEngine()
    private let resetAt = Date(timeIntervalSince1970: 1_782_690_600)
    private let now = Date(timeIntervalSince1970: 1_782_690_600)

    func testSendsWhenObservedLocalQuotaResetIsDueAndActivityIsActive() {
        let decision = engine.evaluate(input: input(
            quotaWindow: quotaWindow(confidence: .observedLocalQuota, resetAt: resetAt),
            activity: .active
        ))

        XCTAssertEqual(decision, .send(QuotaResetWindowEvent(
            eventId: "reset-window-codex-2026-06-28T23:50:00Z",
            tool: .codex,
            resetAt: resetAt,
            source: .codexLocalAppServer,
            confidence: .observedLocalQuota
        )))
    }

    func testWaitsWhenResetIsDueButActivityIsIdle() {
        let decision = engine.evaluate(input: input(
            quotaWindow: quotaWindow(confidence: .observedLocalQuota, resetAt: resetAt),
            activity: .idle(seconds: 301)
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .idle(seconds: 301),
            nextCandidate: event(resetAt: resetAt),
            source: .activityGate
        )))
    }

    func testWaitsWhenResetCandidateIsNotDue() {
        let futureReset = now.addingTimeInterval(60)

        let decision = engine.evaluate(input: input(
            quotaWindow: quotaWindow(confidence: .exactReset, resetAt: futureReset),
            activity: .active
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .resetNotDue,
            nextCandidate: event(resetAt: futureReset, confidence: .exactReset),
            source: .quotaWindow
        )))
    }

    func testRequestsObservationWhenQuotaIsUnknownInStrictMode() {
        let decision = engine.evaluate(input: input(
            quotaWindow: QuotaWindowState(
                tool: .codex,
                source: .none,
                confidence: .unknown,
                classification: .unknownFailure,
                observedAt: now,
                summary: "unknown"
            ),
            activity: .active,
            readiness: WindowReadinessSettings(resetEstimationMode: .localSignalsOnly)
        ))

        XCTAssertEqual(decision, .observeNeeded(QuotaReadinessObservation(
            tool: .codex,
            reason: .unknownStrictMode
        )))
    }

    func testDoesNotSendUnknownConfidenceLimitReachedInStrictMode() {
        let decision = engine.evaluate(input: input(
            quotaWindow: QuotaWindowState(
                tool: .codex,
                source: .none,
                confidence: .unknown,
                classification: .limitReached(resetAt: resetAt),
                observedAt: now,
                resetAt: resetAt,
                summary: "unknown reset candidate"
            ),
            activity: .active,
            readiness: WindowReadinessSettings(resetEstimationMode: .localSignalsOnly)
        ))

        XCTAssertEqual(decision, .observeNeeded(QuotaReadinessObservation(
            tool: .codex,
            reason: .unknownStrictMode
        )))
    }

    func testDoesNotSendPersistedEstimatedFiveHourCandidateInStrictMode() {
        let decision = engine.evaluate(input: input(
            quotaWindow: QuotaWindowState(
                tool: .codex,
                source: .estimatedLastSuccess,
                confidence: .estimatedFiveHour,
                classification: .limitReached(resetAt: resetAt),
                observedAt: now,
                resetAt: resetAt,
                summary: "estimated reset candidate"
            ),
            activity: .active,
            readiness: WindowReadinessSettings(resetEstimationMode: .localSignalsOnly)
        ))

        XCTAssertEqual(decision, .observeNeeded(QuotaReadinessObservation(
            tool: .codex,
            reason: .unknownStrictMode
        )))
    }

    func testSchedulesEstimatedFiveHourCandidateFromLastSuccessWhenQuotaIsUnknownAndEstimationAllowed() {
        let lastSuccessAt = now.addingTimeInterval(-4 * 60 * 60)
        let estimatedReset = lastSuccessAt.addingTimeInterval(5 * 60 * 60)

        let decision = engine.evaluate(input: input(
            quotaWindow: nil,
            activity: .active,
            readiness: WindowReadinessSettings(resetEstimationMode: .allowFiveHourEstimate),
            lastSuccessAt: lastSuccessAt
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .resetNotDue,
            nextCandidate: event(
                resetAt: estimatedReset,
                source: .estimatedLastSuccess,
                confidence: .estimatedFiveHour
            ),
            source: .estimatedFiveHour
        )))
    }

    func testDoesNotSendWhenProviderIsBlocked() {
        let decision = engine.evaluate(input: input(
            quotaWindow: QuotaWindowState(
                tool: .codex,
                source: .cliMessageParser,
                confidence: .blocked,
                classification: .authRequired,
                observedAt: now,
                summary: "authentication required"
            ),
            activity: .active
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .providerBlocked,
            nextCandidate: nil,
            source: .providerState
        )))
    }

    func testWaitsWithoutAutoObserveWhenLocalQuotaSourceIsUnavailable() {
        let decision = engine.evaluate(input: input(
            quotaWindow: QuotaWindowState(
                tool: .codex,
                source: .codexLocalAppServer,
                confidence: .unknown,
                classification: .quotaUnavailable,
                observedAt: now,
                summary: "Codex local quota source is unavailable"
            ),
            activity: .active,
            readiness: WindowReadinessSettings(resetEstimationMode: .localSignalsOnly)
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .quotaUnavailable,
            nextCandidate: nil,
            source: .providerState
        )))
    }

    func testSkipsDuplicateResetWindowEventId() {
        let resetEvent = event(resetAt: resetAt)
        let decision = engine.evaluate(input: input(
            quotaWindow: quotaWindow(confidence: .observedLocalQuota, resetAt: resetAt),
            activity: .active,
            completedResetWindowEventIds: [resetEvent.eventId]
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .duplicateResetWindow,
            nextCandidate: resetEvent,
            source: .idempotency
        )))
    }

    func testCooldownPreventsRepeatedSends() {
        let laterReset = now.addingTimeInterval(60)
        let decision = engine.evaluate(input: input(
            now: laterReset,
            quotaWindow: quotaWindow(confidence: .observedLocalQuota, resetAt: laterReset),
            activity: .active,
            readiness: WindowReadinessSettings(minimumSendCooldownMinutes: 30),
            lastSentAt: now.addingTimeInterval(-10 * 60)
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .cooldown(until: now.addingTimeInterval(20 * 60)),
            nextCandidate: event(resetAt: laterReset),
            source: .cooldown
        )))
    }

    func testDisabledToolDoesNotSend() {
        let decision = engine.evaluate(input: input(
            quotaWindow: quotaWindow(confidence: .observedLocalQuota, resetAt: resetAt),
            toolSettings: ToolSettings(enabled: false),
            activity: .active
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .toolDisabled,
            nextCandidate: nil,
            source: .toolSettings
        )))
    }

    func testSuppressedPowerStateDoesNotSend() {
        let decision = engine.evaluate(input: input(
            quotaWindow: quotaWindow(confidence: .observedLocalQuota, resetAt: resetAt),
            activity: .suppressedPowerState(reason: .darkWake)
        ))

        XCTAssertEqual(decision, .wait(QuotaReadinessWait(
            reason: .suppressedPowerState(.darkWake),
            nextCandidate: event(resetAt: resetAt),
            source: .activityGate
        )))
    }

    private func input(
        now: Date? = nil,
        quotaWindow: QuotaWindowState?,
        toolSettings: ToolSettings = ToolSettings(),
        activity: ActivityGateResult,
        readiness: WindowReadinessSettings = WindowReadinessSettings(),
        lastSuccessAt: Date? = nil,
        lastSentAt: Date? = nil,
        completedResetWindowEventIds: Set<String> = []
    ) -> QuotaReadinessInput {
        QuotaReadinessInput(
            tool: .codex,
            toolSettings: toolSettings,
            quotaWindow: quotaWindow,
            activity: activity,
            readiness: readiness,
            now: now ?? self.now,
            lastSuccessAt: lastSuccessAt,
            lastSentAt: lastSentAt,
            completedResetWindowEventIds: completedResetWindowEventIds
        )
    }

    private func quotaWindow(
        confidence: QuotaWindowConfidence,
        resetAt: Date
    ) -> QuotaWindowState {
        QuotaWindowState(
            tool: .codex,
            source: .codexLocalAppServer,
            confidence: confidence,
            classification: .limitReached(resetAt: resetAt),
            observedAt: now,
            resetAt: resetAt,
            summary: "reset observed"
        )
    }

    private func event(
        resetAt: Date,
        source: QuotaWindowSource = .codexLocalAppServer,
        confidence: QuotaWindowConfidence = .observedLocalQuota
    ) -> QuotaResetWindowEvent {
        QuotaResetWindowEvent(
            eventId: "reset-window-codex-\(Self.iso.string(from: resetAt))",
            tool: .codex,
            resetAt: resetAt,
            source: source,
            confidence: confidence
        )
    }

    private static let iso = ISO8601DateFormatter()
}
