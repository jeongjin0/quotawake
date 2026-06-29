import Foundation

public struct WakeHelperInstallPlan: Equatable, Sendable {
    public let adminInstallScript: String
    public let adminUninstallScript: String
    public let osascriptArguments: [String]
}

public enum WakeHelperInstallerError: Error, Equatable, LocalizedError, Sendable {
    case osascriptFailed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .osascriptFailed(exitCode, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Wake helper administrator action failed with exit code \(exitCode)."
            }
            return "Wake helper administrator action failed with exit code \(exitCode): \(detail)"
        }
    }
}

public struct WakeHelperInstaller: Equatable, Sendable {
    public typealias RunOSAScript = ([String]) throws -> Void

    private let renderer: WakeHelperRenderer

    public init(renderer: WakeHelperRenderer = WakeHelperRenderer()) {
        self.renderer = renderer
    }

    public func stageFiles(configuration: WakeHelperConfiguration, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: configuration.stagedDirectory, withIntermediateDirectories: true)
        try renderer.renderHelperScript(configuration: configuration)
            .write(to: configuration.stagedHelper, atomically: true, encoding: .utf8)
        try renderer.renderLaunchDaemonPlist(configuration: configuration)
            .write(to: configuration.stagedPlist, options: [.atomic])
    }

    public func renderInstallPlan(configuration: WakeHelperConfiguration) throws -> WakeHelperInstallPlan {
        let install = try adminInstallScript(configuration: configuration)
        let uninstall = adminUninstallScript(configuration: configuration)
        return WakeHelperInstallPlan(
            adminInstallScript: install,
            adminUninstallScript: uninstall,
            osascriptArguments: Self.osascriptArguments(for: install)
        )
    }

    @discardableResult
    public func install(
        configuration: WakeHelperConfiguration,
        fileManager: FileManager = .default,
        runOSAScript: RunOSAScript = Self.runOSAScript(arguments:)
    ) throws -> WakeHelperInstallPlan {
        try stageFiles(configuration: configuration, fileManager: fileManager)
        let plan = try renderInstallPlan(configuration: configuration)
        try runOSAScript(plan.osascriptArguments)
        return plan
    }

    public static func runOSAScript(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript", isDirectory: false)
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
            throw WakeHelperInstallerError.osascriptFailed(
                exitCode: process.terminationStatus,
                stderr: message
            )
        }
    }

    private static func osascriptArguments(for shellScript: String) -> [String] {
        [
            "-e",
            "on run argv",
            "-e",
            "do shell script item 1 of argv with administrator privileges",
            "-e",
            "end run",
            shellScript
        ]
    }

    private func adminInstallScript(configuration: WakeHelperConfiguration) throws -> String {
        let helperContent = renderer.renderHelperScript(configuration: configuration)
        let plistContent = try renderer.renderLaunchDaemonPlist(configuration: configuration)
        let rootHelper = WakeHelperRenderer.shellQuote(configuration.rootHelper.path)
        let rootPlist = WakeHelperRenderer.shellQuote(configuration.rootPlist.path)
        let rootHelperDirectory = WakeHelperRenderer.shellQuote(configuration.rootHelper.deletingLastPathComponent().path)
        let rootStateDirectory = WakeHelperRenderer.shellQuote(configuration.rootLastWakeFile.deletingLastPathComponent().path)
        let logDirectory = WakeHelperRenderer.shellQuote(configuration.logDirectory.path)
        let label = WakeHelperRenderer.shellQuote(configuration.label)
        let helperBase64 = WakeHelperRenderer.shellQuote(Data(helperContent.utf8).base64EncodedString())
        let plistBase64 = WakeHelperRenderer.shellQuote(plistContent.base64EncodedString())

        return """
        set -eu
        cleanup() {
          /bin/rm -f \(rootHelper) \(rootPlist)
        }
        if [ -L \(rootHelperDirectory) ] || [ -L \(rootStateDirectory) ] || [ -L \(logDirectory) ]; then
          exit 1
        fi
        /bin/mkdir -p \(rootHelperDirectory) \(rootStateDirectory) \(logDirectory)
        /usr/sbin/chown root:wheel \(rootHelperDirectory) \(rootStateDirectory) \(logDirectory)
        /bin/chmod 755 \(rootHelperDirectory) \(rootStateDirectory) \(logDirectory)
        write_embedded() {
          destination="$1"
          mode="$2"
          content="$3"
          temp="${destination}.quotawake-install.$$"
          /bin/rm -f "$temp"
          /usr/bin/printf '%s' "$content" | /usr/bin/base64 -D > "$temp"
          /usr/sbin/chown root:wheel "$temp"
          /bin/chmod "$mode" "$temp"
          /bin/mv -f "$temp" "$destination"
        }
        write_embedded \(rootHelper) 755 \(helperBase64)
        write_embedded \(rootPlist) 644 \(plistBase64)
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        if ! /bin/launchctl bootstrap system \(rootPlist); then
          cleanup
          exit 1
        fi
        """
    }

    private func adminUninstallScript(configuration: WakeHelperConfiguration) -> String {
        let rootHelper = WakeHelperRenderer.shellQuote(configuration.rootHelper.path)
        let rootPlist = WakeHelperRenderer.shellQuote(configuration.rootPlist.path)
        let rootLast = WakeHelperRenderer.shellQuote(configuration.rootLastWakeFile.path)
        let label = WakeHelperRenderer.shellQuote(configuration.label)

        return """
        set -eu
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        OLD=""
        if [ -f \(rootLast) ]; then
          OLD="$(/usr/bin/tr -d '\\r\\n' < \(rootLast))"
        fi
        case "$OLD" in
          [0-9][0-9]/[0-9][0-9]/[0-9][0-9]\\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) /usr/bin/pmset schedule cancel wake "$OLD" || true ;;
        esac
        /bin/rm -f \(rootPlist) \(rootHelper) \(rootLast)
        """
    }
}
