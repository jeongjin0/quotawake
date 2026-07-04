import Foundation

public enum FirstRunStep: String, CaseIterable, Equatable, Sendable {
    case welcome
    case detectTools
    case windowReadiness
    case testRun
    case complete

    public var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .detectTools:
            return "Detect Providers"
        case .windowReadiness:
            return "Window Readiness"
        case .testRun:
            return "Test Run"
        case .complete:
            return "Complete"
        }
    }
}

public enum FirstRunBlockReason: Equatable, Sendable {
    case testRunNotAcknowledged

    public var message: String {
        switch self {
        case .testRunNotAcknowledged:
            return "Run the test or acknowledge skipping it."
        }
    }
}

public enum FirstRunTransition: Equatable, Sendable {
    case advanced(FirstRunStep)
    case blocked(FirstRunBlockReason)
    case completed(AppSettings)
}

public struct FirstRunFlow: Equatable, Sendable {
    public var step: FirstRunStep
    public var settings: AppSettings
    public var testRunCompleted: Bool
    public var testRunSkippedAcknowledged: Bool

    public init(settings: AppSettings = .default) {
        self.step = settings.firstRunCompleted ? .complete : .welcome
        self.settings = settings
        self.testRunCompleted = false
        self.testRunSkippedAcknowledged = false
    }

    public var canMoveBack: Bool {
        guard let index = Self.setupSteps.firstIndex(of: step) else {
            return false
        }
        return index > 0
    }

    public var completionBlockReason: FirstRunBlockReason? {
        if !testRunCompleted && !testRunSkippedAcknowledged {
            return .testRunNotAcknowledged
        }
        return nil
    }

    public mutating func advance() -> FirstRunTransition {
        switch step {
        case .welcome:
            step = .detectTools
            return .advanced(step)
        case .detectTools:
            step = .windowReadiness
            return .advanced(step)
        case .windowReadiness:
            step = .testRun
            return .advanced(step)
        case .testRun:
            if let reason = completionBlockReason {
                return .blocked(reason)
            }
            settings.firstRunCompleted = true
            step = .complete
            return .completed(settings)
        case .complete:
            return .completed(settings)
        }
    }

    public mutating func moveBack() {
        guard let index = Self.setupSteps.firstIndex(of: step), index > 0 else {
            return
        }
        step = Self.setupSteps[index - 1]
    }

    public mutating func setLaunchAtLoginEnabled(_ enabled: Bool) {
        settings.background.launchAtLoginEnabled = enabled
    }

    public mutating func markTestRunCompleted() {
        testRunCompleted = true
        testRunSkippedAcknowledged = false
    }

    public mutating func acknowledgeTestRunSkip() {
        testRunSkippedAcknowledged = true
        testRunCompleted = false
    }

    private static let setupSteps: [FirstRunStep] = [
        .welcome,
        .detectTools,
        .windowReadiness,
        .testRun
    ]
}
