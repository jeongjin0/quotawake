import Foundation

public struct QuotaReadinessInput: Equatable, Sendable {
    public let tool: ToolKind
    public let toolSettings: ToolSettings
    public let quotaWindow: QuotaWindowState?
    public let activity: ActivityGateResult
    public let readiness: WindowReadinessSettings
    public let now: Date
    public let lastSuccessAt: Date?
    public let lastSentAt: Date?
    public let completedResetWindowEventIds: Set<String>

    public init(
        tool: ToolKind,
        toolSettings: ToolSettings,
        quotaWindow: QuotaWindowState?,
        activity: ActivityGateResult,
        readiness: WindowReadinessSettings,
        now: Date,
        lastSuccessAt: Date? = nil,
        lastSentAt: Date? = nil,
        completedResetWindowEventIds: Set<String> = []
    ) {
        self.tool = tool
        self.toolSettings = toolSettings
        self.quotaWindow = quotaWindow
        self.activity = activity
        self.readiness = readiness
        self.now = now
        self.lastSuccessAt = lastSuccessAt
        self.lastSentAt = lastSentAt
        self.completedResetWindowEventIds = completedResetWindowEventIds
    }
}

public struct QuotaResetWindowEvent: Equatable, Sendable {
    public let eventId: String
    public let tool: ToolKind
    public let resetAt: Date
    public let source: QuotaWindowSource
    public let confidence: QuotaWindowConfidence

    public init(
        eventId: String,
        tool: ToolKind,
        resetAt: Date,
        source: QuotaWindowSource,
        confidence: QuotaWindowConfidence
    ) {
        self.eventId = eventId
        self.tool = tool
        self.resetAt = resetAt
        self.source = source
        self.confidence = confidence
    }

    public static func resetWindowId(tool: ToolKind, resetAt: Date) -> String {
        "reset-window-\(tool.rawValue)-\(ISO8601DateFormatter().string(from: resetAt))"
    }
}

public enum QuotaReadinessDecision: Equatable, Sendable {
    case send(QuotaResetWindowEvent)
    case wait(QuotaReadinessWait)
    case observeNeeded(QuotaReadinessObservation)
}

public struct QuotaReadinessWait: Equatable, Sendable {
    public let reason: QuotaReadinessSkipReason
    public let nextCandidate: QuotaResetWindowEvent?
    public let source: QuotaReadinessDecisionSource

    public init(
        reason: QuotaReadinessSkipReason,
        nextCandidate: QuotaResetWindowEvent?,
        source: QuotaReadinessDecisionSource
    ) {
        self.reason = reason
        self.nextCandidate = nextCandidate
        self.source = source
    }
}

public struct QuotaReadinessObservation: Equatable, Sendable {
    public let tool: ToolKind
    public let reason: QuotaReadinessObserveReason

    public init(tool: ToolKind, reason: QuotaReadinessObserveReason) { self.tool = tool; self.reason = reason }
}

public enum QuotaReadinessSkipReason: Equatable, Sendable {
    case toolDisabled
    case idle(seconds: TimeInterval)
    case activityUnavailable
    case suppressedPowerState(ActivityPowerStateSuppressionReason)
    case resetNotDue
    case providerBlocked
    case quotaUnavailable
    case duplicateResetWindow
    case cooldown(until: Date)
}

public enum QuotaReadinessObserveReason: Equatable, Sendable {
    case unknownStrictMode
    case missingLastSuccessForEstimate
    case invalidQuotaState
    case staleProviderState
}

public enum QuotaReadinessDecisionSource: String, Codable, Equatable, Sendable {
    case toolSettings
    case activityGate
    case quotaWindow
    case estimatedFiveHour
    case providerState
    case idempotency
    case cooldown
}
