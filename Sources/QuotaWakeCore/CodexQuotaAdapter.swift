import Foundation

public final class CodexAppServerQuotaProcessRunner: QuotaProbeRunning {
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
        let stdout = CodexAppServerLineCollector(limitBytes: outputLimitBytes)
        let stderr = BoundedPipeCollector(limitBytes: outputLimitBytes)

        process.standardInput = stdinPipe
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        process.terminationHandler = { _ in
            stdout.markProcessExited()
        }

        let startedAt = Date()
        stdout.start()
        stderr.start()
        try process.run()

        let deadline = startedAt.addingTimeInterval(request.timeoutSeconds)
        write(Self.initializeMessage, to: stdinPipe)
        if wait(on: stdout.initializeObserved, until: deadline), stdout.didObserveInitialize {
            write(Self.initializedMessage, to: stdinPipe)
            write(Self.rateLimitsMessage, to: stdinPipe)
            _ = wait(on: stdout.rateLimitsObserved, until: deadline)
        }

        let timedOut = !stdout.didObserveRateLimits
        ProcessTreeTerminator.terminate(process)
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

    private static let initializeMessage = jsonLine([
        "id": 1,
        "method": "initialize",
        "params": [
            "clientInfo": [
                "title": "QuotaWake",
                "name": "QuotaWake",
                "version": "0.0.0"
            ],
            "capabilities": [
                "experimentalApi": false,
                "requestAttestation": false,
                "optOutNotificationMethods": [
                    "item/agentMessage/delta",
                    "item/reasoning/summaryTextDelta",
                    "item/reasoning/summaryPartAdded",
                    "item/reasoning/textDelta"
                ]
            ]
        ]
    ])
    private static let initializedMessage = jsonLine([
        "method": "initialized",
        "params": [:]
    ])
    private static let rateLimitsMessage = jsonLine([
        "id": 2,
        "method": "account/rateLimits/read",
        "params": [:]
    ])

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }

    private func write(_ message: String, to pipe: Pipe) {
        // write(contentsOf:) throws on a broken pipe; the legacy write(_:)
        // raised an uncatchable ObjC exception if the app-server exited
        // between the initialize response and this write.
        try? pipe.fileHandleForWriting.write(contentsOf: Data(message.utf8))
    }

    private func wait(on semaphore: DispatchSemaphore, until deadline: Date) -> Bool {
        let remaining = max(0, deadline.timeIntervalSinceNow)
        return semaphore.wait(timeout: .now() + remaining) == .success
    }
}

public final class CodexQuotaAdapter {
    private let executableURL: URL
    private let runDirectory: URL
    private let runner: QuotaProbeRunning
    private let timeoutSeconds: TimeInterval
    private let parentEnvironment: [String: String]

    public init(
        executableURL: URL,
        runDirectory: URL,
        runner: QuotaProbeRunning = CodexAppServerQuotaProcessRunner(),
        timeoutSeconds: TimeInterval = 8,
        parentEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.runDirectory = runDirectory
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
        self.parentEnvironment = parentEnvironment
    }

    public func observe(observedAt: Date = Date()) -> QuotaWindowState {
        let policy = CLIChildEnvironmentPolicy.build(parentEnvironment: parentEnvironment, requestEnvironment: [:], tool: .codex)
        let request = appServerRequest(environment: policy.environment)
        do {
            return parse(try runner.run(request), observedAt: observedAt)
        } catch {
            return QuotaWindowState(
                tool: .codex,
                source: .codexLocalAppServer,
                confidence: .unknown,
                classification: .unknownFailure,
                observedAt: observedAt,
                summary: "codex app-server probe failed"
            )
        }
    }

    private func appServerRequest(environment: [String: String]) -> QuotaProbeRequest {
        QuotaProbeRequest(
            tool: .codex,
            executableURL: executableURL,
            arguments: ["app-server"],
            environment: environment,
            runDirectory: runDirectory,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func parse(_ result: QuotaProbeResult, observedAt: Date) -> QuotaWindowState {
        guard let object = Self.firstJSONObject(in: result.stdout) else {
            if Self.isAppServerUnavailable(result) {
                return Self.unavailableState(observedAt: observedAt, summary: Self.unavailableSummary(result))
            }
            if result.timedOut {
                return QuotaWindowParser.parse(
                    tool: .codex,
                    source: .codexLocalAppServer,
                    stdout: result.stdout,
                    stderr: result.stderr.isEmpty ? "probe timed out" : result.stderr,
                    exitCode: result.exitCode,
                    timedOut: true,
                    observedAt: observedAt
                )
            }
            return QuotaWindowParser.parse(
                tool: .codex,
                source: .codexLocalAppServer,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: nil,
                timedOut: false,
                observedAt: observedAt
            )
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "codex app-server method unavailable"
            return QuotaWindowState(
                tool: .codex,
                source: .codexLocalAppServer,
                confidence: .unknown,
                classification: .unknownFailure,
                observedAt: observedAt,
                summary: message
            )
        }
        guard let resultObject = object["result"] as? [String: Any],
              let window = Self.windowFields(in: resultObject),
              let resetAt = Self.dateValue(in: window, keys: ["resetAt", "reset_at", "resetsAt", "resets_at"]) else {
            return QuotaWindowState(
                tool: .codex,
                source: .codexLocalAppServer,
                confidence: .unknown,
                classification: .unknownFailure,
                observedAt: observedAt,
                summary: "codex app-server response did not include a quota window"
            )
        }
        let weekly = Self.secondaryWindowFields(in: resultObject)
        return QuotaWindowState(
            tool: .codex,
            source: .codexLocalAppServer,
            confidence: .observedLocalQuota,
            classification: .limitReached(resetAt: resetAt),
            observedAt: observedAt,
            resetAt: resetAt,
            usedPercent: Self.doubleValue(in: window, keys: ["usedPercent", "used_percent", "percentUsed", "usagePercent"]),
            remainingPercent: Self.remainingPercent(in: window),
            windowLabel: Self.windowLabel(in: window),
            weeklyUsedPercent: weekly.flatMap { Self.doubleValue(in: $0, keys: ["usedPercent", "used_percent", "percentUsed", "usagePercent"]) },
            weeklyRemainingPercent: weekly.flatMap { Self.remainingPercent(in: $0) },
            weeklyResetAt: weekly.flatMap { Self.dateValue(in: $0, keys: ["resetAt", "reset_at", "resetsAt", "resets_at"]) },
            weeklyWindowLabel: weekly.map { _ in "Weekly" },
            summary: "codex local quota window observed"
        )
    }

    private static func unavailableState(observedAt: Date, summary: String) -> QuotaWindowState {
        QuotaWindowState(
            tool: .codex,
            source: .codexLocalAppServer,
            confidence: .unknown,
            classification: .quotaUnavailable,
            observedAt: observedAt,
            summary: summary
        )
    }

    private static func isAppServerUnavailable(_ result: QuotaProbeResult) -> Bool {
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.lowercased()
        if stdout.isEmpty, result.exitCode == 0 {
            return true
        }
        return stderr.contains("failed to connect to socket")
            || stderr.contains("standalone codex install not found")
            || stderr.contains("no such file or directory")
    }

    private static func unavailableSummary(_ result: QuotaProbeResult) -> String {
        let stderr = result.stderr
        if isStandaloneInstallMissing(result) {
            return "Codex local quota is unavailable because the standalone Codex app-server install is missing."
        }
        if stderr.localizedCaseInsensitiveContains("No such file or directory") {
            return "Codex local quota is unavailable because the app-server executable could not start."
        }
        return "Codex local quota is unavailable from this CLI install."
    }

    private static func isStandaloneInstallMissing(_ result: QuotaProbeResult) -> Bool {
        result.stderr.localizedCaseInsensitiveContains("standalone Codex install not found")
            || result.stderr.localizedCaseInsensitiveContains("managed standalone Codex install not found")
    }

    private static func firstJSONObject(in text: String) -> [String: Any]? {
        let objects: [[String: Any]] = text.split(whereSeparator: \.isNewline).compactMap { line -> [String: Any]? in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["result"] != nil || object["error"] != nil else {
                return nil
            }
            return object
        }
        return objects.first(where: isQuotaResponse) ?? objects.first
    }

    private static func isQuotaResponse(_ object: [String: Any]) -> Bool {
        if let id = object["id"] as? Int, id == 2 {
            return true
        }
        if object["error"] != nil {
            return true
        }
        guard let result = object["result"] as? [String: Any] else {
            return false
        }
        return result["rateLimits"] != nil
            || result["rateLimitsByLimitId"] != nil
            || result["primaryWindow"] != nil
            || result["primary_window"] != nil
            || result["fiveHour"] != nil
            || result["five_hour"] != nil
    }

    private static func windowFields(in object: [String: Any]) -> [String: Any]? {
        if let byLimitID = object["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byLimitID["codex"] as? [String: Any],
               let window = rateLimitWindow(in: codex) {
                return window
            }
            for value in byLimitID.values {
                if let snapshot = value as? [String: Any],
                   let window = rateLimitWindow(in: snapshot) {
                    return window
                }
            }
        }
        if let snapshot = object["rateLimits"] as? [String: Any],
           let window = rateLimitWindow(in: snapshot) {
            return window
        }
        for key in ["primaryWindow", "primary_window", "fiveHour", "five_hour", "window"] {
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return object
    }

    private static func rateLimitWindow(in snapshot: [String: Any]) -> [String: Any]? {
        if let primary = snapshot["primary"] as? [String: Any] {
            return primary
        }
        if let window = snapshot["window"] as? [String: Any] {
            return window
        }
        if snapshot["usedPercent"] != nil || snapshot["resetsAt"] != nil || snapshot["resetAt"] != nil {
            return snapshot
        }
        return nil
    }

    // The Codex app-server reports a secondary (weekly) rate-limit window
    // alongside the primary 5h window. Surface it for the weekly quota readout.
    private static func secondaryWindowFields(in object: [String: Any]) -> [String: Any]? {
        if let byLimitID = object["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byLimitID["codex"] as? [String: Any],
               let secondary = secondaryWindow(in: codex) {
                return secondary
            }
            for value in byLimitID.values {
                if let snapshot = value as? [String: Any],
                   let secondary = secondaryWindow(in: snapshot) {
                    return secondary
                }
            }
        }
        if let snapshot = object["rateLimits"] as? [String: Any],
           let secondary = secondaryWindow(in: snapshot) {
            return secondary
        }
        for key in ["secondaryWindow", "secondary_window", "weekly", "sevenDay", "seven_day"] {
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func secondaryWindow(in snapshot: [String: Any]) -> [String: Any]? {
        snapshot["secondary"] as? [String: Any]
    }

    private static func dateValue(in object: [String: Any], keys: [String]) -> Date? {
        keys.compactMap { key in
            if let value = object[key] as? String {
                if let date = QuotaWindowParser.isoDate(value) {
                    return date
                }
                if let epoch = Double(value) {
                    return dateFromEpoch(epoch)
                }
            }
            if let value = object[key] as? Double {
                return dateFromEpoch(value)
            }
            if let value = object[key] as? Int {
                return dateFromEpoch(Double(value))
            }
            return nil
        }.first
    }

    private static func doubleValue(in object: [String: Any], keys: [String]) -> Double? {
        keys.compactMap { key in
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? String { return Double(value) }
            return nil
        }.first
    }

    private static func remainingPercent(in object: [String: Any]) -> Double? {
        if let explicit = doubleValue(in: object, keys: ["remainingPercent", "remaining_percent"]) {
            return explicit
        }
        guard let used = doubleValue(in: object, keys: ["usedPercent", "used_percent", "percentUsed", "usagePercent"]) else {
            return nil
        }
        return 100 - min(max(used, 0), 100)
    }

    private static func windowLabel(in object: [String: Any]) -> String? {
        if let explicit = stringValue(in: object, keys: ["window", "windowLabel", "label"]) {
            return explicit
        }
        guard let minutes = doubleValue(in: object, keys: ["windowDurationMins", "window_duration_mins"]) else {
            return nil
        }
        if minutes == 300 {
            return "5h"
        }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(minutes / 60))h"
        }
        return "\(Int(minutes))m"
    }

    private static func dateFromEpoch(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        keys.compactMap { object[$0] as? String }.first
    }
}

private final class CodexAppServerLineCollector {
    let pipe = Pipe()
    let initializeObserved = DispatchSemaphore(value: 0)
    let rateLimitsObserved = DispatchSemaphore(value: 0)

    private let limitBytes: Int
    private let lock = NSLock()
    private var buffer = ""
    private var lines: [String] = []
    private var byteCount = 0
    private var processExited = false
    private var observedInitialize = false
    private var observedRateLimits = false

    init(limitBytes: Int) {
        self.limitBytes = limitBytes
    }

    var didObserveInitialize: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedInitialize
    }

    var didObserveRateLimits: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedRateLimits
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData)
        }
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        append(pipe.fileHandleForReading.availableData)
    }

    func markProcessExited() {
        lock.lock()
        processExited = true
        lock.unlock()
        initializeObserved.signal()
        rateLimitsObserved.signal()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        var allLines = lines
        let tail = buffer.trimmingCharacters(in: .newlines)
        if !tail.isEmpty {
            allLines.append(tail)
        }
        return allLines.isEmpty ? "" : allLines.joined(separator: "\n") + "\n"
    }

    private func append(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return
        }

        var signalInitialize = false
        var signalRateLimits = false
        lock.lock()
        defer {
            lock.unlock()
            if signalInitialize { initializeObserved.signal() }
            if signalRateLimits { rateLimitsObserved.signal() }
        }

        let remaining = max(0, limitBytes - byteCount)
        guard remaining > 0 else {
            return
        }
        let limited = String(text.prefix(remaining))
        byteCount += Data(limited.utf8).count
        buffer += limited

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            lines.append(line)
            if let id = Self.messageID(in: line) {
                if id == 1, !observedInitialize {
                    observedInitialize = true
                    signalInitialize = true
                }
                if id == 2, !observedRateLimits {
                    observedRateLimits = true
                    signalRateLimits = true
                }
            }
        }

        if processExited {
            signalInitialize = true
            signalRateLimits = true
        }
    }

    private static func messageID(in line: String) -> Int? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["id"] as? Int
    }
}

