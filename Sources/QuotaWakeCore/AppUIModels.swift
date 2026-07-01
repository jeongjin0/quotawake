import Foundation

// SIZE_OK(MVP): popover/settings/log row derivation is centralized to keep UI copy
// and state mapping consistent. Follow-up split: PopoverUIState.swift,
// SettingsUIState.swift, FirstRunUIState.swift, and LogRowState.swift.

public enum UIStatusTone: String, Equatable, Sendable {
    case neutral
    case success
    case warning
    case error
    case info
}

public struct ToolUIState: Equatable, Sendable {
    public let tool: ToolKind
    public let displayName: String
    public let enabled: Bool
    public let status: CLIResolutionStatus
    public let statusText: String
    public let pathText: String
    public let detailText: String
    public let canTest: Bool
}

public struct LogRowUIState: Equatable, Sendable {
    public let timeText: String
    public let toolText: String
    public let statusText: String
    public let tone: UIStatusTone
    public let durationText: String
    public let exitCodeText: String
    public let summaryText: String
}

public struct ProviderReadinessUIState: Equatable, Sendable {
    public let tool: ToolKind
    public let displayName: String
    public let statusText: String
    public let statusTone: UIStatusTone
    public let quotaText: String
    public let usedPercent: Double?
    public let remainingPercent: Double?
    public let weeklyUsedPercent: Double?
    public let weeklyRemainingPercent: Double?
    public let weeklyValueText: String
    public let weeklyResetCountdownText: String
    public let hasWeeklyData: Bool
    public let lastReadinessText: String
    public let nextResetText: String
    public let resetCountdownText: String
    public let confidenceText: String
    public let sourceText: String
    public let detailText: String
    public let diagnosticText: String
    public let showsDiagnosticDetail: Bool
}

public struct PopoverUIState: Equatable, Sendable {
    public let statusTitle: String
    public let statusDetail: String
    public let statusTone: UIStatusTone
    public let readinessSummaryText: String
    public let readinessText: String
    public let providerStatusText: String
    public let fiveHourQuotaText: String
    public let resetTimeText: String
    public let nextResetText: String
    public let confidenceText: String
    public let enabledToolsText: String
    public let activityText: String
    public let lastRunText: String
    public let runNowTitle: String
    public let canRunNow: Bool
    public let toolStates: [ToolUIState]
    public let providerStates: [ProviderReadinessUIState]
    public let recentActivity: [LogRowUIState]
}

public enum SettingsPaneID: String, CaseIterable, Equatable, Sendable {
    case general
    case tools
    case readiness
    case prompt
    case logs

    public var title: String {
        switch self {
        case .general:
            return "General"
        case .tools:
            return "Tools"
        case .readiness:
            return "Window Readiness"
        case .prompt:
            return "Prompt"
        case .logs:
            return "Logs"
        }
    }
}

public struct SettingsUIState: Equatable, Sendable {
    public let panes: [SettingsPaneID]
    public let appVersionText: String
    public let launchAtLoginText: String
    public let backgroundText: String
    public let readinessSummary: String
    public let nextResetText: String
    public let confidenceText: String
    public let promptPreview: String
    public let toolStates: [ToolUIState]
    public let providerStates: [ProviderReadinessUIState]
    public let logRows: [LogRowUIState]
}

public enum QuotaWakeUIStateBuilder {
    public static func makePopoverState(
        settings: AppSettings,
        logs: [RunLogEntry],
        resolvedCommands: [ResolvedToolCommand],
        quotaStates: [QuotaWindowState] = [],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        isRunning: Bool = false
    ) -> PopoverUIState {
        let toolStates = ToolKind.allCases.map { toolState(for: $0, settings: settings, resolvedCommands: resolvedCommands) }
        let enabledTools = toolStates.filter(\.enabled)
        let runnableTools = enabledTools.filter { $0.status == .found }
        let latestLog = logs.sorted { $0.endedAt < $1.endedAt }.last
        let allProviderStates = providerStates(
            settings: settings,
            quotaStates: quotaStates,
            latestLogs: latestLogsByTool(logs),
            now: now,
            calendar: calendar
        )
        let runnableToolSet = Set(runnableTools.map(\.tool))
        let providerStates = allProviderStates.filter { runnableToolSet.contains($0.tool) }
        let status = statusSummary(
            settings: settings,
            toolStates: toolStates,
            providerStates: providerStates,
            latestLog: latestLog,
            isRunning: isRunning
        )

        let resetSummary = providerResetSummaryText(providerStates)
        return PopoverUIState(
            statusTitle: status.title,
            statusDetail: status.detail,
            statusTone: status.tone,
            readinessSummaryText: popoverReadinessSummaryText(settings: settings),
            readinessText: readinessText(settings: settings),
            providerStatusText: providerStatusText(providerStates),
            fiveHourQuotaText: fiveHourQuotaText(settings: settings, quotaStates: quotaStates),
            resetTimeText: resetSummary,
            nextResetText: resetSummary,
            confidenceText: confidenceSummary(providerStates),
            enabledToolsText: enabledToolsText(settings: settings),
            activityText: activityText(settings.readiness),
            lastRunText: lastRunText(latestLog),
            runNowTitle: isRunning ? "Sending..." : "Send",
            canRunNow: !isRunning && !runnableTools.isEmpty,
            toolStates: toolStates,
            providerStates: providerStates,
            recentActivity: logs
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(3)
                .map { logRow($0, calendar: calendar) }
        )
    }

    public static func makeSettingsState(
        settings: AppSettings,
        logs: [RunLogEntry],
        resolvedCommands: [ResolvedToolCommand],
        quotaStates: [QuotaWindowState] = [],
        appVersion: String = "0.0.0",
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> SettingsUIState {
        let providerStates = providerStates(
            settings: settings,
            quotaStates: quotaStates,
            latestLogs: latestLogsByTool(logs),
            now: now,
            calendar: calendar
        )
        return SettingsUIState(
            panes: SettingsPaneID.allCases,
            appVersionText: "Version \(appVersion)",
            launchAtLoginText: settings.background.launchAtLoginEnabled ? "On" : "Off",
            backgroundText: backgroundText(settings: settings),
            readinessSummary: readinessSummary(settings.readiness),
            nextResetText: nextResetText(providerStates),
            confidenceText: confidenceSummary(providerStates),
            promptPreview: truncateMiddle(settings.prompt, maxCharacters: 96),
            toolStates: ToolKind.allCases.map { toolState(for: $0, settings: settings, resolvedCommands: resolvedCommands) },
            providerStates: providerStates,
            logRows: logs
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(100)
                .map { logRow($0, calendar: calendar) }
        )
    }

    public static func visibleStrings(
        popover: PopoverUIState,
        settings: SettingsUIState
    ) -> [String] {
        var strings = [
            popover.statusTitle,
            popover.statusDetail,
            popover.readinessSummaryText,
            popover.readinessText,
            popover.providerStatusText,
            popover.fiveHourQuotaText,
            popover.resetTimeText,
            popover.nextResetText,
            popover.confidenceText,
            popover.enabledToolsText,
            popover.activityText,
            popover.lastRunText,
            popover.runNowTitle,
            settings.appVersionText,
            settings.launchAtLoginText,
            settings.backgroundText,
            settings.readinessSummary,
            settings.nextResetText,
            settings.confidenceText,
            settings.promptPreview
        ]
        strings += popover.toolStates.flatMap { [$0.displayName, $0.statusText, $0.pathText, $0.detailText] }
        strings += popover.providerStates.flatMap {
            [
                $0.displayName,
                $0.statusText,
                $0.quotaText,
                $0.lastReadinessText,
                $0.nextResetText,
                $0.resetCountdownText,
                $0.weeklyValueText,
                $0.weeklyResetCountdownText,
                $0.confidenceText,
                $0.sourceText,
                $0.detailText,
                $0.diagnosticText
            ]
        }
        strings += settings.toolStates.flatMap { [$0.displayName, $0.statusText, $0.pathText, $0.detailText] }
        strings += settings.providerStates.flatMap {
            [
                $0.displayName,
                $0.statusText,
                $0.quotaText,
                $0.lastReadinessText,
                $0.nextResetText,
                $0.resetCountdownText,
                $0.weeklyValueText,
                $0.weeklyResetCountdownText,
                $0.confidenceText,
                $0.sourceText,
                $0.detailText,
                $0.diagnosticText
            ]
        }
        strings += settings.logRows.flatMap { [$0.timeText, $0.toolText, $0.statusText, $0.durationText, $0.exitCodeText, $0.summaryText] }
        return strings
    }

    public static func truncateMiddle(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 6, text.count > maxCharacters else {
            return text
        }

        let visibleCount = maxCharacters - 3
        let prefixCount = visibleCount / 2
        let suffixCount = visibleCount - prefixCount
        return "\(text.prefix(prefixCount))...\(text.suffix(suffixCount))"
    }

    private static func statusSummary(
        settings: AppSettings,
        toolStates: [ToolUIState],
        providerStates: [ProviderReadinessUIState],
        latestLog: RunLogEntry?,
        isRunning: Bool
    ) -> (title: String, detail: String, tone: UIStatusTone) {
        if isRunning {
            return ("Running", "Sending readiness prompt through enabled tools.", .info)
        }

        guard settings.firstRunCompleted else {
            return ("Setup needed", "Choose tools and window readiness options before background runs.", .warning)
        }

        let enabledTools = toolStates.filter(\.enabled)
        guard !enabledTools.isEmpty else {
            return ("Setup needed", "Enable Claude or Codex before background runs.", .warning)
        }

        let unresolvedTools = enabledTools.filter { $0.status != .found }
        if unresolvedTools.count == enabledTools.count {
            return ("Setup needed", "Choose CLI paths for enabled tools.", .warning)
        }
        if !unresolvedTools.isEmpty {
            return ("Setup needed", "Review CLI paths for enabled tools.", .warning)
        }

        if !settings.background.launchAtLoginEnabled {
            return ("Paused", "Background readiness is off.", .neutral)
        }

        if settings.readiness.paused {
            return ("Paused", "Background readiness is paused.", .neutral)
        }

        if let latestLog, latestLog.status != .sent, !isQuotaObservationLog(latestLog) {
            return ("Last run failed", latestLog.errorSummary ?? statusText(latestLog.status), .error)
        }

        if providerStates.contains(where: { $0.statusText == "Reset candidate due" }) {
            return ("Ready", "A quota window candidate is due and active use is allowed.", .success)
        }

        if providerStates.contains(where: { $0.statusText == "Quota unknown" }) {
            return ("Observation needed", "Observe the last result before background readiness sends.", .warning)
        }

        return ("Ready", "Window readiness is ready.", .success)
    }

    private static func readinessText(settings: AppSettings) -> String {
        guard settings.firstRunCompleted else {
            return "Waiting for quota window signal"
        }
        if !settings.background.launchAtLoginEnabled {
            return "Background readiness off"
        }
        if settings.readiness.paused {
            return "Window readiness paused"
        }
        return "Window readiness enabled"
    }

    private static func popoverReadinessSummaryText(settings: AppSettings) -> String {
        "\(readinessText(settings: settings)) · \(activityText(settings.readiness))"
    }

    private static func enabledToolsText(settings: AppSettings) -> String {
        let enabled = ToolKind.allCases.filter { settings.tools[$0].enabled }
        switch enabled {
        case [.claude, .codex]:
            return "Claude and Codex enabled"
        case [.claude]:
            return "Claude enabled"
        case [.codex]:
            return "Codex enabled"
        default:
            return "No tools enabled"
        }
    }

    private static func activityText(_ readiness: WindowReadinessSettings) -> String {
        readiness.activeOnly ? "Active-use gate on" : "Active-use gate off"
    }

    private static func fiveHourQuotaText(settings: AppSettings, quotaStates: [QuotaWindowState]) -> String {
        let statesByTool = Dictionary(uniqueKeysWithValues: quotaStates.map { ($0.tool, $0) })
        let enabledTools = ToolKind.allCases.filter { settings.tools[$0].enabled }
        let values = enabledTools.map { tool -> (tool: ToolKind, percentText: String) in
            guard let state = statesByTool[tool],
                  let percentText = quotaPercentText(state) else {
                return (tool, "Unknown")
            }
            return (tool, percentText)
        }

        switch values.count {
        case 0:
            return "Unknown"
        case 1:
            return values[0].percentText
        default:
            let summary = values
                .map { "\(displayName($0.tool)) \(shortPercentText($0.percentText))" }
                .joined(separator: " / ")
            return truncateMiddle(summary, maxCharacters: 42)
        }
    }

    private static func providerQuotaText(_ state: QuotaWindowState) -> String {
        let window = state.windowLabel ?? "5h"
        var parts: [String] = []
        if let usedPercent = state.usedPercent {
            parts.append("\(percentText(usedPercent)) used")
        }
        if let remainingPercent = state.remainingPercent {
            parts.append("\(percentText(remainingPercent)) left")
        }
        if parts.isEmpty {
            switch state.classification {
            case .quotaUnavailable:
                return "\(window) quota unavailable"
            case .unknownFailure, .usageLimitNoReset, .sent:
                return "\(window) quota unknown"
            case .authRequired, .apiBillingEnvPresent:
                return "\(window) quota blocked"
            case .limitReached:
                return "\(window) quota observed"
            }
        }
        return "\(window) \(parts.joined(separator: " · "))"
    }

    private static func providerQuotaPercents(_ state: QuotaWindowState) -> (used: Double?, remaining: Double?) {
        var used = state.usedPercent.map(clampedPercent)
        var remaining = state.remainingPercent.map(clampedPercent)
        if used == nil, let remaining {
            used = clampedPercent(100 - remaining)
        }
        if remaining == nil, let used {
            remaining = clampedPercent(100 - used)
        }
        return (used, remaining)
    }

    private static func weeklyValues(
        _ state: QuotaWindowState,
        now: Date
    ) -> (used: Double?, remaining: Double?, valueText: String, countdown: String, hasData: Bool) {
        var used = state.weeklyUsedPercent.map(clampedPercent)
        var remaining = state.weeklyRemainingPercent.map(clampedPercent)
        if used == nil, let remaining { used = clampedPercent(100 - remaining) }
        if remaining == nil, let used { remaining = clampedPercent(100 - used) }
        let hasData = used != nil || remaining != nil || state.weeklyResetAt != nil
        let valueText: String
        if let remaining {
            valueText = "\(percentText(remaining)) left"
        } else if let used {
            valueText = "\(percentText(used)) used"
        } else if hasData {
            valueText = "Observed"
        } else {
            valueText = "Unknown"
        }
        let countdown = state.weeklyResetAt.map { resetCountdownText(until: $0, now: now) } ?? "Unknown"
        return (used, remaining, valueText, countdown, hasData)
    }

    private static func quotaPercentText(_ state: QuotaWindowState) -> String? {
        if let remainingPercent = state.remainingPercent {
            return "\(percentText(remainingPercent)) left"
        }
        if let usedPercent = state.usedPercent {
            return "\(percentText(usedPercent)) used"
        }
        return nil
    }

    private static func shortPercentText(_ value: String) -> String {
        guard value != "Unknown" else {
            return value
        }
        return value
            .replacingOccurrences(of: " used", with: "")
            .replacingOccurrences(of: " left", with: " left")
    }

    private static func percentText(_ value: Double) -> String {
        let clamped = clampedPercent(value)
        if clamped.rounded() == clamped {
            return "\(Int(clamped))%"
        }
        return String(format: "%.1f%%", clamped)
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func resetCountdownText(until resetAt: Date, now: Date) -> String {
        let seconds = Int(ceil(resetAt.timeIntervalSince(now)))
        guard seconds > 0 else {
            return "Due now"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    private static func providerShowsDiagnostic(_ tone: UIStatusTone) -> Bool {
        tone == .warning || tone == .error
    }

    private static func lastRunText(_ entry: RunLogEntry?) -> String {
        guard let entry else {
            return "No runs yet"
        }
        if let quotaObservationText = quotaObservationText(entry) {
            return "\(displayName(entry.tool)) \(quotaObservationText)"
        }
        return "\(displayName(entry.tool)) \(statusText(entry.status))"
    }

    private static func isQuotaObservationLog(_ entry: RunLogEntry) -> Bool {
        quotaObservationText(entry) != nil
    }

    private static func quotaObservationText(_ entry: RunLogEntry) -> String? {
        switch entry.skipReason {
        case "quota_observed":
            return "quota observed"
        case "quota_observe_unavailable":
            return "quota unavailable"
        case "quota_observe_failed":
            return "quota unknown"
        default:
            return nil
        }
    }

    private static func providerStates(
        settings: AppSettings,
        quotaStates: [QuotaWindowState],
        latestLogs: [ToolKind: RunLogEntry],
        now: Date,
        calendar: Calendar
    ) -> [ProviderReadinessUIState] {
        let statesByTool = Dictionary(uniqueKeysWithValues: quotaStates.map { ($0.tool, $0) })
        return ToolKind.allCases.map { tool in
            providerState(
                for: tool,
                enabled: settings.tools[tool].enabled,
                quotaState: statesByTool[tool],
                latestLog: latestLogs[tool],
                now: now,
                calendar: calendar
            )
        }
    }

    private static func providerState(
        for tool: ToolKind,
        enabled: Bool,
        quotaState: QuotaWindowState?,
        latestLog: RunLogEntry?,
        now: Date,
        calendar: Calendar
    ) -> ProviderReadinessUIState {
        guard enabled else {
            return ProviderReadinessUIState(
                tool: tool,
                displayName: displayName(tool),
                statusText: "Disabled",
                statusTone: .neutral,
                quotaText: "Not used",
                usedPercent: nil,
                remainingPercent: nil,
                weeklyUsedPercent: nil,
                weeklyRemainingPercent: nil,
                weeklyValueText: "Not used",
                weeklyResetCountdownText: "Not used",
                hasWeeklyData: false,
                lastReadinessText: lastRunText(latestLog),
                nextResetText: "Not used",
                resetCountdownText: "Not used",
                confidenceText: "Blocked",
                sourceText: "Tool settings",
                detailText: "This provider is excluded from session readiness.",
                diagnosticText: "Blocked · Tool settings",
                showsDiagnosticDetail: false
            )
        }

        guard let quotaState else {
            return ProviderReadinessUIState(
                tool: tool,
                displayName: displayName(tool),
                statusText: "Quota unknown",
                statusTone: .warning,
                quotaText: "5h quota unknown",
                usedPercent: nil,
                remainingPercent: nil,
                weeklyUsedPercent: nil,
                weeklyRemainingPercent: nil,
                weeklyValueText: "Unknown",
                weeklyResetCountdownText: "Unknown",
                hasWeeklyData: false,
                lastReadinessText: lastRunText(latestLog),
                nextResetText: "Unknown",
                resetCountdownText: "Unknown",
                confidenceText: confidenceText(.unknown),
                sourceText: sourceText(.none),
                detailText: "Observe from the last provider result before background sends.",
                diagnosticText: "Unknown · None",
                showsDiagnosticDetail: true
            )
        }

        let nextReset = quotaState.resetAt.map { dateTimeText($0, calendar: calendar) } ?? "Unknown"
        let resetCountdown = quotaState.resetAt.map { resetCountdownText(until: $0, now: now) } ?? "Unknown"
        let detail = truncateMiddle(quotaState.summary, maxCharacters: 140)
        let (status, tone) = providerStatus(quotaState, now: now)
        let (usedPercent, remainingPercent) = providerQuotaPercents(quotaState)
        let weekly = weeklyValues(quotaState, now: now)
        let confidence = confidenceText(quotaState.confidence)
        let source = sourceText(quotaState.source)
        return ProviderReadinessUIState(
            tool: tool,
            displayName: displayName(tool),
            statusText: status,
            statusTone: tone,
            quotaText: providerQuotaText(quotaState),
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            weeklyUsedPercent: weekly.used,
            weeklyRemainingPercent: weekly.remaining,
            weeklyValueText: weekly.valueText,
            weeklyResetCountdownText: weekly.countdown,
            hasWeeklyData: weekly.hasData,
            lastReadinessText: lastRunText(latestLog),
            nextResetText: nextReset,
            resetCountdownText: resetCountdown,
            confidenceText: confidence,
            sourceText: source,
            detailText: detail.isEmpty ? classificationText(quotaState.classification) : detail,
            diagnosticText: "\(confidence) · \(source)",
            showsDiagnosticDetail: providerShowsDiagnostic(tone)
        )
    }

    private static func providerStatus(_ state: QuotaWindowState, now: Date) -> (String, UIStatusTone) {
        switch state.classification {
        case .sent:
            return ("Provider available", .success)
        case .limitReached:
            if let resetAt = state.resetAt, resetAt <= now, state.confidence != .unknown {
                return ("Reset candidate due", .success)
            }
            if state.confidence == .unknown {
                return ("Quota unknown", .warning)
            }
            return ("Reset observed", .info)
        case .authRequired, .apiBillingEnvPresent:
            return ("Provider blocked", .error)
        case .quotaUnavailable:
            return ("Quota unavailable", .warning)
        case .usageLimitNoReset, .unknownFailure:
            return ("Quota unknown", .warning)
        }
    }

    private static func providerStatusText(_ states: [ProviderReadinessUIState]) -> String {
        if states.contains(where: { $0.statusText == "Reset candidate due" }) {
            return "Reset candidate due"
        }
        if states.contains(where: { $0.statusText == "Provider blocked" }) {
            return "Provider blocked"
        }
        if states.contains(where: { $0.statusText == "Quota unknown" }) {
            return "Quota unknown"
        }
        if states.contains(where: { $0.statusText == "Reset observed" }) {
            return "Reset observed"
        }
        if states.contains(where: { $0.statusText == "Quota unavailable" }) {
            return "Quota unavailable"
        }
        return "Provider available"
    }

    private static func nextResetText(_ states: [ProviderReadinessUIState]) -> String {
        states.first { $0.nextResetText != "Unknown" && $0.nextResetText != "Not used" }?.nextResetText ?? "Unknown"
    }

    private static func providerResetSummaryText(_ states: [ProviderReadinessUIState]) -> String {
        let enabled = states.filter { $0.statusText != "Disabled" }
        guard !enabled.isEmpty else {
            return "Blocked"
        }
        let values = enabled.map { state -> String in
            guard state.nextResetText != "Unknown", state.nextResetText != "Not used" else {
                return "\(state.displayName) Unknown"
            }
            return "\(state.displayName) \(compactResetText(state.nextResetText))"
        }
        return truncateMiddle(values.joined(separator: " / "), maxCharacters: 44)
    }

    private static func confidenceSummary(_ states: [ProviderReadinessUIState]) -> String {
        let enabled = states.filter { $0.statusText != "Disabled" }
        guard !enabled.isEmpty else {
            return "Blocked"
        }
        let values = Array(Set(enabled.map(\.confidenceText))).sorted()
        return truncateMiddle(values.joined(separator: " / "), maxCharacters: 42)
    }

    private static func latestLogsByTool(_ logs: [RunLogEntry]) -> [ToolKind: RunLogEntry] {
        Dictionary(grouping: logs, by: \.tool).compactMapValues { entries in
            entries.sorted { $0.endedAt < $1.endedAt }.last
        }
    }

    private static func toolState(
        for tool: ToolKind,
        settings: AppSettings,
        resolvedCommands: [ResolvedToolCommand]
    ) -> ToolUIState {
        let toolSettings = settings.tools[tool]
        let command = resolvedCommands.first { $0.tool == tool }
        let status = command?.status ?? .missing
        let path = command?.executableURL?.path ?? toolSettings.manualPath ?? ""
        let pathText = path.isEmpty ? "No path detected" : truncateMiddle(path, maxCharacters: 78)

        if !toolSettings.enabled {
            return ToolUIState(
                tool: tool,
                displayName: displayName(tool),
                enabled: false,
                status: status,
                statusText: "Disabled",
                pathText: pathText,
                detailText: "This tool is excluded from session readiness.",
                canTest: false
            )
        }

        return ToolUIState(
            tool: tool,
            displayName: displayName(tool),
            enabled: true,
            status: status,
            statusText: toolStatusText(status),
            pathText: pathText,
            detailText: toolDetailText(status),
            canTest: status == .found
        )
    }

    private static func toolStatusText(_ status: CLIResolutionStatus) -> String {
        switch status {
        case .found:
            return "Ready"
        case .manualPathInvalid:
            return "Manual path invalid"
        case .missing:
            return "Choose path"
        case .nodeRuntimeMissing:
            return "Node runtime missing"
        case .brokenExecutable:
            return "CLI check failed"
        }
    }

    private static func toolDetailText(_ status: CLIResolutionStatus) -> String {
        switch status {
        case .found:
            return "Ready to send readiness prompts."
        case .manualPathInvalid:
            return "Pick an executable CLI path."
        case .missing:
            return "Install the CLI or choose a path."
        case .nodeRuntimeMissing:
            return "Node is required for this CLI."
        case .brokenExecutable:
            return "Pick another CLI path or reinstall this CLI."
        }
    }

    private static func readinessSummary(_ readiness: WindowReadinessSettings) -> String {
        let activity = readiness.activeOnly ? "Active use" : "Activity gate off"
        let prefix = readiness.paused ? "Paused, \(activity.lowercased())" : activity
        return "\(prefix), idle after \(readiness.idleThresholdSeconds)s, cooldown \(readiness.minimumSendCooldownMinutes)m, \(resetModeText(readiness.resetEstimationMode))"
    }

    private static func backgroundText(settings: AppSettings) -> String {
        if settings.readiness.paused {
            return "Session readiness paused"
        }
        return settings.background.launchAtLoginEnabled ? "Session readiness on" : "Session readiness off"
    }

    private static func confidenceText(_ confidence: QuotaWindowConfidence) -> String {
        switch confidence {
        case .observedLocalQuota:
            return "Observed local quota"
        case .exactReset:
            return "Exact reset"
        case .estimatedFiveHour:
            return "Estimated"
        case .unknown:
            return "Unknown"
        case .blocked:
            return "Blocked"
        }
    }

    private static func sourceText(_ source: QuotaWindowSource) -> String {
        switch source {
        case .codexLocalAppServer:
            return "Codex local app-server"
        case .claudeUsageProbe:
            return "Claude usage probe"
        case .cliMessageParser:
            return "CLI result parser"
        case .estimatedLastSuccess:
            return "Last successful send"
        case .none:
            return "None"
        }
    }

    private static func resetModeText(_ mode: ResetEstimationMode) -> String {
        switch mode {
        case .localSignalsOnly:
            return "local signals only"
        case .allowFiveHourEstimate:
            return "estimated candidate allowed"
        }
    }

    private static func classificationText(_ classification: QuotaSourceClassification) -> String {
        switch classification {
        case .sent:
            return "Provider accepted the last readiness send."
        case .limitReached:
            return "Provider reported a limit with a reset candidate."
        case .authRequired:
            return "Provider requires authentication."
        case .apiBillingEnvPresent:
            return "API billing environment is present."
        case .usageLimitNoReset:
            return "Usage limit was observed without a reset candidate."
        case .quotaUnavailable:
            return "Local quota source is unavailable."
        case .unknownFailure:
            return "Provider state could not be classified."
        }
    }

    private static func logRow(_ entry: RunLogEntry, calendar: Calendar) -> LogRowUIState {
        let baseSummary = entry.errorSummary?.isEmpty == false
            ? entry.errorSummary!
            : firstNonEmpty(entry.stdoutSummary, entry.stderrSummary, fallback: statusText(entry.status))
        let summary = logMetadataSummary(entry, fallback: baseSummary)
        return LogRowUIState(
            timeText: timeText(entry.startedAt, calendar: calendar),
            toolText: displayName(entry.tool),
            statusText: statusText(entry.status),
            tone: tone(entry.status),
            durationText: "\(entry.durationMs) ms",
            exitCodeText: entry.exitCode.map(String.init) ?? "-",
            summaryText: truncateMiddle(summary, maxCharacters: 120)
        )
    }

    private static func logMetadataSummary(_ entry: RunLogEntry, fallback: String) -> String {
        var fields: [String] = []
        if let skipReason = entry.skipReason {
            fields.append("skip \(skipReason)")
        }
        if let decisionSource = entry.decisionSource {
            fields.append("source \(decisionSource.rawValue)")
        }
        if let quotaConfidence = entry.quotaConfidence {
            fields.append("confidence \(quotaConfidence.rawValue)")
        }
        guard !fields.isEmpty else {
            return fallback
        }
        return fields.joined(separator: ", ")
    }

    private static func firstNonEmpty(_ first: String, _ second: String, fallback: String) -> String {
        if !first.isEmpty {
            return first
        }
        if !second.isEmpty {
            return second
        }
        return fallback
    }

    private static func statusText(_ status: RunStatus) -> String {
        switch status {
        case .sent:
            return "sent"
        case .failed:
            return "failed"
        case .timedOut:
            return "timed out"
        case .skippedOverlap:
            return "skipped overlap"
        case .skippedMissedWindow:
            return "skipped missed window"
        }
    }

    private static func tone(_ status: RunStatus) -> UIStatusTone {
        switch status {
        case .sent:
            return .success
        case .failed, .timedOut:
            return .error
        case .skippedOverlap, .skippedMissedWindow:
            return .warning
        }
    }

    private static func displayName(_ tool: ToolKind) -> String {
        switch tool {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

    private static func dateTimeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(
            format: "%02d/%02d %02d:%02d",
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private static func compactResetText(_ text: String) -> String {
        let parts = text.split(separator: " ")
        guard let time = parts.last, time.contains(":") else {
            return text
        }
        return String(time)
    }

    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
