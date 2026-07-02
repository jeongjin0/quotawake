import Foundation

public enum QuotaWindowConfidence: String, Codable, Equatable, Sendable {
    case observedLocalQuota
    case exactReset
    case estimatedFiveHour
    case unknown
    case blocked
}

public enum QuotaWindowSource: String, Codable, Equatable, Sendable {
    case codexLocalAppServer
    case claudeUsageProbe
    case cliMessageParser
    case estimatedLastSuccess
    case none
}

public enum QuotaSourceClassification: Codable, Equatable, Sendable {
    case sent
    case limitReached(resetAt: Date)
    case authRequired
    case apiBillingEnvPresent
    case usageLimitNoReset
    case quotaUnavailable
    case unknownFailure
}

public struct QuotaWindowState: Codable, Equatable, Sendable {
    public let tool: ToolKind
    public let source: QuotaWindowSource
    public let confidence: QuotaWindowConfidence
    public let classification: QuotaSourceClassification
    public let observedAt: Date
    public let resetAt: Date?
    public let usedPercent: Double?
    public let remainingPercent: Double?
    public let windowLabel: String?
    public let weeklyUsedPercent: Double?
    public let weeklyRemainingPercent: Double?
    public let weeklyResetAt: Date?
    public let weeklyWindowLabel: String?
    public let summary: String

    public init(
        tool: ToolKind,
        source: QuotaWindowSource,
        confidence: QuotaWindowConfidence,
        classification: QuotaSourceClassification,
        observedAt: Date,
        resetAt: Date? = nil,
        usedPercent: Double? = nil,
        remainingPercent: Double? = nil,
        windowLabel: String? = nil,
        weeklyUsedPercent: Double? = nil,
        weeklyRemainingPercent: Double? = nil,
        weeklyResetAt: Date? = nil,
        weeklyWindowLabel: String? = nil,
        summary: String
    ) {
        self.tool = tool
        self.source = source
        self.confidence = confidence
        self.classification = classification
        self.observedAt = observedAt
        self.resetAt = resetAt
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.windowLabel = windowLabel
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyResetAt = weeklyResetAt
        self.weeklyWindowLabel = weeklyWindowLabel
        self.summary = QuotaWindowSanitizer.sanitize(summary)
    }

    public static func estimatedFiveHour(
        tool: ToolKind,
        lastSuccessAt: Date,
        observedAt: Date
    ) -> QuotaWindowState {
        let resetAt = lastSuccessAt.addingTimeInterval(5 * 60 * 60)
        return QuotaWindowState(
            tool: tool,
            source: .estimatedLastSuccess,
            confidence: .estimatedFiveHour,
            classification: .limitReached(resetAt: resetAt),
            observedAt: observedAt,
            resetAt: resetAt,
            summary: "estimated from last successful readiness send plus five hours"
        )
    }
}

public enum QuotaWindowSanitizer {
    public static func sanitize(_ raw: String, limit: Int = 500) -> String {
        var value = SecretRedaction.applyPatterns(SecretRedaction.stripANSI(raw), token: "<redacted>")
        value = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if value.count > limit {
            return String(value.prefix(limit)) + "..."
        }
        return value
    }
}
