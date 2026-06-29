import Foundation

public enum ToolKind: String, Codable, CaseIterable, Equatable, Sendable {
    case claude
    case codex
}

public struct ToolSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var manualPath: String?

    public init(enabled: Bool = true, manualPath: String? = nil) {
        self.enabled = enabled
        self.manualPath = manualPath
    }
}

public struct ToolSettingsSet: Codable, Equatable, Sendable {
    public var claude: ToolSettings
    public var codex: ToolSettings

    public init(
        claude: ToolSettings = ToolSettings(),
        codex: ToolSettings = ToolSettings()
    ) {
        self.claude = claude
        self.codex = codex
    }

    public subscript(kind: ToolKind) -> ToolSettings {
        get {
            switch kind {
            case .claude:
                claude
            case .codex:
                codex
            }
        }
        set {
            switch kind {
            case .claude:
                claude = newValue
            case .codex:
                codex = newValue
            }
        }
    }
}

public struct ScheduleTime: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour) else {
            throw ValidationError.invalidHour
        }
        guard (0...59).contains(minute) else {
            throw ValidationError.invalidMinute
        }
        self.hour = hour
        self.minute = minute
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidHour
        case invalidMinute
    }
}

public struct Schedule: Codable, Equatable, Sendable {
    public var paused: Bool
    public var weekdays: [Int]
    public var times: [ScheduleTime]
    public var missedRunGraceMinutes: Int

    public init(
        paused: Bool = true,
        weekdays: [Int] = [],
        times: [ScheduleTime] = [],
        missedRunGraceMinutes: Int = 15
    ) {
        self.paused = paused
        self.weekdays = weekdays
        self.times = times
        self.missedRunGraceMinutes = missedRunGraceMinutes
    }
}

public struct BackgroundSettings: Codable, Equatable, Sendable {
    public var launchAtLoginEnabled: Bool

    public init(launchAtLoginEnabled: Bool = false) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}

public struct WakeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var leadMinutes: Int
    public var helperInstalled: Bool
    public var lastRequestedWake: String?

    public init(
        enabled: Bool = false,
        leadMinutes: Int = 10,
        helperInstalled: Bool = false,
        lastRequestedWake: String? = nil
    ) {
        self.enabled = enabled
        self.leadMinutes = leadMinutes
        self.helperInstalled = helperInstalled
        self.lastRequestedWake = lastRequestedWake
    }
}

public enum ResetEstimationMode: String, Codable, Equatable, Sendable {
    case localSignalsOnly
    case allowFiveHourEstimate
}

public struct WindowReadinessSettings: Codable, Equatable, Sendable {
    public var activeOnly: Bool
    public var idleThresholdSeconds: Int
    public var minimumSendCooldownMinutes: Int
    public var resetEstimationMode: ResetEstimationMode

    public init(
        activeOnly: Bool = true,
        idleThresholdSeconds: Int = 300,
        minimumSendCooldownMinutes: Int = 30,
        resetEstimationMode: ResetEstimationMode = .localSignalsOnly
    ) {
        self.activeOnly = activeOnly
        self.idleThresholdSeconds = max(0, idleThresholdSeconds)
        self.minimumSendCooldownMinutes = max(0, minimumSendCooldownMinutes)
        self.resetEstimationMode = resetEstimationMode
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var firstRunCompleted: Bool
    public var prompt: String
    public var tools: ToolSettingsSet
    public var readiness: WindowReadinessSettings
    public var schedule: Schedule
    public var background: BackgroundSettings
    public var wake: WakeSettings

    public init(
        schemaVersion: Int = 2,
        firstRunCompleted: Bool = false,
        prompt: String = "hi",
        tools: ToolSettingsSet = ToolSettingsSet(),
        readiness: WindowReadinessSettings = WindowReadinessSettings(),
        schedule: Schedule = Schedule(),
        background: BackgroundSettings = BackgroundSettings(),
        wake: WakeSettings = WakeSettings()
    ) {
        self.schemaVersion = max(2, schemaVersion)
        self.firstRunCompleted = firstRunCompleted
        self.prompt = prompt
        self.tools = tools
        self.readiness = readiness
        self.schedule = schedule
        self.background = background
        self.wake = wake
    }

    public static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case firstRunCompleted
        case prompt
        case tools
        case readiness
        case background
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = max(2, decodedVersion)
        firstRunCompleted = try container.decodeIfPresent(Bool.self, forKey: .firstRunCompleted) ?? false
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? "hi"
        tools = try container.decodeIfPresent(ToolSettingsSet.self, forKey: .tools) ?? ToolSettingsSet()
        readiness = try container.decodeIfPresent(WindowReadinessSettings.self, forKey: .readiness)
            ?? WindowReadinessSettings()
        background = try container.decodeIfPresent(BackgroundSettings.self, forKey: .background)
            ?? BackgroundSettings()
        schedule = Schedule()
        wake = WakeSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(max(2, schemaVersion), forKey: .schemaVersion)
        try container.encode(firstRunCompleted, forKey: .firstRunCompleted)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(tools, forKey: .tools)
        try container.encode(readiness, forKey: .readiness)
        try container.encode(background, forKey: .background)
    }
}

public final class SettingsStore {
    private let paths: QuotaWakePaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: QuotaWakePaths = QuotaWakePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> AppSettings {
        guard fileManager.fileExists(atPath: paths.settingsFile.path) else {
            return .default
        }
        let data = try Data(contentsOf: paths.settingsFile)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        try paths.createDirectories(fileManager: fileManager)
        let data = try encoder.encode(settings)
        try data.write(to: paths.settingsFile, options: [.atomic])
    }
}
