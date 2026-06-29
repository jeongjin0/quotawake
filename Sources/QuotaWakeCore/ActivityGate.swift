import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct ActivityGate: Sendable {
    private let configuration: ActivityGateConfiguration
    private let idleReader: ActivityIdleReading
    private let powerStateProbe: ActivityPowerStateProbing

    public init(
        configuration: ActivityGateConfiguration = .default,
        idleReader: ActivityIdleReading = CoreGraphicsActivityIdleReader(),
        powerStateProbe: ActivityPowerStateProbing = IoregActivityPowerStateProbe()
    ) {
        self.configuration = configuration
        self.idleReader = idleReader
        self.powerStateProbe = powerStateProbe
    }

    public func evaluate() -> ActivityGateResult {
        if let reason = ActivityPowerStateParser.suppressionReason(from: powerStateProbe.sample()) {
            return .suppressedPowerState(reason: reason)
        }

        guard let idleSeconds = idleReader.secondsSinceLastInput(),
              idleSeconds.isFinite,
              idleSeconds >= 0 else {
            switch configuration.unavailablePolicy {
            case .failOpen:
                return .active
            case .failClosed:
                return .activityUnavailable
            }
        }

        if idleSeconds >= configuration.idleThresholdSeconds {
            return .idle(seconds: idleSeconds)
        }
        return .active
    }
}

public struct ActivityGateConfiguration: Equatable, Sendable {
    public static let `default` = ActivityGateConfiguration(
        idleThresholdSeconds: 300,
        unavailablePolicy: .failClosed
    )

    public let idleThresholdSeconds: TimeInterval
    public let unavailablePolicy: ActivityUnavailablePolicy

    public init(
        idleThresholdSeconds: TimeInterval,
        unavailablePolicy: ActivityUnavailablePolicy
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.unavailablePolicy = unavailablePolicy
    }
}

public enum ActivityUnavailablePolicy: Equatable, Sendable {
    case failOpen
    case failClosed
}

public enum ActivityGateResult: Equatable, Sendable {
    case active
    case idle(seconds: TimeInterval)
    case activityUnavailable
    case suppressedPowerState(reason: ActivityPowerStateSuppressionReason)
}

public enum ActivityPowerStateSuppressionReason: String, Equatable, Sendable {
    case darkWake
    case maintenanceWake
    case sleepServiceWake
    case clamshellSleep
}

public protocol ActivityIdleReading: Sendable {
    func secondsSinceLastInput() -> TimeInterval?
}

public struct CoreGraphicsActivityIdleReader: ActivityIdleReading {
    public init() {}

    public func secondsSinceLastInput() -> TimeInterval? {
        #if canImport(CoreGraphics)
        guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else {
            return nil
        }
        let seconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: anyInputEvent
        )
        guard seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return seconds
        #else
        return nil
        #endif
    }
}

public protocol ActivityPowerStateProbing: Sendable {
    func sample() -> ActivityPowerStateCommandResult
}

public enum ActivityPowerStateCommandResult: Equatable, Sendable {
    case completed(exitCode: Int32, stdout: String)
    case failed(String)
    case timedOut
    case unavailable
}

public struct IoregActivityPowerStateProbe: ActivityPowerStateProbing {
    private let runner: ActivityPowerStateCommandRunning
    private let timeoutSeconds: TimeInterval

    public init(
        runner: ActivityPowerStateCommandRunning = ProcessActivityPowerStateCommandRunner(),
        timeoutSeconds: TimeInterval = 2
    ) {
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
    }

    public func sample() -> ActivityPowerStateCommandResult {
        #if os(macOS)
        return runner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/ioreg"),
            arguments: ["-r", "-n", "IOPMrootDomain", "-d", "1"],
            timeoutSeconds: timeoutSeconds
        )
        #else
        return .unavailable
        #endif
    }
}

public protocol ActivityPowerStateCommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> ActivityPowerStateCommandResult
}

public struct ProcessActivityPowerStateCommandRunner: ActivityPowerStateCommandRunning {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> ActivityPowerStateCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return .failed(String(describing: type(of: error)))
        }

        let timeout = DispatchTime.now() + timeoutSeconds
        guard finished.wait(timeout: timeout) == .success else {
            process.terminate()
            if process.isRunning {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            return .timedOut
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return .completed(exitCode: process.terminationStatus, stdout: stdout)
    }
}

enum ActivityPowerStateParser {
    static func suppressionReason(from commandResult: ActivityPowerStateCommandResult) -> ActivityPowerStateSuppressionReason? {
        guard case let .completed(exitCode, stdout) = commandResult,
              exitCode == 0 else {
            return nil
        }
        return suppressionReason(fromIoregOutput: stdout)
    }

    static func suppressionReason(fromIoregOutput output: String) -> ActivityPowerStateSuppressionReason? {
        let values = parseRootDomainValues(output)
        let wakeType = normalized(
            values["Wake Type"]
                ?? values["WakeType"]
                ?? values["IOPMRootDomainWakeType"]
        )

        switch wakeType {
        case "dark", "darkwake":
            return .darkWake
        case "maintenance", "maintenancewake":
            return .maintenanceWake
        case "sleepservice", "sleepservicewake":
            return .sleepServiceWake
        default:
            break
        }

        let clamshellClosed = isTruthy(values["AppleClamshellState"])
        let clamshellCausesSleep = isTruthy(values["AppleClamshellCausesSleep"])
        if clamshellClosed && clamshellCausesSleep {
            return .clamshellSleep
        }

        return nil
    }

    private static func parseRootDomainValues(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let firstQuote = line.firstIndex(of: "\""),
                  let equals = line[firstQuote...].firstIndex(of: "=") else {
                continue
            }

            let keyPart = line[firstQuote..<equals]
            let valuePart = line[line.index(after: equals)...]
            let key = keyPart.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
            let value = valuePart.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }
        return value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .lowercased()
    }

    private static func isTruthy(_ value: String?) -> Bool {
        switch normalized(value) {
        case "yes", "true", "1":
            return true
        default:
            return false
        }
    }
}
