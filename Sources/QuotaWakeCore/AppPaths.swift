import Foundation

public struct QuotaWakePaths: Equatable, Sendable {
    public let applicationSupportDirectory: URL

    public init(
        applicationSupportDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? Self.defaultApplicationSupportDirectory(
                environment: environment,
                homeDirectory: homeDirectory
            )
    }

    public var settingsFile: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json", isDirectory: false)
    }

    public var logsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    public var runDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Run", isDirectory: true)
    }

    public var quotaStateDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("QuotaWindows", isDirectory: true)
    }

    public var daemonPIDFile: URL {
        applicationSupportDirectory.appendingPathComponent("daemon.pid", isDirectory: false)
    }

    public func createDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: quotaStateDirectory, withIntermediateDirectories: true)
    }

    public static func defaultApplicationSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = nonEmpty(environment["QUOTAWAKE_HOME"]) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        #if os(Windows)
        if let localAppData = nonEmpty(environment["LOCALAPPDATA"] ?? environment["APPDATA"]) {
            return URL(fileURLWithPath: localAppData, isDirectory: true)
                .appendingPathComponent("QuotaWake", isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Local", isDirectory: true)
            .appendingPathComponent("QuotaWake", isDirectory: true)
        #elseif os(macOS)
        return homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("QuotaWake", isDirectory: true)
        #else
        if let stateHome = nonEmpty(environment["XDG_STATE_HOME"]) {
            return URL(fileURLWithPath: stateHome, isDirectory: true)
                .appendingPathComponent("quotawake", isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("quotawake", isDirectory: true)
        #endif
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
