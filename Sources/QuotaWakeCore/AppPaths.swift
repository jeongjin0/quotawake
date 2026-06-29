import Foundation

public struct QuotaWakePaths: Equatable, Sendable {
    public let applicationSupportDirectory: URL

    public init(applicationSupportDirectory: URL? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("QuotaWake", isDirectory: true)
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

    public func createDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: quotaStateDirectory, withIntermediateDirectories: true)
    }
}
