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
        var value = raw.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        let replacements = [
            #"(?i)Bearer\s+[A-Za-z0-9._~+/=-]+"#: "Bearer <redacted>",
            #"(?i)(sk-(?:ant|proj)?-[A-Za-z0-9_-]+)"#: "<redacted>",
            #"\bsk-[A-Za-z0-9._-]{12,}\b"#: "<redacted>",
            #"(?i)(ANTHROPIC_API_KEY|OPENAI_API_KEY|AZURE_OPENAI_API_KEY)=\S+"#: "$1=<redacted>",
            #"(?i)(Cookie:\s*)[^\n\r]+"#: "$1<redacted>",
            #"(?i)\b(session[_ -]?id|sessionid)(\s*[:=]?\s*)"?[A-Za-z0-9][A-Za-z0-9._:-]*"?"#: "$1$2<redacted>",
            #"(?i)\bsession(\s*[:=]\s*)"?sess[A-Za-z0-9._:-]*"?"#: "session$1<redacted>",
            ##"(?i)("?(?:authorization|api[_-]?key|cookie|token|transcript|project)"?\s*[:=]\s*)"?[^",\n\r}]+"?"##: "$1<redacted>"
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        value = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if value.count > limit {
            return String(value.prefix(limit)) + "..."
        }
        return value
    }
}
