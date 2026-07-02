import Foundation

/// The single source of truth for secret-redaction rules applied before
/// anything is written to disk. `RunLogSanitizer` and `QuotaWindowSanitizer`
/// shape their output differently (multi-line log summaries vs one-line quota
/// summaries) but must never diverge on WHAT counts as a secret — a leak
/// pattern fixed in one surface used to stay leakable in the other.
enum SecretRedaction {
    /// Keywords that mark a line as sensitive when no structured pattern
    /// already redacted it (used by the run-log line-blanking pass).
    static let sensitiveLineKeywords = [
        "api_key",
        "apikey",
        "token",
        "authorization",
        "bearer",
        "cookie",
        "password",
        "secret"
    ]

    /// Structured secret patterns, ordered so specific shapes run before the
    /// generic key/value catch-all.
    static func patterns(token: String) -> [(pattern: String, replacement: String)] {
        [
            (#"(?i)Bearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer \(token)"),
            (#"(?i)(sk-(?:ant|proj)?-[A-Za-z0-9_-]+)"#, token),
            (#"\bsk-[A-Za-z0-9._-]{12,}\b"#, token),
            (#"(?i)(ANTHROPIC_API_KEY|OPENAI_API_KEY|AZURE_OPENAI_API_KEY)=\S+"#, "$1=\(token)"),
            (#"(?i)(Cookie:\s*)[^\n\r]+"#, "$1\(token)"),
            (#"(?i)\b(session[_ -]?id|sessionid)(\s*[:=]?\s*)"?[A-Za-z0-9][A-Za-z0-9._:-]*"?"#, "$1$2\(token)"),
            (#"(?i)\bsession(\s*[:=]\s*)"?sess[A-Za-z0-9._:-]*"?"#, "session$1\(token)"),
            (##"(?i)("?(?:authorization|api[_-]?key|cookie|token|transcript|project|password|secret)"?\s*[:=]\s*)"?[^",\n\r}]+"?"##, "$1\(token)")
        ]
    }

    static func applyPatterns(_ text: String, token: String) -> String {
        var value = text
        for (pattern, replacement) in patterns(token: token) {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }
}
