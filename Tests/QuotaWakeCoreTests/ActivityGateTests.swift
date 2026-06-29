import XCTest
@testable import QuotaWakeCore

final class ActivityGateTests: XCTestCase {
    func testReportsActiveWhenIdleBelowThresholdAndPowerStateAllowsCapture() {
        let gate = ActivityGate(
            configuration: ActivityGateConfiguration(
                idleThresholdSeconds: 300,
                unavailablePolicy: .failClosed
            ),
            idleReader: FakeIdleReader(seconds: 299),
            powerStateProbe: FakePowerStateProbe(output: Self.activePowerOutput)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .active)
    }

    func testReportsIdleWhenIdleEqualsThreshold() {
        let gate = ActivityGate(
            configuration: ActivityGateConfiguration(
                idleThresholdSeconds: 300,
                unavailablePolicy: .failClosed
            ),
            idleReader: FakeIdleReader(seconds: 300),
            powerStateProbe: FakePowerStateProbe(output: Self.activePowerOutput)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .idle(seconds: 300))
    }

    func testReportsIdleWhenIdleExceedsThreshold() {
        let gate = ActivityGate(
            configuration: ActivityGateConfiguration(
                idleThresholdSeconds: 300,
                unavailablePolicy: .failClosed
            ),
            idleReader: FakeIdleReader(seconds: 301.5),
            powerStateProbe: FakePowerStateProbe(output: Self.activePowerOutput)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .idle(seconds: 301.5))
    }

    func testIdleUnavailableFailsOpenWhenConfigured() {
        let gate = ActivityGate(
            configuration: ActivityGateConfiguration(
                idleThresholdSeconds: 300,
                unavailablePolicy: .failOpen
            ),
            idleReader: FakeIdleReader(seconds: nil),
            powerStateProbe: FakePowerStateProbe(output: Self.activePowerOutput)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .active)
    }

    func testIdleUnavailableFailsClosedWhenConfigured() {
        let gate = ActivityGate(
            configuration: ActivityGateConfiguration(
                idleThresholdSeconds: 300,
                unavailablePolicy: .failClosed
            ),
            idleReader: FakeIdleReader(seconds: nil),
            powerStateProbe: FakePowerStateProbe(output: Self.activePowerOutput)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .activityUnavailable)
    }

    func testSuppressesDarkWakePowerState() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 0),
            powerStateProbe: FakePowerStateProbe(output: Self.powerOutput(wakeType: "DarkWake"))
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .suppressedPowerState(reason: .darkWake))
    }

    func testSuppressesMaintenanceWakePowerState() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 0),
            powerStateProbe: FakePowerStateProbe(output: Self.powerOutput(wakeType: "MaintenanceWake"))
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .suppressedPowerState(reason: .maintenanceWake))
    }

    func testSuppressesSleepServiceWakePowerState() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 0),
            powerStateProbe: FakePowerStateProbe(output: Self.powerOutput(wakeType: "SleepService"))
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .suppressedPowerState(reason: .sleepServiceWake))
    }

    func testSuppressesClamshellSleepState() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 0),
            powerStateProbe: FakePowerStateProbe(output: """
            +-o IOPMrootDomain
              | {
              |   "Wake Type" = "FullWake"
              |   "AppleClamshellState" = Yes
              |   "AppleClamshellCausesSleep" = Yes
              | }
            """)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .suppressedPowerState(reason: .clamshellSleep))
    }

    func testIoregTimeoutFailsOpenToIdleReaderDecision() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 12),
            powerStateProbe: FakePowerStateProbe(commandResult: .timedOut)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .active)
    }

    func testPowerStateUnavailableFailsOpenToIdleReaderDecision() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 12),
            powerStateProbe: FakePowerStateProbe(commandResult: .unavailable)
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .active)
    }

    func testMalformedIoregOutputFailsOpenToIdleReaderDecision() {
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 12),
            powerStateProbe: FakePowerStateProbe(output: "unexpected ioreg output")
        )

        let result = gate.evaluate()

        XCTAssertEqual(result, .active)
    }

    func testDarkWakeWouldSkipProviderExecution() {
        var providerWasExecuted = false
        let gate = ActivityGate(
            idleReader: FakeIdleReader(seconds: 0),
            powerStateProbe: FakePowerStateProbe(output: Self.powerOutput(wakeType: "DarkWake"))
        )

        let result = gate.evaluate()
        if case .active = result {
            providerWasExecuted = true
        }

        XCTAssertEqual(result, .suppressedPowerState(reason: .darkWake))
        XCTAssertFalse(providerWasExecuted)
    }

    private static let activePowerOutput = powerOutput(wakeType: "FullWake")

    private static func powerOutput(wakeType: String) -> String {
        """
        +-o IOPMrootDomain
          | {
          |   "Wake Type" = "\(wakeType)"
          |   "AppleClamshellState" = No
          |   "AppleClamshellCausesSleep" = Yes
          | }
        """
    }
}

private struct FakeIdleReader: ActivityIdleReading {
    let seconds: TimeInterval?

    func secondsSinceLastInput() -> TimeInterval? {
        seconds
    }
}

private struct FakePowerStateProbe: ActivityPowerStateProbing {
    let commandResult: ActivityPowerStateCommandResult

    init(output: String) {
        commandResult = .completed(exitCode: 0, stdout: output)
    }

    init(commandResult: ActivityPowerStateCommandResult) {
        self.commandResult = commandResult
    }

    func sample() -> ActivityPowerStateCommandResult {
        commandResult
    }
}
