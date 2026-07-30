import Foundation
import QuotaWakeCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum BackgroundServiceState: String, Codable {
    case running
    case stopped
    case notInstalled = "not_installed"
    case unknown
}

public struct BackgroundServiceSnapshot: Codable {
    public let platform: String
    public let state: BackgroundServiceState
    public let definitionPath: String?
}

public struct PlatformServiceManager {
    private let executableURL: URL
    private let paths: QuotaWakePaths
    private let fileManager: FileManager

    public init(
        executableURL: URL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL,
        paths: QuotaWakePaths = QuotaWakePaths(),
        fileManager: FileManager = .default
    ) {
        self.executableURL = executableURL
        self.paths = paths
        self.fileManager = fileManager
    }

    public func install() throws -> BackgroundServiceSnapshot {
        try paths.createDirectories(fileManager: fileManager)
        #if os(macOS)
        let definition = macOSLaunchAgentURL
        try fileManager.createDirectory(at: definition.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "Label": serviceIdentifier,
            "ProgramArguments": [executableURL.path, "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": paths.logsDirectory.appendingPathComponent("daemon.stdout.log").path,
            "StandardErrorPath": paths.logsDirectory.appendingPathComponent("daemon.stderr.log").path
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: definition, options: .atomic)
        _ = try? run("/bin/launchctl", ["bootout", macOSDomain, definition.path])
        try requireSuccess(run("/bin/launchctl", ["bootstrap", macOSDomain, definition.path]))
        try requireSuccess(run("/bin/launchctl", ["enable", "\(macOSDomain)/\(serviceIdentifier)"]))
        return try status()
        #elseif os(Linux)
        let definition = linuxSystemdUnitURL
        try fileManager.createDirectory(at: definition.deletingLastPathComponent(), withIntermediateDirectories: true)
        let unit = """
        [Unit]
        Description=QuotaWake usage-window readiness daemon
        After=default.target

        [Service]
        Type=simple
        ExecStart=\(systemdQuote(executableURL.path)) daemon
        Restart=on-failure
        RestartSec=10
        Environment=QUOTAWAKE_HOME=\(systemdQuote(paths.applicationSupportDirectory.path))

        [Install]
        WantedBy=default.target
        """
        try unit.write(to: definition, atomically: true, encoding: .utf8)
        try requireSuccess(run("/usr/bin/systemctl", ["--user", "daemon-reload"]))
        try requireSuccess(run("/usr/bin/systemctl", ["--user", "enable", "--now", "quotawake.service"]))
        return try status()
        #elseif os(Windows)
        let command = "\"\(executableURL.path)\" daemon"
        try requireSuccess(run(windowsTaskCommand, [
            "/Create", "/F", "/SC", "ONLOGON", "/TN", "QuotaWake", "/TR", command
        ]))
        try requireSuccess(run(windowsTaskCommand, ["/Run", "/TN", "QuotaWake"]))
        return try status()
        #else
        throw QuotaWakeCLIError.unsupportedServicePlatform
        #endif
    }

    public func uninstall() throws -> BackgroundServiceSnapshot {
        #if os(macOS)
        _ = try? run("/bin/launchctl", ["bootout", macOSDomain, macOSLaunchAgentURL.path])
        try? fileManager.removeItem(at: macOSLaunchAgentURL)
        return try status()
        #elseif os(Linux)
        _ = try? run("/usr/bin/systemctl", ["--user", "disable", "--now", "quotawake.service"])
        try? fileManager.removeItem(at: linuxSystemdUnitURL)
        _ = try? run("/usr/bin/systemctl", ["--user", "daemon-reload"])
        return try status()
        #elseif os(Windows)
        _ = try? run(windowsTaskCommand, ["/Delete", "/F", "/TN", "QuotaWake"])
        return try status()
        #else
        throw QuotaWakeCLIError.unsupportedServicePlatform
        #endif
    }

    public func start() throws -> BackgroundServiceSnapshot {
        #if os(macOS)
        try requireSuccess(run("/bin/launchctl", ["bootstrap", macOSDomain, macOSLaunchAgentURL.path]))
        #elseif os(Linux)
        try requireSuccess(run("/usr/bin/systemctl", ["--user", "start", "quotawake.service"]))
        #elseif os(Windows)
        try requireSuccess(run(windowsTaskCommand, ["/Run", "/TN", "QuotaWake"]))
        #else
        throw QuotaWakeCLIError.unsupportedServicePlatform
        #endif
        return try status()
    }

    public func stop() throws -> BackgroundServiceSnapshot {
        #if os(macOS)
        _ = try? run("/bin/launchctl", ["bootout", macOSDomain, macOSLaunchAgentURL.path])
        #elseif os(Linux)
        _ = try? run("/usr/bin/systemctl", ["--user", "stop", "quotawake.service"])
        #elseif os(Windows)
        _ = try? run(windowsTaskCommand, ["/End", "/TN", "QuotaWake"])
        #else
        throw QuotaWakeCLIError.unsupportedServicePlatform
        #endif
        return try status()
    }

    public func status() throws -> BackgroundServiceSnapshot {
        #if os(macOS)
        guard fileManager.fileExists(atPath: macOSLaunchAgentURL.path) else {
            return BackgroundServiceSnapshot(platform: "macos-launchd", state: .notInstalled, definitionPath: nil)
        }
        let result = try run("/bin/launchctl", ["print", "\(macOSDomain)/\(serviceIdentifier)"])
        return BackgroundServiceSnapshot(
            platform: "macos-launchd",
            state: result.exitCode == 0 ? .running : .stopped,
            definitionPath: macOSLaunchAgentURL.path
        )
        #elseif os(Linux)
        guard fileManager.fileExists(atPath: linuxSystemdUnitURL.path) else {
            return BackgroundServiceSnapshot(platform: "linux-systemd-user", state: .notInstalled, definitionPath: nil)
        }
        let result = try run("/usr/bin/systemctl", ["--user", "is-active", "quotawake.service"])
        return BackgroundServiceSnapshot(
            platform: "linux-systemd-user",
            state: result.exitCode == 0 ? .running : .stopped,
            definitionPath: linuxSystemdUnitURL.path
        )
        #elseif os(Windows)
        let result = try run(windowsTaskCommand, ["/Query", "/TN", "QuotaWake"])
        return BackgroundServiceSnapshot(
            platform: "windows-task-scheduler",
            state: result.exitCode == 0 ? .running : .notInstalled,
            definitionPath: nil
        )
        #else
        return BackgroundServiceSnapshot(platform: "unsupported", state: .unknown, definitionPath: nil)
        #endif
    }

    private let serviceIdentifier = "com.jeongjin.quotawake.cli"

    #if os(macOS)
    private var macOSDomain: String {
        "gui/\(getuid())"
    }

    private var macOSLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(serviceIdentifier).plist", isDirectory: false)
    }
    #endif

    #if os(Linux)
    private var linuxSystemdUnitURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let root: URL
        if let configHome = environment["XDG_CONFIG_HOME"], !configHome.isEmpty {
            root = URL(fileURLWithPath: configHome, isDirectory: true)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return root
            .appendingPathComponent("systemd/user", isDirectory: true)
            .appendingPathComponent("quotawake.service", isDirectory: false)
    }

    private func systemdQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    #endif

    #if os(Windows)
    private var windowsTaskCommand: String {
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        return URL(fileURLWithPath: systemRoot, isDirectory: true)
            .appendingPathComponent("System32/schtasks.exe", isDirectory: false)
            .path
    }
    #endif

    private struct CommandResult {
        let exitCode: Int32
        let output: String
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw QuotaWakeCLIError.serviceCommandFailed("could not run service command: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func requireSuccess(_ result: CommandResult) throws {
        guard result.exitCode == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw QuotaWakeCLIError.serviceCommandFailed(
                detail.isEmpty ? "service command failed with exit code \(result.exitCode)" : detail
            )
        }
    }
}

public final class DaemonLease {
    private let pidFile: URL
    private let fileManager: FileManager

    public init(pidFile: URL, fileManager: FileManager = .default) {
        self.pidFile = pidFile
        self.fileManager = fileManager
    }

    public func acquire() throws {
        if let existing = existingPID(), isProcessAlive(existing) {
            throw QuotaWakeCLIError.daemonAlreadyRunning(existing)
        }
        try? fileManager.removeItem(at: pidFile)
        try fileManager.createDirectory(at: pidFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(ProcessInfo.processInfo.processIdentifier)\n".write(to: pidFile, atomically: true, encoding: .utf8)
    }

    public func release() {
        try? fileManager.removeItem(at: pidFile)
    }

    private func existingPID() -> Int32? {
        guard let value = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        #if os(Windows)
        return false
        #else
        return kill(pid, 0) == 0 || errno == EPERM
        #endif
    }
}
