import XCTest
@testable import QuotaWakeCore

final class AppUIModelsTests: XCTestCase {
    func testPopoverSummaryCoversNeedsSetupReadyPausedAndFailedStates() throws {
        let calendar = utcCalendar()
        let now = date("2026-06-28T05:30:00Z")
        let foundCommands = [
            command(tool: .claude, status: .found, path: "/usr/local/bin/claude"),
            command(tool: .codex, status: .found, path: "/usr/local/bin/codex")
        ]

        let setup = QuotaWakeUIStateBuilder.makePopoverState(
            settings: .default,
            logs: [],
            resolvedCommands: foundCommands,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(setup.statusTitle, "Setup needed")
        XCTAssertEqual(setup.statusTone, .warning)
        XCTAssertEqual(setup.readinessText, "Waiting for quota window signal")
        XCTAssertEqual(setup.enabledToolsText, "Claude and Codex enabled")
        XCTAssertEqual(setup.activityText, "Active-use gate on")

        var readySettings = AppSettings.default
        readySettings.firstRunCompleted = true
        readySettings.background.launchAtLoginEnabled = true

        var backgroundOffSettings = readySettings
        backgroundOffSettings.background.launchAtLoginEnabled = false
        let backgroundOff = QuotaWakeUIStateBuilder.makePopoverState(
            settings: backgroundOffSettings,
            logs: [],
            resolvedCommands: foundCommands,
            quotaStates: [quotaWindow(tool: .claude, confidence: .exactReset, resetAt: now)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(backgroundOff.statusTitle, "Paused")
        XCTAssertEqual(backgroundOff.statusDetail, "Background readiness is off.")
        XCTAssertEqual(backgroundOff.readinessText, "Background readiness off")

        let ready = QuotaWakeUIStateBuilder.makePopoverState(
            settings: readySettings,
            logs: [],
            resolvedCommands: foundCommands,
            quotaStates: [quotaWindow(tool: .claude, confidence: .exactReset, resetAt: now)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(ready.statusTitle, "Ready")
        XCTAssertEqual(ready.statusTone, .success)
        XCTAssertEqual(ready.readinessSummaryText, "Window readiness enabled · Active-use gate on")
        XCTAssertEqual(ready.readinessText, "Window readiness enabled")
        XCTAssertEqual(ready.fiveHourQuotaText, "Claude 0% left / Codex Unknown")
        XCTAssertEqual(ready.resetTimeText, "Claude 05:30 / Codex Unknown")
        XCTAssertEqual(ready.providerStates.first { $0.tool == .claude }?.resetCountdownText, "Due now")
        XCTAssertEqual(ready.runNowTitle, "Send")
        XCTAssertTrue(ready.canRunNow)

        var pausedSettings = readySettings
        pausedSettings.readiness.paused = true
        let paused = QuotaWakeUIStateBuilder.makePopoverState(
            settings: pausedSettings,
            logs: [],
            resolvedCommands: foundCommands,
            quotaStates: [quotaWindow(tool: .claude, confidence: .exactReset, resetAt: now)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(paused.statusTitle, "Paused")
        XCTAssertEqual(paused.statusTone, .neutral)
        XCTAssertEqual(paused.readinessSummaryText, "Window readiness paused · Active-use gate on")
        XCTAssertEqual(paused.readinessText, "Window readiness paused")
        XCTAssertTrue(paused.canRunNow)

        let failed = QuotaWakeUIStateBuilder.makePopoverState(
            settings: readySettings,
            logs: [log(status: .failed, tool: .codex, at: now, errorSummary: "CLI exited with code 2")],
            resolvedCommands: foundCommands,
            quotaStates: [quotaWindow(tool: .codex, confidence: .exactReset, resetAt: now.addingTimeInterval(300))],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(failed.statusTitle, "Last run failed")
        XCTAssertEqual(failed.statusTone, .error)
        XCTAssertEqual(failed.lastRunText, "Codex failed")
    }

    func testRecentActivityShowsOutcomesAndActionableSkipsButHidesHousekeeping() throws {
        let calendar = utcCalendar()
        let now = date("2026-06-28T05:30:00Z")
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        let foundCommands = [
            command(tool: .claude, status: .found, path: "/usr/local/bin/claude"),
            command(tool: .codex, status: .found, path: "/usr/local/bin/codex")
        ]

        // Interleave real outcomes with the housekeeping skips/observation probes
        // that dominate the log in practice. Only three slots are available, so a
        // naive "latest 3" would show nothing but noise.
        let logs = [
            log(status: .sent, tool: .claude, at: now.addingTimeInterval(-600)),
            log(status: .skippedMissedWindow, tool: .codex, at: now.addingTimeInterval(-500), skipReason: "idle"),
            log(status: .skippedMissedWindow, tool: .claude, at: now.addingTimeInterval(-400), skipReason: "cooldown"),
            log(status: .skippedMissedWindow, tool: .codex, at: now.addingTimeInterval(-300), skipReason: "quota_observed"),
            log(status: .skippedOverlap, tool: .claude, at: now.addingTimeInterval(-250)),
            log(status: .skippedMissedWindow, tool: .codex, at: now.addingTimeInterval(-200), skipReason: "provider_blocked"),
            log(status: .failed, tool: .codex, at: now.addingTimeInterval(-100), errorSummary: "CLI exited with code 2")
        ]

        let state = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: logs,
            resolvedCommands: foundCommands,
            now: now,
            calendar: calendar
        )

        // Newest-first: failed (outcome), provider_blocked (actionable skip), sent
        // (outcome). Idle/cooldown/observe/overlap housekeeping is filtered out.
        XCTAssertEqual(state.recentActivity.count, 3)
        XCTAssertEqual(state.recentActivity.map(\.statusText), ["failed", "skipped missed window", "sent"])
        XCTAssertTrue(state.recentActivity.contains { $0.summaryText.contains("provider_blocked") })
        XCTAssertFalse(state.recentActivity.contains { $0.summaryText.contains("idle") })
        XCTAssertFalse(state.recentActivity.contains { $0.summaryText.contains("cooldown") })
        XCTAssertFalse(state.recentActivity.contains { $0.statusText == "skipped overlap" })
    }

    func testToolStatesCoverMissingMalformedDisabledAndLongTextWithoutProhibitedCopy() throws {
        let calendar = utcCalendar()
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.tools.codex.manualPath = "/Users/example/.nvm/versions/node/v99.99.99/bin/codex-with-a-very-long-file-name-that-should-not-expand-the-ui"

        let commands = [
            command(tool: .claude, status: .missing, path: nil),
            command(tool: .codex, status: .manualPathInvalid, path: settings.tools.codex.manualPath)
        ]
        let popover = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [log(status: .timedOut, tool: .claude, at: date("2026-06-28T05:31:00Z"), errorSummary: longSummary())],
            resolvedCommands: commands,
            now: date("2026-06-28T05:30:00Z"),
            calendar: calendar
        )
        let uiSettings = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [log(status: .timedOut, tool: .claude, at: date("2026-06-28T05:31:00Z"), errorSummary: longSummary())],
            resolvedCommands: commands,
            appVersion: "0.0.0",
            calendar: calendar
        )

        XCTAssertFalse(popover.canRunNow)
        XCTAssertEqual(popover.statusTitle, "Setup needed")
        XCTAssertEqual(popover.statusDetail, "Choose CLI paths for enabled tools.")
        XCTAssertEqual(popover.statusTone, .warning)
        XCTAssertEqual(popover.toolStates.first { $0.tool == .claude }?.statusText, "Choose path")
        XCTAssertEqual(popover.toolStates.first { $0.tool == .codex }?.statusText, "Manual path invalid")
        XCTAssertTrue(popover.providerStates.isEmpty)
        XCTAssertLessThanOrEqual(popover.toolStates.first { $0.tool == .codex }?.pathText.count ?? 999, 78)
        XCTAssertTrue(popover.toolStates.first { $0.tool == .codex }?.pathText.contains("...") == true)
        XCTAssertLessThanOrEqual(uiSettings.logRows.first?.summaryText.count ?? 999, 120)
        XCTAssertEqual(uiSettings.providerStates.count, ToolKind.allCases.count)

        let claudeOnly = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [],
            resolvedCommands: [
                command(tool: .claude, status: .found, path: "/usr/local/bin/claude"),
                command(tool: .codex, status: .manualPathInvalid, path: settings.tools.codex.manualPath)
            ],
            quotaStates: [quotaWindow(tool: .claude, confidence: .exactReset, resetAt: date("2026-06-28T07:00:00Z"))],
            now: date("2026-06-28T05:30:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(claudeOnly.providerStates.map(\.tool), [.claude])
        XCTAssertEqual(claudeOnly.providerStates.first?.resetCountdownText, "1h 30m")

        settings.tools.codex.enabled = false
        let disabled = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [],
            resolvedCommands: commands,
            now: date("2026-06-28T05:30:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(disabled.toolStates.first { $0.tool == .codex }?.statusText, "Disabled")

        settings.tools.codex.enabled = true
        let nodeMissing = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [],
            resolvedCommands: [command(tool: .codex, status: .nodeRuntimeMissing, path: settings.tools.codex.manualPath)],
            now: date("2026-06-28T05:30:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(nodeMissing.toolStates.first { $0.tool == .codex }?.statusText, "Node runtime missing")
        XCTAssertEqual(nodeMissing.toolStates.first { $0.tool == .codex }?.detailText, "Node is required for this CLI.")

        let brokenExecutable = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [],
            resolvedCommands: [command(tool: .codex, status: .brokenExecutable, path: settings.tools.codex.manualPath)],
            now: date("2026-06-28T05:30:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(brokenExecutable.toolStates.first { $0.tool == .codex }?.statusText, "CLI check failed")
        XCTAssertEqual(brokenExecutable.toolStates.first { $0.tool == .codex }?.detailText, "Pick another CLI path or reinstall this CLI.")
        XCTAssertFalse(brokenExecutable.canRunNow)

        let visible = QuotaWakeUIStateBuilder.visibleStrings(popover: popover, settings: uiSettings)
            .joined(separator: "\n")
            .lowercased()
        for prohibited in ["window opened", "quota reset verified", "bypass", "extra usage", "schedule", "weekday", "06:00", "wake helper", "install helper"] {
            XCTAssertFalse(visible.contains(prohibited), "Visible UI copy contained \(prohibited)")
        }
    }

    func testSettingsStateListsPanesLogsAndWindowReadiness() throws {
        let calendar = utcCalendar()
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.readiness.activeOnly = true
        settings.readiness.idleThresholdSeconds = 180
        settings.readiness.minimumSendCooldownMinutes = 45
        settings.prompt = "hi"

        let state = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [log(status: .sent, tool: .claude, at: date("2026-06-28T05:30:00Z"))],
            resolvedCommands: [command(tool: .claude, status: .found, path: "/usr/local/bin/claude")],
            appVersion: "0.0.0",
            calendar: calendar
        )

        XCTAssertEqual(state.panes, SettingsPaneID.allCases)
        XCTAssertFalse(state.panes.map(\.rawValue).contains("schedule"))
        XCTAssertEqual(state.appVersionText, "Version 0.0.0")
        XCTAssertEqual(state.readinessSummary, "Active use, idle after 180s, cooldown 45m, local signals only")
        XCTAssertEqual(state.promptPreview, "hi")
        XCTAssertEqual(state.logRows.first?.statusText, "sent")

        settings.readiness.paused = true
        let paused = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [],
            resolvedCommands: [command(tool: .claude, status: .found, path: "/usr/local/bin/claude")],
            appVersion: "0.0.0",
            calendar: calendar
        )
        XCTAssertEqual(paused.backgroundText, "Session readiness paused")
        XCTAssertEqual(paused.readinessSummary, "Paused, active use, idle after 180s, cooldown 45m, local signals only")

        let skipped = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [RunLogEntry(
                eventId: "reset-window-codex-2026-06-28T23:50:00Z",
                scheduledAt: date("2026-06-28T23:50:00Z"),
                startedAt: date("2026-06-28T23:50:00Z"),
                endedAt: date("2026-06-28T23:50:00Z"),
                tool: .codex,
                commandPath: "/usr/local/bin/codex",
                status: .skippedMissedWindow,
                exitCode: nil,
                durationMs: 0,
                timedOut: false,
                stdoutSummary: "",
                stderrSummary: "",
                prompt: "hi",
                decisionSource: .activityGate,
                quotaConfidence: .exactReset,
                skipReason: "idle"
            )],
            resolvedCommands: [command(tool: .codex, status: .found, path: "/usr/local/bin/codex")],
            appVersion: "0.0.0",
            calendar: calendar
        )
        XCTAssertEqual(skipped.logRows.first?.summaryText, "skip idle, source activityGate, confidence exactReset")
    }

    func testReadinessProviderStatesCoverActiveIdleUnknownObservedAndMigration() throws {
        let calendar = utcCalendar()
        let now = date("2026-06-29T00:00:00Z")
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.background.launchAtLoginEnabled = true
        let commands = [
            command(tool: .claude, status: .found, path: "/usr/local/bin/claude"),
            command(tool: .codex, status: .found, path: "/usr/local/bin/codex")
        ]

        let active = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [],
            resolvedCommands: commands,
            quotaStates: [
                quotaWindow(tool: .claude, confidence: .exactReset, resetAt: date("2026-06-28T23:59:00Z")),
                quotaWindow(tool: .codex, confidence: .exactReset, resetAt: date("2026-06-28T23:59:00Z"))
            ],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(active.providerStatusText, "Reset candidate due")
        XCTAssertEqual(active.fiveHourQuotaText, "Claude 0% left / Codex 0% left")
        XCTAssertEqual(active.resetTimeText, "Claude 23:59 / Codex 23:59")
        XCTAssertEqual(active.nextResetText, "Claude 23:59 / Codex 23:59")
        XCTAssertEqual(active.confidenceText, "Exact reset")

        let observedLog = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [
                log(
                    status: .skippedMissedWindow,
                    tool: .claude,
                    at: now,
                    skipReason: "quota_observed",
                    stdoutSummary: "Current session: 22% used"
                )
            ],
            resolvedCommands: commands,
            quotaStates: [
                QuotaWindowState(
                    tool: .claude,
                    source: .claudeUsageProbe,
                    confidence: .observedLocalQuota,
                    classification: .limitReached(resetAt: date("2026-06-29T09:10:00Z")),
                    observedAt: now,
                    resetAt: date("2026-06-29T09:10:00Z"),
                    usedPercent: 22,
                    remainingPercent: 78,
                    windowLabel: "5h",
                    summary: "Current session: 22% used · resets Jun 29 at 6:10pm (Asia/Seoul)"
                ),
                QuotaWindowState(
                    tool: .codex,
                    source: .codexLocalAppServer,
                    confidence: .unknown,
                    classification: .quotaUnavailable,
                    observedAt: now,
                    summary: "Codex local quota source is unavailable from this CLI install."
                )
            ],
            now: now,
            calendar: calendar
        )
        XCTAssertNotEqual(observedLog.statusTitle, "Last run failed")
        XCTAssertEqual(observedLog.readinessSummaryText, "Window readiness enabled · Active-use gate on")
        XCTAssertEqual(observedLog.providerStatusText, "Reset observed")
        XCTAssertEqual(observedLog.fiveHourQuotaText, "Claude 78% left / Codex Unknown")
        XCTAssertEqual(observedLog.resetTimeText, "Claude 09:10 / Codex Unknown")
        XCTAssertEqual(observedLog.lastRunText, "Claude quota observed")
        let claudeCard = try XCTUnwrap(observedLog.providerStates.first { $0.tool == .claude })
        let codexCard = try XCTUnwrap(observedLog.providerStates.first { $0.tool == .codex })
        XCTAssertEqual(claudeCard.quotaText, "5h 22% used · 78% left")
        XCTAssertEqual(claudeCard.usedPercent, 22)
        XCTAssertEqual(claudeCard.remainingPercent, 78)
        XCTAssertEqual(claudeCard.nextResetText, "06/29 09:10")
        XCTAssertEqual(claudeCard.resetCountdownText, "9h 10m")
        XCTAssertEqual(claudeCard.confidenceText, "Observed local quota")
        XCTAssertEqual(claudeCard.sourceText, "Claude usage probe")
        XCTAssertFalse(claudeCard.showsDiagnosticDetail)
        XCTAssertTrue(claudeCard.detailText.localizedCaseInsensitiveContains("22% used"))
        XCTAssertEqual(codexCard.quotaText, "5h quota unavailable")
        XCTAssertNil(codexCard.usedPercent)
        XCTAssertNil(codexCard.remainingPercent)
        XCTAssertEqual(codexCard.nextResetText, "Unknown")
        XCTAssertEqual(codexCard.resetCountdownText, "Unknown")
        XCTAssertEqual(codexCard.confidenceText, "Unknown")
        XCTAssertEqual(codexCard.sourceText, "Codex local app-server")
        XCTAssertEqual(codexCard.diagnosticText, "Unknown · Codex local app-server")
        XCTAssertTrue(codexCard.showsDiagnosticDetail)
        XCTAssertTrue(codexCard.detailText.localizedCaseInsensitiveContains("unavailable"))
        XCTAssertNotEqual(claudeCard.quotaText, codexCard.quotaText)
        XCTAssertNotEqual(claudeCard.nextResetText, codexCard.nextResetText)

        let idle = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [RunLogEntry(
                eventId: "reset-window-claude-2026-06-28T23:59:00Z",
                scheduledAt: now,
                startedAt: now,
                endedAt: now,
                tool: .claude,
                commandPath: "/usr/local/bin/claude",
                status: .skippedMissedWindow,
                exitCode: nil,
                durationMs: 0,
                timedOut: false,
                stdoutSummary: "",
                stderrSummary: "",
                prompt: "hi",
                decisionSource: .activityGate,
                quotaConfidence: .exactReset,
                skipReason: "idle"
            )],
            resolvedCommands: commands,
            quotaStates: [quotaWindow(tool: .claude, confidence: .exactReset, resetAt: date("2026-06-28T23:59:00Z"))],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(idle.logRows.first?.summaryText, "skip idle, source activityGate, confidence exactReset")
        XCTAssertEqual(idle.providerStates.first?.statusText, "Reset candidate due")

        let unknown = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [],
            resolvedCommands: commands,
            quotaStates: [QuotaWindowState(
                tool: .claude,
                source: .none,
                confidence: .unknown,
                classification: .unknownFailure,
                observedAt: now,
                summary: longSummary()
            )],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(unknown.statusTitle, "Observation needed")
        XCTAssertEqual(unknown.providerStatusText, "Quota unknown")
        XCTAssertEqual(unknown.nextResetText, "Claude Unknown / Codex Unknown")
        XCTAssertLessThanOrEqual(unknown.providerStates.first?.detailText.count ?? 999, 140)

        let unavailable = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: [
                log(
                    status: .skippedMissedWindow,
                    tool: .codex,
                    at: now,
                    errorSummary: "Codex quota failed",
                    skipReason: "quota_observe_unavailable"
                )
            ],
            resolvedCommands: commands,
            quotaStates: [
                quotaWindow(tool: .claude, confidence: .exactReset, resetAt: now.addingTimeInterval(300)),
                QuotaWindowState(
                    tool: .codex,
                    source: .codexLocalAppServer,
                    confidence: .unknown,
                    classification: .quotaUnavailable,
                    observedAt: now,
                    summary: "Codex local quota source is unavailable from this CLI install."
                )
            ],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(unavailable.statusTitle, "Ready")
        XCTAssertEqual(unavailable.providerStatusText, "Reset observed")
        XCTAssertEqual(unavailable.lastRunText, "Codex quota unavailable")
        XCTAssertEqual(unavailable.providerStates.first { $0.tool == .codex }?.statusText, "Quota unavailable")
        XCTAssertEqual(unavailable.providerStates.first { $0.tool == .codex }?.resetCountdownText, "Unknown")
        XCTAssertEqual(unavailable.providerStates.first { $0.tool == .codex }?.showsDiagnosticDetail, true)
        XCTAssertTrue(unavailable.providerStates.first { $0.tool == .codex }?.detailText.localizedCaseInsensitiveContains("unavailable") == true)

        let observed = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [],
            resolvedCommands: commands,
            quotaStates: [quotaWindow(tool: .codex, confidence: .observedLocalQuota, resetAt: date("2026-06-29T00:40:00Z"))],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(observed.providerStates.first { $0.tool == .codex }?.statusText, "Reset observed")
        XCTAssertEqual(observed.providerStates.first { $0.tool == .codex }?.resetCountdownText, "40m")
        XCTAssertEqual(observed.providerStates.first { $0.tool == .codex }?.confidenceText, "Observed local quota")
        XCTAssertEqual(observed.providerStates.first { $0.tool == .codex }?.showsDiagnosticDetail, false)

        let legacyData = legacySettingsFixture.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(AppSettings.self, from: legacyData)
        let migratedState = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: migrated,
            logs: [],
            resolvedCommands: commands,
            quotaStates: [quotaWindow(tool: .claude, confidence: .estimatedFiveHour, resetAt: date("2026-06-29T00:00:00Z"))],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertFalse(migratedState.panes.map(\.rawValue).contains("schedule"))
        XCTAssertEqual(migratedState.providerStates.first?.confidenceText, "Estimated")
    }

    private func command(tool: ToolKind, status: CLIResolutionStatus, path: String?) -> ResolvedToolCommand {
        ResolvedToolCommand(
            tool: tool,
            executableURL: path.map { URL(fileURLWithPath: $0) },
            status: status,
            childPATH: "/usr/local/bin:/usr/bin:/bin",
            searchedDirectories: []
        )
    }

    private func log(
        status: RunStatus,
        tool: ToolKind,
        at date: Date,
        errorSummary: String? = nil,
        skipReason: String? = nil,
        stdoutSummary: String? = nil
    ) -> RunLogEntry {
        RunLogEntry(
            eventId: "test-event",
            scheduledAt: date,
            startedAt: date,
            endedAt: date.addingTimeInterval(2),
            tool: tool,
            commandPath: "/usr/local/bin/\(tool.rawValue)",
            status: status,
            exitCode: status == .sent ? 0 : 2,
            durationMs: 2_000,
            timedOut: status == .timedOut,
            stdoutSummary: stdoutSummary ?? (status == .sent ? "ok" : ""),
            stderrSummary: "",
            prompt: "hi",
            errorSummary: errorSummary,
            skipReason: skipReason
        )
    }

    private func longSummary() -> String {
        Array(repeating: "readiness prompt failed because output was intentionally long", count: 10)
            .joined(separator: " ")
    }

    private func quotaWindow(
        tool: ToolKind,
        confidence: QuotaWindowConfidence,
        resetAt: Date
    ) -> QuotaWindowState {
        QuotaWindowState(
            tool: tool,
            source: confidence == .observedLocalQuota ? .codexLocalAppServer : .cliMessageParser,
            confidence: confidence,
            classification: .limitReached(resetAt: resetAt),
            observedAt: resetAt.addingTimeInterval(-300),
            resetAt: resetAt,
            usedPercent: confidence == .estimatedFiveHour ? nil : 100,
            remainingPercent: confidence == .estimatedFiveHour ? nil : 0,
            windowLabel: "5h",
            summary: "limit reached; reset candidate \(ISO8601DateFormatter().string(from: resetAt))"
        )
    }

    private var legacySettingsFixture: String {
        """
        {
          "schemaVersion": 1,
          "firstRunCompleted": true,
          "prompt": "hi",
          "tools": {
            "claude": { "enabled": true, "manualPath": null },
            "codex": { "enabled": true, "manualPath": null }
          },
          "schedule": {
            "weekdays": [2,3,4,5,6],
            "times": [{ "hour": 6, "minute": 0 }],
            "paused": false,
            "missedRunGraceMinutes": 30
          },
          "background": { "launchAtLoginEnabled": true },
          "wake": {
            "enabled": true,
            "leadMinutes": 10,
            "helperInstalled": true,
            "lastRequestedWake": null
          }
        }
        """
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
