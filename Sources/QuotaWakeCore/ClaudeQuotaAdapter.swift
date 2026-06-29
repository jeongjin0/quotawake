import Foundation

public final class ClaudeQuotaAdapter {
    private let executableURL: URL
    private let runDirectory: URL
    private let runner: QuotaProbeRunning
    private let timeoutSeconds: TimeInterval
    private let parentEnvironment: [String: String]

    public init(
        executableURL: URL,
        runDirectory: URL,
        runner: QuotaProbeRunning = QuotaProbeProcessRunner(),
        timeoutSeconds: TimeInterval = 3,
        parentEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.runDirectory = runDirectory
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
        self.parentEnvironment = parentEnvironment
    }

    public func observe(observedAt: Date = Date()) -> QuotaWindowState {
        let policy = CLIChildEnvironmentPolicy.build(parentEnvironment: parentEnvironment, requestEnvironment: [:], tool: .claude)
        let request = QuotaProbeRequest(
            tool: .claude,
            executableURL: executableURL,
            arguments: ["/usage"],
            environment: policy.environment,
            runDirectory: runDirectory,
            timeoutSeconds: timeoutSeconds
        )
        do {
            let result = try runner.run(request)
            return QuotaWindowParser.parse(
                tool: .claude,
                source: .claudeUsageProbe,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                timedOut: result.timedOut,
                observedAt: observedAt
            )
        } catch {
            return QuotaWindowState(
                tool: .claude,
                source: .claudeUsageProbe,
                confidence: .unknown,
                classification: .unknownFailure,
                observedAt: observedAt,
                summary: "claude usage probe failed"
            )
        }
    }
}
