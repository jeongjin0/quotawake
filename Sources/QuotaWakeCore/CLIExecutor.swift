import Foundation

// SIZE_OK(MVP): CLI execution, overlap guarding, and log entry conversion stay in
// one file so argv/process invariants are reviewed together. Follow-up split:
// CLIExecutor.swift, ToolRunner.swift, and BoundedPipe.swift.

#if canImport(Darwin)
import Darwin
#endif

public struct CLICommandTemplate: Equatable, Sendable {
    public init() {}

    public func arguments(for tool: ToolKind, prompt: String, runDirectory: URL) -> [String] {
        switch tool {
        case .claude:
            return [
                "--print",
                "--output-format",
                "text",
                "--no-session-persistence",
                prompt
            ]
        case .codex:
            return [
                "exec",
                "--sandbox",
                "read-only",
                "--skip-git-repo-check",
                "--ephemeral",
                "--ignore-rules",
                "--color",
                "never",
                "-C",
                runDirectory.path,
                prompt
            ]
        }
    }
}

public struct CLIExecutionRequest: Equatable, Sendable {
    public let tool: ToolKind
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let runDirectory: URL
    public let timeoutSeconds: TimeInterval
    public let prompt: String
    public let scheduledAt: Date
    public let eventId: String

    public init(
        tool: ToolKind,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        runDirectory: URL,
        timeoutSeconds: TimeInterval = 120,
        prompt: String,
        scheduledAt: Date,
        eventId: String
    ) {
        self.tool = tool
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.runDirectory = runDirectory
        self.timeoutSeconds = timeoutSeconds
        self.prompt = prompt
        self.scheduledAt = scheduledAt
        self.eventId = eventId
    }
}

public struct CLIExecutionResult: Equatable, Sendable {
    public let exitCode: Int?
    public let timedOut: Bool
    public let stdout: String
    public let stderr: String
    public let durationMs: Int
    public let startedAt: Date
    public let endedAt: Date
}

public struct CLIChildEnvironmentPolicy: Equatable, Sendable {
    public let environment: [String: String]
    public let scrubbedKeyNames: [String]

    public static func build(
        parentEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        requestEnvironment: [String: String],
        tool: ToolKind
    ) -> CLIChildEnvironmentPolicy {
        var environment = parentEnvironment
        requestEnvironment.forEach { key, value in
            environment[key] = value
        }

        let guardedKeys: Set<String>
        switch tool {
        case .claude, .codex:
            guardedKeys = apiBillingEnvironmentKeys
        }

        var scrubbedKeyNames = Set<String>()
        for key in guardedKeys where environment[key] != nil {
            environment.removeValue(forKey: key)
            scrubbedKeyNames.insert(key)
        }

        return CLIChildEnvironmentPolicy(
            environment: environment,
            scrubbedKeyNames: scrubbedKeyNames.sorted()
        )
    }

    public static let apiBillingEnvironmentKeys: Set<String> = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_CUSTOM_HEADERS",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "OPENAI_API_BASE",
        "OPENAI_API_HOST",
        "OPENAI_ORGANIZATION",
        "OPENAI_ORG_ID",
        "OPENAI_PROJECT",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_ANTHROPIC_AWS",
        "CLAUDE_CODE_USE_FOUNDRY",
        "AWS_PROFILE",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "AZURE_API_KEY",
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_CLIENT_ID",
        "AZURE_CLIENT_SECRET",
        "AZURE_TENANT_ID",
        "AZURE_SUBSCRIPTION_ID",
        "AZURE_FOUNDRY_API_KEY",
        "AZURE_AI_FOUNDRY_API_KEY",
        "AZURE_INFERENCE_ENDPOINT",
        "AZURE_AUTHORITY_HOST",
        "FOUNDRY_API_KEY",
        "FOUNDRY_ENDPOINT"
    ]

    public static let claudeBillingEnvironmentKeys = apiBillingEnvironmentKeys
}

public final class CLIExecutor {
    private let fileManager: FileManager
    private let outputLimitBytes: Int

    public init(fileManager: FileManager = .default, outputLimitBytes: Int = 65_536) {
        self.fileManager = fileManager
        self.outputLimitBytes = outputLimitBytes
    }

    public func run(_ request: CLIExecutionRequest) throws -> CLIExecutionResult {
        try fileManager.createDirectory(
            at: request.runDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.runDirectory

        let childEnvironment = CLIChildEnvironmentPolicy.build(
            requestEnvironment: request.environment,
            tool: request.tool
        )
        process.environment = childEnvironment.environment

        let stdout = BoundedPipeCollector(limitBytes: outputLimitBytes)
        let stderr = BoundedPipeCollector(limitBytes: outputLimitBytes)
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe

        let startedAt = Date()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        stdout.start()
        stderr.start()
        do {
            try process.run()
        } catch {
            stdout.stop()
            stderr.stop()
            throw error
        }

        let waitResult = finished.wait(timeout: .now() + request.timeoutSeconds)
        let timedOut = waitResult == .timedOut
        if timedOut {
            terminate(process)
        }

        process.waitUntilExit()
        let endedAt = Date()
        stdout.stop()
        stderr.stop()

        return CLIExecutionResult(
            exitCode: timedOut ? nil : Int(process.terminationStatus),
            timedOut: timedOut,
            stdout: stdout.string(),
            stderr: stderr.string(),
            durationMs: Self.durationMs(startedAt: startedAt, endedAt: endedAt),
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    private func terminate(_ process: Process) {
        ProcessTreeTerminator.terminate(process)
    }

    private static func durationMs(startedAt: Date, endedAt: Date) -> Int {
        max(0, Int((endedAt.timeIntervalSince(startedAt) * 1_000).rounded()))
    }
}

public final class OverlapGuard {
    private let lock = NSLock()
    private var runningTools = Set<ToolKind>()

    public init() {}

    public func tryBegin(_ tool: ToolKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !runningTools.contains(tool) else {
            return false
        }
        runningTools.insert(tool)
        return true
    }

    public func end(_ tool: ToolKind) {
        lock.lock()
        defer { lock.unlock() }
        runningTools.remove(tool)
    }
}

public struct ToolRunRequest: Equatable, Sendable {
    public let command: ResolvedToolCommand
    public let prompt: String
    public let eventId: String
    public let scheduledAt: Date
    public let runDirectory: URL
    public let timeoutSeconds: TimeInterval
    public let decisionSource: QuotaReadinessDecisionSource?
    public let quotaConfidence: QuotaWindowConfidence?

    public init(
        command: ResolvedToolCommand,
        prompt: String,
        eventId: String,
        scheduledAt: Date,
        runDirectory: URL,
        timeoutSeconds: TimeInterval = 120,
        decisionSource: QuotaReadinessDecisionSource? = nil,
        quotaConfidence: QuotaWindowConfidence? = nil
    ) {
        self.command = command
        self.prompt = prompt
        self.eventId = eventId
        self.scheduledAt = scheduledAt
        self.runDirectory = runDirectory
        self.timeoutSeconds = timeoutSeconds
        self.decisionSource = decisionSource
        self.quotaConfidence = quotaConfidence
    }
}

public final class ToolRunner {
    private let executor: CLIExecutor
    private let logStore: RunLogStore
    private let overlapGuard: OverlapGuard
    private let commandTemplate: CLICommandTemplate
    private let logLock = NSLock()

    public init(
        executor: CLIExecutor = CLIExecutor(),
        logStore: RunLogStore = RunLogStore(),
        overlapGuard: OverlapGuard = OverlapGuard(),
        commandTemplate: CLICommandTemplate = CLICommandTemplate()
    ) {
        self.executor = executor
        self.logStore = logStore
        self.overlapGuard = overlapGuard
        self.commandTemplate = commandTemplate
    }

    public func run(_ request: ToolRunRequest) throws -> RunLogEntry {
        let command = request.command
        let commandPath = command.executableURL?.path ?? ""

        guard overlapGuard.tryBegin(command.tool) else {
            let now = Date()
            let entry = RunLogEntry(
                eventId: request.eventId,
                scheduledAt: request.scheduledAt,
                startedAt: now,
                endedAt: now,
                tool: command.tool,
                commandPath: commandPath,
                status: .skippedOverlap,
                exitCode: nil,
                durationMs: 0,
                timedOut: false,
                stdoutSummary: "",
                stderrSummary: "",
                prompt: request.prompt,
                errorSummary: "Provider is already running",
                decisionSource: request.decisionSource,
                quotaConfidence: request.quotaConfidence,
                skipReason: "overlap"
            )
            try appendLog(entry)
            return entry
        }
        defer { overlapGuard.end(command.tool) }

        guard command.status == .found, let executableURL = command.executableURL else {
            let now = Date()
            let entry = RunLogEntry(
                eventId: request.eventId,
                scheduledAt: request.scheduledAt,
                startedAt: now,
                endedAt: now,
                tool: command.tool,
                commandPath: commandPath,
                status: .failed,
                exitCode: nil,
                durationMs: 0,
                timedOut: false,
                stdoutSummary: "",
                stderrSummary: "",
                prompt: request.prompt,
                errorSummary: "CLI resolution status: \(command.status.rawValue)",
                decisionSource: request.decisionSource,
                quotaConfidence: request.quotaConfidence
            )
            try appendLog(entry)
            return entry
        }

        let arguments = commandTemplate.arguments(
            for: command.tool,
            prompt: request.prompt,
            runDirectory: request.runDirectory
        )
        let executionRequest = CLIExecutionRequest(
            tool: command.tool,
            executableURL: executableURL,
            arguments: arguments,
            environment: ["PATH": command.childPATH],
            runDirectory: request.runDirectory,
            timeoutSeconds: request.timeoutSeconds,
            prompt: request.prompt,
            scheduledAt: request.scheduledAt,
            eventId: request.eventId
        )

        do {
            let result = try executor.run(executionRequest)
            let graded = Self.gradedStatus(for: result, tool: command.tool)
            let entry = RunLogEntry(
                eventId: request.eventId,
                scheduledAt: request.scheduledAt,
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                tool: command.tool,
                commandPath: executableURL.path,
                status: graded.status,
                exitCode: result.exitCode,
                durationMs: result.durationMs,
                timedOut: result.timedOut,
                stdoutSummary: result.stdout,
                stderrSummary: result.stderr,
                prompt: request.prompt,
                errorSummary: graded.errorSummary,
                decisionSource: request.decisionSource,
                quotaConfidence: request.quotaConfidence
            )
            try appendLog(entry)
            return entry
        } catch {
            let now = Date()
            let entry = RunLogEntry(
                eventId: request.eventId,
                scheduledAt: request.scheduledAt,
                startedAt: now,
                endedAt: now,
                tool: command.tool,
                commandPath: executableURL.path,
                status: .failed,
                exitCode: nil,
                durationMs: 0,
                timedOut: false,
                stdoutSummary: "",
                stderrSummary: "",
                prompt: request.prompt,
                errorSummary: error.localizedDescription,
                decisionSource: request.decisionSource,
                quotaConfidence: request.quotaConfidence
            )
            try appendLog(entry)
            return entry
        }
    }

    private func appendLog(_ entry: RunLogEntry) throws {
        logLock.lock()
        defer { logLock.unlock() }
        try logStore.append(entry)
    }

    private static func gradedStatus(
        for result: CLIExecutionResult,
        tool: ToolKind
    ) -> (status: RunStatus, errorSummary: String?) {
        if result.timedOut {
            return (.timedOut, nil)
        }
        guard result.exitCode == 0 else {
            return (.failed, "CLI exited with code \(result.exitCode ?? -1)")
        }
        // Some CLIs exit 0 while reporting they could not serve the prompt
        // (usage limit banner, login prompt). Recording those as sent would
        // mark the reset window completed and anchor the next 5h estimate on
        // a send that never started a window.
        let parsed = QuotaWindowParser.parse(
            tool: tool,
            source: .cliMessageParser,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            timedOut: result.timedOut,
            observedAt: result.endedAt
        )
        switch parsed.classification {
        case .limitReached:
            return (.failed, "CLI exited 0 but reported a usage limit; not counting as a sent readiness prompt")
        case .authRequired:
            return (.failed, "CLI exited 0 but reported authentication is required")
        case .usageLimitNoReset:
            // Keyword-only match with no parsed reset time is a weaker signal:
            // a normal model reply that merely mentions "rate limit" must not
            // be demoted, so require an explicit limit-banner phrase.
            let lowered = (result.stdout + "\n" + result.stderr).lowercased()
            let bannerPhrases = ["usage limit", "limit reached", "hit your limit"]
            if bannerPhrases.contains(where: lowered.contains) {
                return (.failed, "CLI exited 0 but reported a usage limit without a reset time")
            }
            return (.sent, nil)
        case .apiBillingEnvPresent:
            return (.failed, "CLI exited 0 but reported an API billing key environment")
        case .sent, .quotaUnavailable, .unknownFailure:
            return (.sent, nil)
        }
    }
}

