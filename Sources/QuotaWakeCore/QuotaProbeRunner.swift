import Foundation

#if canImport(Darwin)
import Darwin
#endif

public struct QuotaProbeRequest: Equatable, Sendable {
    public let tool: ToolKind
    public let executableURL: URL
    public let arguments: [String]
    public let stdin: String?
    public let environment: [String: String]
    public let runDirectory: URL
    public let timeoutSeconds: TimeInterval

    public init(
        tool: ToolKind,
        executableURL: URL,
        arguments: [String],
        stdin: String? = nil,
        environment: [String: String],
        runDirectory: URL,
        timeoutSeconds: TimeInterval
    ) {
        self.tool = tool
        self.executableURL = executableURL
        self.arguments = arguments
        self.stdin = stdin
        self.environment = environment
        self.runDirectory = runDirectory
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct QuotaProbeResult: Equatable, Sendable {
    public let exitCode: Int?
    public let timedOut: Bool
    public let stdout: String
    public let stderr: String
    public let startedAt: Date
    public let endedAt: Date
    public let durationMs: Int

    public init(
        exitCode: Int?,
        timedOut: Bool,
        stdout: String,
        stderr: String,
        startedAt: Date,
        endedAt: Date
    ) {
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = max(0, Int((endedAt.timeIntervalSince(startedAt) * 1_000).rounded()))
    }
}

public protocol QuotaProbeRunning {
    func run(_ request: QuotaProbeRequest) throws -> QuotaProbeResult
}

public final class QuotaProbeProcessRunner: QuotaProbeRunning {
    private let outputLimitBytes: Int
    private let fileManager: FileManager

    public init(outputLimitBytes: Int = 65_536, fileManager: FileManager = .default) {
        self.outputLimitBytes = outputLimitBytes
        self.fileManager = fileManager
    }

    public func run(_ request: QuotaProbeRequest) throws -> QuotaProbeResult {
        try fileManager.createDirectory(at: request.runDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.runDirectory
        process.environment = request.environment

        let stdinPipe = Pipe()
        let stdout = QuotaPipeCollector(limitBytes: outputLimitBytes)
        let stderr = QuotaPipeCollector(limitBytes: outputLimitBytes)
        process.standardInput = stdinPipe
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe

        let startedAt = Date()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        stdout.start()
        stderr.start()
        try process.run()
        if let input = request.stdin {
            stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        }
        try? stdinPipe.fileHandleForWriting.close()

        let timedOut = finished.wait(timeout: .now() + request.timeoutSeconds) == .timedOut
        if timedOut {
            terminate(process)
        }
        process.waitUntilExit()
        let endedAt = Date()
        stdout.stop()
        stderr.stop()

        return QuotaProbeResult(
            exitCode: timedOut ? nil : Int(process.terminationStatus),
            timedOut: timedOut,
            stdout: stdout.string(),
            stderr: stderr.string(),
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    private func terminate(_ process: Process) {
        ProcessTreeTerminator.terminate(process)
    }
}

private final class QuotaPipeCollector {
    let pipe = Pipe()
    private let limitBytes: Int
    private let lock = NSLock()
    private var buffer = Data()

    init(limitBytes: Int) {
        self.limitBytes = limitBytes
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.append(data)
        }
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        append(pipe.fileHandleForReading.availableData)
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    private func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limitBytes - buffer.count)
        if remaining > 0 {
            buffer.append(data.prefix(remaining))
        }
    }
}
