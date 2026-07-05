import Foundation

public enum QuotaWindowParser {
    public static func parse(
        tool: ToolKind,
        source: QuotaWindowSource,
        stdout: String,
        stderr: String,
        exitCode: Int?,
        timedOut: Bool,
        observedAt: Date
    ) -> QuotaWindowState {
        let text = [stdout, stderr].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        let lowered = text.lowercased()
        let summary = summary(stdout: stdout, stderr: stderr)

        if containsAny(lowered, ["anthropic_api_key", "openai_api_key", "azure_openai_api_key", "api billing", "api key environment"]) {
            return state(tool, source, .blocked, .apiBillingEnvPresent, observedAt, nil, usedPercent(in: text), summary)
        }
        if containsAny(lowered, ["authentication required", "auth required", "not logged in", "login required", "please login", "please log in"]) {
            return state(tool, source, .blocked, .authRequired, observedAt, nil, usedPercent(in: text), summary)
        }
        if let currentSession = currentSessionQuota(in: text, observedAt: observedAt) {
            let week = currentWeekQuota(in: text, observedAt: observedAt)
            return QuotaWindowState(
                tool: tool,
                source: source,
                confidence: .observedLocalQuota,
                classification: .limitReached(resetAt: currentSession.resetAt),
                observedAt: observedAt,
                resetAt: currentSession.resetAt,
                usedPercent: currentSession.usedPercent,
                remainingPercent: max(0, min(100, 100 - currentSession.usedPercent)),
                windowLabel: "5h",
                weeklyUsedPercent: week?.usedPercent,
                weeklyRemainingPercent: week.map { max(0, min(100, 100 - $0.usedPercent)) },
                weeklyResetAt: week?.resetAt,
                weeklyWindowLabel: week != nil ? "Weekly" : nil,
                summary: summary.isEmpty ? "current 5h quota window observed" : summary
            )
        }
        if containsAny(lowered, ["usage limit", "rate limit", "limit reached", "try again", "resets at", "reset at", "resets in"]) {
            if let resetAt = exactReset(in: text) ?? relativeReset(in: lowered, observedAt: observedAt) {
                return state(tool, source, .exactReset, .limitReached(resetAt: resetAt), observedAt, resetAt, usedPercent(in: text), summary)
            }
            return state(tool, source, .blocked, .usageLimitNoReset, observedAt, nil, usedPercent(in: text), summary)
        }
        if timedOut {
            return state(tool, source, .unknown, .unknownFailure, observedAt, nil, nil, summary.isEmpty ? "probe timed out" : "probe timed out; \(summary)")
        }
        if exitCode == 0 {
            return state(tool, source, .unknown, .sent, observedAt, nil, usedPercent(in: text), summary)
        }
        return state(tool, source, .unknown, .unknownFailure, observedAt, nil, usedPercent(in: text), summary)
    }

    // Phrases that only appear in an actual provider limit banner, as opposed
    // to keyword-level matches ("rate limit", "try again", "resets in") that a
    // normal model reply can contain. Callers that must not misgrade a
    // delivered reply (ToolRunner's exit-0 demotion) require one of these on
    // top of the classification.
    public static func containsExplicitLimitBanner(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["usage limit", "limit reached", "hit your limit"].contains { lowered.contains($0) }
    }

    static func exactReset(in text: String) -> Date? {
        matches(#"20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})"#, in: text)
            .compactMap(isoDate)
            .first
    }

    static func relativeReset(in text: String, observedAt: Date) -> Date? {
        // Anchor to the reset phrase so an unrelated duration earlier in the
        // message ("your 5h limit ... resets in 3 hours") cannot win. Without
        // an anchor phrase, fall back to scanning the whole text.
        let scope = matches(#"(?:resets?|try\s+again)\s+in\b([^.\n]*)"#, in: text).first ?? text
        let hours = number(beforeUnits: "(?:h|hr|hrs|hour|hours)", in: scope)
        let minutes = number(beforeUnits: "(?:m|min|mins|minute|minutes)", in: scope)
        let seconds = number(beforeUnits: "(?:s|sec|secs|second|seconds)", in: scope)
        let total = (hours * 3_600) + (minutes * 60) + seconds
        guard total > 0 else {
            return nil
        }
        return observedAt.addingTimeInterval(TimeInterval(total))
    }

    static func isoDate(_ value: String) -> Date? {
        iso.date(from: value) ?? isoFractional.date(from: value)
    }

    static func usedPercent(in text: String) -> Double? {
        currentSessionUsedPercent(in: text)
            ?? matches(#"\b(\d{1,3}(?:\.\d+)?)\s*%\s*(?:used|usage)\b"#, in: text)
            .compactMap(Double.init)
            .first
    }

    private static let iso = ISO8601DateFormatter()

    // The default ISO8601DateFormatter rejects fractional seconds, so
    // "…T13:00:00.123Z" would match the reset regex but fail to parse.
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct CurrentSessionQuota {
        let usedPercent: Double
        let resetAt: Date
    }

    private static func currentSessionQuota(in text: String, observedAt: Date) -> CurrentSessionQuota? {
        let pattern = #"current\s+session:\s*(\d{1,3}(?:\.\d+)?)\s*%\s*used\b.*?\bresets\s+([A-Za-z]{3,9})\s+(\d{1,2})\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?:\s*\(([^)]+)\))?"#
        guard let captures = firstCaptureGroups(pattern, in: text, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              captures.count >= 6,
              let usedPercentText = captures[0],
              let usedPercent = Double(usedPercentText),
              let month = captures[1],
              let day = captures[2],
              let hour = captures[3],
              let meridiem = captures[5],
              let resetAt = localResetDate(
                  month: month,
                  day: day,
                  hour: hour,
                  minute: captures[4],
                  meridiem: meridiem,
                  timeZoneIdentifier: captures.count > 6 ? captures[6] : nil,
                  observedAt: observedAt
              )
        else {
            return nil
        }

        return CurrentSessionQuota(usedPercent: usedPercent, resetAt: resetAt)
    }

    private struct WeekQuota {
        let usedPercent: Double
        let resetAt: Date?
    }

    // Claude `/usage` reports a weekly window ("Current week ...: NN% used, resets ...")
    // beneath the current session. The reset clause is best-effort.
    private static func currentWeekQuota(in text: String, observedAt: Date) -> WeekQuota? {
        guard let usedPercent = matches(#"current\s+week[^:]*:\s*(\d{1,3}(?:\.\d+)?)\s*%\s*used\b"#, in: text)
            .compactMap(Double.init)
            .first else {
            return nil
        }

        let resetPattern = #"current\s+week[^:]*:\s*\d{1,3}(?:\.\d+)?\s*%\s*used\b.*?\bresets\s+([A-Za-z]{3,9})\s+(\d{1,2})\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?:\s*\(([^)]+)\))?"#
        var resetAt: Date?
        if let captures = firstCaptureGroups(resetPattern, in: text, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           captures.count >= 5,
           let month = captures[0],
           let day = captures[1],
           let hour = captures[2],
           let meridiem = captures[4] {
            resetAt = localResetDate(
                month: month,
                day: day,
                hour: hour,
                minute: captures[3],
                meridiem: meridiem,
                timeZoneIdentifier: captures.count > 5 ? captures[5] : nil,
                observedAt: observedAt
            )
        }
        return WeekQuota(usedPercent: usedPercent, resetAt: resetAt)
    }

    private static func currentSessionUsedPercent(in text: String) -> Double? {
        matches(#"current\s+session:\s*(\d{1,3}(?:\.\d+)?)\s*%\s*used\b"#, in: text)
            .compactMap(Double.init)
            .first
    }

    private static func localResetDate(
        month: String,
        day: String,
        hour: String,
        minute: String?,
        meridiem: String,
        timeZoneIdentifier: String?,
        observedAt: Date
    ) -> Date? {
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let observedYear = calendar.component(.year, from: observedAt)
        let minuteText = minute ?? "00"
        let normalized = "\(observedYear) \(month) \(day) \(hour):\(minuteText) \(meridiem.uppercased())"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        let parsed = ["yyyy MMM d h:mm a", "yyyy MMMM d h:mm a"].lazy.compactMap { format -> Date? in
            formatter.dateFormat = format
            return formatter.date(from: normalized)
        }.first

        guard let parsed else {
            return nil
        }

        // Month/day-only resets near the December/January boundary belong to
        // next year. Use a one-day threshold: a reset that passed moments ago
        // (probe raced the boundary, stale screen) must stay "due now" rather
        // than jump a year into the future and wedge the candidate.
        if parsed < observedAt.addingTimeInterval(-86_400) {
            return calendar.date(byAdding: .year, value: 1, to: parsed) ?? parsed
        }
        return parsed
    }

    private static func state(
        _ tool: ToolKind,
        _ source: QuotaWindowSource,
        _ confidence: QuotaWindowConfidence,
        _ classification: QuotaSourceClassification,
        _ observedAt: Date,
        _ resetAt: Date?,
        _ usedPercent: Double?,
        _ summary: String
    ) -> QuotaWindowState {
        QuotaWindowState(
            tool: tool,
            source: source,
            confidence: confidence,
            classification: classification,
            observedAt: observedAt,
            resetAt: resetAt,
            usedPercent: usedPercent,
            summary: summary.isEmpty ? "no quota signal" : summary
        )
    }

    private static func summary(stdout: String, stderr: String) -> String {
        let preferred = stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stderr : stdout
        return QuotaWindowSanitizer.sanitize(preferred)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func number(beforeUnits units: String, in text: String) -> Int {
        guard let match = matches(#"\b(\d+)\s*"# + units + #"\b"#, in: text).first else {
            return 0
        }
        return Int(match) ?? 0
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let swiftRange = Range(capture, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }

    private static func firstCaptureGroups(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options
    ) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            let capture = match.range(at: index)
            guard let swiftRange = Range(capture, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }
}
