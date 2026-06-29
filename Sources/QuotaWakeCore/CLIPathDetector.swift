import Darwin
import Foundation

public enum CLIResolutionStatus: String, Codable, Equatable, Sendable {
    case found
    case manualPathInvalid
    case missing
    case nodeRuntimeMissing
    case brokenExecutable
}

public struct ResolvedToolCommand: Equatable, Sendable {
    public let tool: ToolKind
    public let executableURL: URL?
    public let status: CLIResolutionStatus
    public let childPATH: String
    public let searchedDirectories: [URL]

    public init(
        tool: ToolKind,
        executableURL: URL?,
        status: CLIResolutionStatus,
        childPATH: String,
        searchedDirectories: [URL]
    ) {
        self.tool = tool
        self.executableURL = executableURL
        self.status = status
        self.childPATH = childPATH
        self.searchedDirectories = searchedDirectories
    }

    public var executableDirectory: URL? {
        executableURL?.deletingLastPathComponent()
    }
}

public struct CLIPathDetector {
    public static let defaultSystemBinDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let commonBinDirectories: [URL]
    private let codexHealthProbeTimeoutSeconds: TimeInterval

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        commonBinDirectories: [URL] = Self.defaultSystemBinDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) },
        fileManager: FileManager = .default,
        codexHealthProbeTimeoutSeconds: TimeInterval = 2
    ) {
        self.homeDirectory = homeDirectory
        self.commonBinDirectories = commonBinDirectories
        self.fileManager = fileManager
        self.codexHealthProbeTimeoutSeconds = codexHealthProbeTimeoutSeconds
    }

    public func resolve(tool: ToolKind, manualPath: String? = nil) -> ResolvedToolCommand {
        let commandName = tool.executableName

        if let manualPath, !manualPath.isEmpty {
            let manualURL = URL(fileURLWithPath: manualPath)
            guard isExecutableFile(manualURL) else {
                return makeResult(tool: tool, executableURL: nil, status: .manualPathInvalid)
            }
            return validateExecutable(tool: tool, executableURL: manualURL)
        }

        var firstBrokenExecutable: URL?
        for directory in searchDirectories() {
            let candidate = directory.appendingPathComponent(commandName, isDirectory: false)
            guard isExecutableFile(candidate) else {
                continue
            }
            let result = validateExecutable(tool: tool, executableURL: candidate)
            if result.status == .brokenExecutable {
                if firstBrokenExecutable == nil {
                    firstBrokenExecutable = candidate
                }
                continue
            }
            return result
        }

        if let firstBrokenExecutable {
            return makeResult(tool: tool, executableURL: firstBrokenExecutable, status: .brokenExecutable)
        }

        return makeResult(tool: tool, executableURL: nil, status: .missing)
    }

    public func searchDirectories() -> [URL] {
        uniqueDirectories(commonBinDirectories + nodePackageDirectories())
    }

    public func nodePackageDirectories() -> [URL] {
        let nvmRoot = homeDirectory
            .appendingPathComponent(".nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)

        let nvmDirectories = nvmVersionDirectories(in: nvmRoot)
            .map { $0.appendingPathComponent("bin", isDirectory: true) }

        let nodeToolDirectories = [
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".yarn/bin", isDirectory: true)
        ]

        return uniqueDirectories(nvmDirectories + nodeToolDirectories)
    }

    private func validateExecutable(tool: ToolKind, executableURL: URL) -> ResolvedToolCommand {
        if usesEnvNodeShebang(executableURL), !hasNodeRuntime(for: executableURL) {
            return makeResult(tool: tool, executableURL: executableURL, status: .nodeRuntimeMissing)
        }
        if tool == .codex, !codexVersionProbeSucceeds(executableURL) {
            return makeResult(tool: tool, executableURL: executableURL, status: .brokenExecutable)
        }
        return makeResult(tool: tool, executableURL: executableURL, status: .found)
    }

    private func codexVersionProbeSucceeds(_ executableURL: URL) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.environment = [
            "HOME": homeDirectory.path,
            "PATH": childPATH(for: executableURL)
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return false
        }

        let timeout = DispatchTime.now() + .milliseconds(max(1, Int(codexHealthProbeTimeoutSeconds * 1000)))
        if semaphore.wait(timeout: timeout) == .timedOut {
            terminateTimedOutProbe(process, semaphore: semaphore)
            return false
        }

        return process.terminationStatus == 0
    }

    private func terminateTimedOutProbe(_ process: Process, semaphore: DispatchSemaphore) {
        let processID = process.processIdentifier
        let processGroupID = getpgid(processID)
        let canSignalProcessGroup = processGroupID == processID

        guard process.isRunning || canSignalProcessGroup else { return }

        if canSignalProcessGroup {
            killProcessGroup(processGroupID, signal: SIGTERM)
        } else {
            process.terminate()
        }

        let parentExited = semaphore.wait(timeout: .now() + .milliseconds(100)) == .success

        if canSignalProcessGroup {
            killProcessGroup(processGroupID, signal: SIGKILL)
        } else if !parentExited, process.isRunning {
            kill(processID, SIGKILL)
        }

        if !parentExited {
            _ = semaphore.wait(timeout: .now() + .milliseconds(500))
        }
    }

    private func killProcessGroup(_ processGroupID: pid_t, signal: Int32) {
        guard processGroupID > 1 else { return }
        kill(-processGroupID, signal)
    }

    private func makeResult(
        tool: ToolKind,
        executableURL: URL?,
        status: CLIResolutionStatus
    ) -> ResolvedToolCommand {
        return ResolvedToolCommand(
            tool: tool,
            executableURL: executableURL,
            status: status,
            childPATH: executableURL.map { childPATH(for: $0) } ?? childPATH(for: nil),
            searchedDirectories: searchDirectories()
        )
    }

    private func childPATH(for executableURL: URL?) -> String {
        let detectedDirectory = executableURL?.deletingLastPathComponent()
        let pathDirectories = uniqueDirectories(
            [detectedDirectory].compactMap { $0 } + nodePackageDirectories() + commonBinDirectories
        )
        return pathDirectories.map(\.path).joined(separator: ":")
    }

    private func hasNodeRuntime(for executableURL: URL) -> Bool {
        let candidateDirectories = uniqueDirectories(
            [executableURL.deletingLastPathComponent()] + nodePackageDirectories() + commonBinDirectories
        )
        return candidateDirectories.contains { directory in
            isExecutableFile(directory.appendingPathComponent("node", isDirectory: false))
        }
    }

    private func usesEnvNodeShebang(_ url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let firstLine = contents.split(separator: "\n", maxSplits: 1).first else {
            return false
        }
        return firstLine.contains("/usr/bin/env node") || firstLine.contains("env node")
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    private func nvmVersionDirectories(in root: URL) -> [URL] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { isDirectory($0) }
            .sorted { lhs, rhs in
                compareNodeVersion(lhs.lastPathComponent, rhs.lastPathComponent) == .orderedDescending
            }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func compareNodeVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        for index in 0..<max(lhsParts.count, rhsParts.count) {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left > right {
                return .orderedDescending
            }
            if left < right {
                return .orderedAscending
            }
        }
        return lhs.localizedStandardCompare(rhs)
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for directory in directories {
            let standardized = directory.standardizedFileURL
            guard seen.insert(standardized.path).inserted else {
                continue
            }
            result.append(standardized)
        }

        return result
    }
}

public extension ToolKind {
    var executableName: String {
        rawValue
    }
}
