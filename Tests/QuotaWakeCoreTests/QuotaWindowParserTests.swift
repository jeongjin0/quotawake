import XCTest
@testable import QuotaWakeCore

final class QuotaWindowParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_512_800)

    func testParseExactResetTimestampWhenLimitMessageIncludesISODate() throws {
        let state = QuotaWindowParser.parse(
            tool: .codex,
            source: .cliMessageParser,
            stdout: "usage limit reached; reset at 2026-06-29T05:30:00Z; Authorization: Bearer sk-proj-fake",
            stderr: "",
            exitCode: 1,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.confidence, .exactReset)
        XCTAssertEqual(state.resetAt, try XCTUnwrap(Self.iso.date(from: "2026-06-29T05:30:00Z")))
        XCTAssertTrue(state.summary.contains("<redacted>"))
        XCTAssertFalse(state.summary.contains("sk-proj-fake"))
    }

    func testParseSummaryRedactsBareGenericOpenAISecret() {
        let secret = "sk-fakeGenericSecret1234567890"
        let state = QuotaWindowParser.parse(
            tool: .codex,
            source: .cliMessageParser,
            stdout: "usage limit reached for this plan; diagnostic \(secret)",
            stderr: "",
            exitCode: 1,
            timedOut: false,
            observedAt: now
        )

        XCTAssertTrue(state.summary.contains("<redacted>"))
        XCTAssertFalse(state.summary.contains(secret))
    }

    func testParseSummaryRedactsClaudeArtifactFields() {
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .claudeUsageProbe,
            stdout: """
            Current session: 64% used. Resets at 2026-06-29T05:30:00Z.
            session_id=019f0b09-52c1-7443-bc80-0bdde9c5d918
            transcript: user asked about private repository setup
            project: /Users/example/.claude/projects/private-workspace
            token=raw-claude-token-123
            """,
            stderr: "",
            exitCode: 0,
            timedOut: false,
            observedAt: now
        )

        XCTAssertTrue(state.summary.contains("64% used"))
        XCTAssertTrue(state.summary.contains("<redacted>"))
        XCTAssertFalse(state.summary.contains("019f0b09-52c1-7443-bc80-0bdde9c5d918"))
        XCTAssertFalse(state.summary.contains("private repository setup"))
        XCTAssertFalse(state.summary.contains("/Users/example/.claude/projects/private-workspace"))
        XCTAssertFalse(state.summary.contains("raw-claude-token-123"))
    }

    func testParseClaudeCurrentSessionHumanResetAsObservedFiveHourWindow() throws {
        let observedAt = try XCTUnwrap(Self.iso.date(from: "2026-06-29T07:15:00Z"))
        let resetAt = try XCTUnwrap(Self.iso.date(from: "2026-06-29T09:10:00Z"))
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .claudeUsageProbe,
            stdout: """
            You are currently using your subscription to power your Claude Code usage.
            Current session: 22% used · resets Jun 29 at 6:10pm (Asia/Seoul)
            Current week: usage remains available.
            """,
            stderr: "",
            exitCode: 0,
            timedOut: false,
            observedAt: observedAt
        )

        XCTAssertEqual(state.confidence, .observedLocalQuota)
        XCTAssertEqual(state.classification, .limitReached(resetAt: resetAt))
        XCTAssertEqual(state.resetAt, resetAt)
        XCTAssertEqual(state.usedPercent, 22)
        XCTAssertEqual(state.remainingPercent, 78)
        XCTAssertEqual(state.windowLabel, "5h")
    }

    func testParseClaudeCurrentWeekPopulatesWeeklyWindow() throws {
        let observedAt = try XCTUnwrap(Self.iso.date(from: "2026-06-29T07:15:00Z"))
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .claudeUsageProbe,
            stdout: """
            Current session: 22% used · resets Jun 29 at 6:10pm (Asia/Seoul)
            Current week (all models): 47% used · resets Jul 3 at 9:00am (Asia/Seoul)
            """,
            stderr: "",
            exitCode: 0,
            timedOut: false,
            observedAt: observedAt
        )

        let weeklyReset = try XCTUnwrap(state.weeklyResetAt)
        XCTAssertEqual(state.weeklyUsedPercent, 47)
        XCTAssertEqual(state.weeklyRemainingPercent, 53)
        XCTAssertEqual(state.weeklyWindowLabel, "Weekly")
        XCTAssertGreaterThan(weeklyReset, observedAt)
    }

    func testUsageInsightPercentDoesNotBecomeFiveHourQuotaPercent() {
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .claudeUsageProbe,
            stdout: "35% of your usage was at >150k context and 12% of your usage was from tool calls.",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.classification, .sent)
        XCTAssertNil(state.usedPercent)
        XCTAssertNil(state.resetAt)
    }

    func testTimedOutClaudeUsageProbeStillUsesCurrentSessionSignal() throws {
        let observedAt = try XCTUnwrap(Self.iso.date(from: "2026-06-29T07:15:00Z"))
        let resetAt = try XCTUnwrap(Self.iso.date(from: "2026-06-29T09:10:00Z"))
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .claudeUsageProbe,
            stdout: "Current session: 22% used · resets Jun 29 at 6:10pm (Asia/Seoul)",
            stderr: "",
            exitCode: nil,
            timedOut: true,
            observedAt: observedAt
        )

        XCTAssertEqual(state.confidence, .observedLocalQuota)
        XCTAssertEqual(state.classification, .limitReached(resetAt: resetAt))
        XCTAssertEqual(state.resetAt, resetAt)
        XCTAssertEqual(state.usedPercent, 22)
    }

    func testQuotaWindowStateStorePersistsRedactedGenericOpenAISecret() throws {
        let secret = "sk-fakePersistedSecret1234567890"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeParserTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = QuotaWakePaths(applicationSupportDirectory: directory)
        let store = QuotaWindowStateStore(paths: paths)
        let state = QuotaWindowState(
            tool: .codex,
            source: .cliMessageParser,
            confidence: .blocked,
            classification: .usageLimitNoReset,
            observedAt: now,
            summary: "provider emitted \(secret) while reporting usage limit"
        )

        try store.save(state)

        let persisted = try String(
            contentsOf: paths.quotaStateDirectory.appendingPathComponent("codex.json"),
            encoding: .utf8
        )
        XCTAssertTrue(persisted.contains("<redacted>"))
        XCTAssertFalse(persisted.contains(secret))
    }

    func testParseRelativeResetTextWhenLimitMessageIncludesDuration() throws {
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .cliMessageParser,
            stdout: "Claude usage limit reached. Try again in 1 hour 15 minutes.",
            stderr: "",
            exitCode: 1,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.confidence, .exactReset)
        XCTAssertEqual(state.resetAt, now.addingTimeInterval(4_500))
        XCTAssertEqual(state.classification, .limitReached(resetAt: now.addingTimeInterval(4_500)))
    }

    func testParseUsageLimitWithoutTimestampWhenLimitHasNoResetHint() {
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .cliMessageParser,
            stdout: "usage limit reached for this plan",
            stderr: "",
            exitCode: 1,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.confidence, .blocked)
        XCTAssertEqual(state.classification, .usageLimitNoReset)
    }

    func testParseAuthRequiredWhenCliRequestsLogin() {
        let state = QuotaWindowParser.parse(
            tool: .codex,
            source: .cliMessageParser,
            stdout: "",
            stderr: "authentication required; please login again",
            exitCode: 1,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.confidence, .blocked)
        XCTAssertEqual(state.classification, .authRequired)
    }

    func testParseApiBillingEnvPresentWhenProviderWarnsAboutApiKey() {
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .cliMessageParser,
            stdout: "ANTHROPIC_API_KEY environment variable is set",
            stderr: "",
            exitCode: 1,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.confidence, .blocked)
        XCTAssertEqual(state.classification, .apiBillingEnvPresent)
    }

    func testParseNormalSuccessWhenCliExitIsZero() {
        let state = QuotaWindowParser.parse(
            tool: .codex,
            source: .cliMessageParser,
            stdout: "readiness prompt sent",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.confidence, .unknown)
        XCTAssertEqual(state.classification, .sent)
    }

    func testParseNoisyUnrelatedStderrDoesNotOverrideNormalSuccess() {
        let state = QuotaWindowParser.parse(
            tool: .claude,
            source: .cliMessageParser,
            stdout: "ok",
            stderr: "warning: terminal resize ignored",
            exitCode: 0,
            timedOut: false,
            observedAt: now
        )

        XCTAssertEqual(state.classification, .sent)
        XCTAssertFalse(state.summary.contains("Bearer"))
    }

    private static let iso = ISO8601DateFormatter()
}
