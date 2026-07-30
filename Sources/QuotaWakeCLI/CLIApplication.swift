import Foundation
import QuotaWakeCore

public enum QuotaWakeCLIError: Error, CustomStringConvertible, Equatable {
    case invalidProvider(String)
    case noProviderDetected
    case providerUnavailable(ToolKind, CLIResolutionStatus)
    case backgroundReadinessDisabled
    case daemonAlreadyRunning(Int32?)
    case unsupportedServicePlatform
    case serviceCommandFailed(String)
    case invalidConfiguration(String)

    public var description: String {
        switch self {
        case let .invalidProvider(value):
            return "unknown provider '\(value)'; expected claude or codex"
        case .noProviderDetected:
            return "no runnable Claude or Codex CLI was detected"
        case let .providerUnavailable(tool, status):
            return "\(tool.rawValue) is unavailable (\(status.rawValue)); run 'quotawake doctor'"
        case .backgroundReadinessDisabled:
            return "background readiness is disabled; run 'quotawake service install' or enable it in config"
        case let .daemonAlreadyRunning(pid):
            if let pid {
                return "a QuotaWake daemon is already running with pid \(pid)"
            }
            return "a QuotaWake daemon already appears to be running"
        case .unsupportedServicePlatform:
            return "background service installation is not supported on this platform yet"
        case let .serviceCommandFailed(message):
            return message
        case let .invalidConfiguration(message):
            return message
        }
    }
}

public struct ProviderSnapshot: Codable, Equatable {
    public let provider: String
    public let enabled: Bool
    public let cliStatus: String
    public let executablePath: String?
    public let confidence: String?
    public let classification: String?
    public let observedAt: Date?
    public let resetAt: Date?
    public let usedPercent: Double?
    public let weeklyUsedPercent: Double?
    public let summary: String?
}

public struct QuotaWakeStatusSnapshot: Codable, Equatable {
    public let version: String
    public let setupComplete: Bool
    public let backgroundReadinessEnabled: Bool
    public let paused: Bool
    public let activityMode: String
    public let configPath: String
    public let providers: [ProviderSnapshot]
}

public struct DoctorSnapshot: Codable, Equatable {
    public let ready: Bool
    public let configDirectory: String
    public let providers: [ProviderSnapshot]
    public let problems: [String]
}

public struct SendSnapshot: Codable, Equatable {
    public let provider: String
    public let status: String
    public let exitCode: Int?
    public let durationMs: Int
    public let summary: String
}

public struct QuotaWakeCLIContext {
    public let paths: QuotaWakePaths
    public let settingsStore: SettingsStore
    public let logStore: RunLogStore
    public let quotaStateStore: QuotaWindowStateStore
    public let detector: CLIPathDetector
    public let now: () -> Date

    public init(
        paths: QuotaWakePaths = QuotaWakePaths(),
        detector: CLIPathDetector = CLIPathDetector(),
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.settingsStore = SettingsStore(paths: paths)
        self.logStore = RunLogStore(paths: paths)
        self.quotaStateStore = QuotaWindowStateStore(paths: paths)
        self.detector = detector
        self.now = now
    }

    public func parseProvider(_ raw: String?) throws -> ToolKind? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        guard let tool = ToolKind(rawValue: raw.lowercased()) else {
            throw QuotaWakeCLIError.invalidProvider(raw)
        }
        return tool
    }

    public func setup(
        providers: Set<ToolKind>? = nil,
        claudePath: String? = nil,
        codexPath: String? = nil,
        enableBackground: Bool = false
    ) throws -> QuotaWakeStatusSnapshot {
        var settings = try settingsStore.load()
        if let claudePath {
            settings.tools.claude.manualPath = claudePath
        }
        if let codexPath {
            settings.tools.codex.manualPath = codexPath
        }

        let requested = providers ?? Set(ToolKind.allCases)
        var detectedCount = 0
        for tool in ToolKind.allCases {
            guard requested.contains(tool) else {
                settings.tools[tool].enabled = false
                continue
            }
            let result = detector.resolve(tool: tool, manualPath: settings.tools[tool].manualPath)
            if result.status == .found {
                settings.tools[tool].enabled = true
                detectedCount += 1
            } else if providers != nil {
                throw QuotaWakeCLIError.providerUnavailable(tool, result.status)
            } else {
                settings.tools[tool].enabled = false
            }
        }
        guard detectedCount > 0 else {
            throw QuotaWakeCLIError.noProviderDetected
        }

        settings.firstRunCompleted = true
        if enableBackground {
            settings.background.launchAtLoginEnabled = true
        }
        try settingsStore.save(settings)
        return try status()
    }

    public func status() throws -> QuotaWakeStatusSnapshot {
        let settings = try settingsStore.load()
        let providers = ToolKind.allCases.map { tool in
            providerSnapshot(tool: tool, settings: settings)
        }
        return QuotaWakeStatusSnapshot(
            version: QuotaWakeCore.currentVersion,
            setupComplete: settings.firstRunCompleted,
            backgroundReadinessEnabled: settings.background.launchAtLoginEnabled,
            paused: settings.readiness.paused,
            activityMode: settings.readiness.activeOnly ? "active-only" : "always",
            configPath: paths.settingsFile.path,
            providers: providers
        )
    }

    public func doctor() throws -> DoctorSnapshot {
        let settings = try settingsStore.load()
        let providers = ToolKind.allCases.map { tool in
            providerSnapshot(tool: tool, settings: settings)
        }
        var problems: [String] = []
        if !settings.firstRunCompleted {
            problems.append("setup is incomplete; run 'quotawake setup'")
        }
        for provider in providers where provider.enabled && provider.cliStatus != CLIResolutionStatus.found.rawValue {
            problems.append("\(provider.provider): \(provider.cliStatus)")
        }
        #if os(Windows)
        if settings.readiness.activeOnly {
            problems.append("automatic active-only sends are fail-closed on Windows in this preview")
        }
        #endif
        return DoctorSnapshot(
            ready: problems.isEmpty,
            configDirectory: paths.applicationSupportDirectory.path,
            providers: providers,
            problems: problems
        )
    }

    public func observe(provider: ToolKind? = nil) throws -> [ProviderSnapshot] {
        let settings = try settingsStore.load()
        let tools = selectedTools(provider, settings: settings)
        try validateSelectedTools(tools, settings: settings)
        guard try makePoller().observeNow(provider: provider) else {
            throw QuotaWakeCLIError.invalidConfiguration("another QuotaWake operation is already running")
        }

        return tools.map { providerSnapshot(tool: $0, settings: settings) }
    }

    public func send(provider: ToolKind? = nil) throws -> [SendSnapshot] {
        let settings = try settingsStore.load()
        let tools = selectedTools(provider, settings: settings)
        try validateSelectedTools(tools, settings: settings)
        return try makePoller().sendNow(provider: provider).map { entry in
            SendSnapshot(
                provider: entry.tool.rawValue,
                status: entry.status.rawValue,
                exitCode: entry.exitCode,
                durationMs: entry.durationMs,
                summary: entry.errorSummary ?? entry.stdoutSummary
            )
        }
    }

    public func logs(limit: Int) throws -> [RunLogEntry] {
        Array(try logStore.readAll().sorted { $0.startedAt > $1.startedAt }.prefix(max(0, limit)))
    }

    public func makePoller() -> QuotaReadinessPoller {
        let runner = ToolRunner(logStore: logStore)
        return QuotaReadinessPoller(
            paths: paths,
            settingsStore: settingsStore,
            logStore: logStore,
            quotaStateStore: quotaStateStore,
            commandsProvider: {
                let settings = (try? settingsStore.load()) ?? .default
                return ToolKind.allCases.map { tool in
                    detector.resolve(tool: tool, manualPath: settings.tools[tool].manualPath)
                }
            },
            runner: runner
        )
    }

    public func updateConfiguration(key: String, value: String) throws -> AppSettings {
        var settings = try settingsStore.load()
        switch key {
        case "prompt":
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw QuotaWakeCLIError.invalidConfiguration("prompt cannot be empty")
            }
            settings.prompt = value
        case "readiness.paused":
            settings.readiness.paused = try parseBoolean(value)
        case "readiness.active-only":
            settings.readiness.activeOnly = try parseBoolean(value)
        case "readiness.idle-seconds":
            guard let seconds = Int(value), seconds >= 0 else {
                throw QuotaWakeCLIError.invalidConfiguration("idle seconds must be a non-negative integer")
            }
            settings.readiness.idleThresholdSeconds = seconds
        case "readiness.cooldown-minutes":
            guard let minutes = Int(value), minutes >= 0 else {
                throw QuotaWakeCLIError.invalidConfiguration("cooldown minutes must be a non-negative integer")
            }
            settings.readiness.minimumSendCooldownMinutes = minutes
        case "background.enabled":
            settings.background.launchAtLoginEnabled = try parseBoolean(value)
        case "provider.claude.enabled":
            settings.tools.claude.enabled = try parseBoolean(value)
        case "provider.codex.enabled":
            settings.tools.codex.enabled = try parseBoolean(value)
        case "provider.claude.path":
            settings.tools.claude.manualPath = value.isEmpty ? nil : value
        case "provider.codex.path":
            settings.tools.codex.manualPath = value.isEmpty ? nil : value
        default:
            throw QuotaWakeCLIError.invalidConfiguration("unknown config key '\(key)'")
        }
        try settingsStore.save(settings)
        return settings
    }

    private func selectedTools(_ provider: ToolKind?, settings: AppSettings) -> [ToolKind] {
        if let provider {
            return [provider]
        }
        return ToolKind.allCases.filter { settings.tools[$0].enabled }
    }

    private func validateSelectedTools(_ tools: [ToolKind], settings: AppSettings) throws {
        guard !tools.isEmpty else {
            throw QuotaWakeCLIError.noProviderDetected
        }
        for tool in tools {
            guard settings.tools[tool].enabled else {
                throw QuotaWakeCLIError.invalidConfiguration("\(tool.rawValue) is disabled in QuotaWake configuration")
            }
            let command = resolve(tool, settings: settings)
            guard command.status == .found else {
                throw QuotaWakeCLIError.providerUnavailable(tool, command.status)
            }
        }
    }

    private func resolve(_ tool: ToolKind, settings: AppSettings) -> ResolvedToolCommand {
        detector.resolve(tool: tool, manualPath: settings.tools[tool].manualPath)
    }

    private func providerSnapshot(tool: ToolKind, settings: AppSettings) -> ProviderSnapshot {
        let command = resolve(tool, settings: settings)
        let state = (try? quotaStateStore.load(tool: tool)) ?? nil
        return ProviderSnapshot(
            provider: tool.rawValue,
            enabled: settings.tools[tool].enabled,
            cliStatus: command.status.rawValue,
            executablePath: command.executableURL?.path,
            confidence: state?.confidence.rawValue,
            classification: state.map { classificationName($0.classification) },
            observedAt: state?.observedAt,
            resetAt: state?.resetAt,
            usedPercent: state?.usedPercent,
            weeklyUsedPercent: state?.weeklyUsedPercent,
            summary: state?.summary
        )
    }

    private func classificationName(_ classification: QuotaSourceClassification) -> String {
        switch classification {
        case .sent: return "sent"
        case .limitReached: return "limit_reached"
        case .authRequired: return "auth_required"
        case .apiBillingEnvPresent: return "api_billing_env_present"
        case .usageLimitNoReset: return "usage_limit_no_reset"
        case .quotaUnavailable: return "quota_unavailable"
        case .unknownFailure: return "unknown_failure"
        }
    }

    private func parseBoolean(_ raw: String) throws -> Bool {
        switch raw.lowercased() {
        case "true", "yes", "1", "on": return true
        case "false", "no", "0", "off": return false
        default:
            throw QuotaWakeCLIError.invalidConfiguration("expected a boolean value, got '\(raw)'")
        }
    }
}

public enum CLIJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}
