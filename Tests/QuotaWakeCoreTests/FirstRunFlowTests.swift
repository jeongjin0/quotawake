import XCTest
@testable import QuotaWakeCore

final class FirstRunFlowTests: XCTestCase {
    func testHappyPathCompletesOnlyAfterToolSetupReadinessAndTestRun() throws {
        var flow = FirstRunFlow()
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertFalse(FirstRunStep.allCases.map(\.title).contains("Schedule"))
        XCTAssertFalse(FirstRunStep.allCases.map(\.title).contains("Wake Helper"))

        XCTAssertEqual(flow.advance(), .advanced(.detectTools))
        XCTAssertEqual(flow.advance(), .advanced(.windowReadiness))

        flow.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(flow.advance(), .advanced(.testRun))
        XCTAssertEqual(flow.advance(), .blocked(.testRunNotAcknowledged))

        flow.markTestRunCompleted()
        guard case let .completed(settings) = flow.advance() else {
            return XCTFail("Expected completed settings")
        }
        XCTAssertTrue(settings.firstRunCompleted)
        XCTAssertTrue(settings.background.launchAtLoginEnabled)
    }

    func testSkipTestRequiresExplicitAcknowledgmentWithoutWakeSetup() throws {
        var flow = flowReadyForTestRun()
        XCTAssertEqual(flow.step, .testRun)
        XCTAssertEqual(flow.advance(), .blocked(.testRunNotAcknowledged))

        flow.acknowledgeTestRunSkip()
        guard case let .completed(settings) = flow.advance() else {
            return XCTFail("Expected completed settings after skip acknowledgment")
        }
        XCTAssertTrue(settings.firstRunCompleted)
    }

    func testFailedCliDetectionAndNoTestAcknowledgmentRemainBlocked() throws {
        var settings = AppSettings.default
        settings.firstRunCompleted = false
        settings.tools.codex.manualPath = "/missing/codex"
        let commands = [
            command(tool: .claude, status: .missing, path: nil),
            command(tool: .codex, status: .manualPathInvalid, path: settings.tools.codex.manualPath)
        ]
        let uiState = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: [],
            resolvedCommands: commands,
            appVersion: "0.0.0"
        )
        XCTAssertEqual(uiState.toolStates.first { $0.tool == .claude }?.statusText, "Choose path")
        XCTAssertEqual(uiState.toolStates.first { $0.tool == .codex }?.statusText, "Manual path invalid")

        var flow = FirstRunFlow(settings: settings)
        flow.step = .testRun
        XCTAssertEqual(flow.completionBlockReason, .testRunNotAcknowledged)
        XCTAssertEqual(flow.advance(), .blocked(.testRunNotAcknowledged))
        flow.acknowledgeTestRunSkip()
        XCTAssertEqual(flow.advance(), .completed(flow.settings))
    }

    private func flowReadyForTestRun() -> FirstRunFlow {
        var flow = FirstRunFlow()
        _ = flow.advance()
        _ = flow.advance()
        _ = flow.advance()
        XCTAssertEqual(flow.step, .testRun)
        return flow
    }

    private func command(tool: ToolKind, status: CLIResolutionStatus, path: String?) -> ResolvedToolCommand {
        ResolvedToolCommand(
            tool: tool,
            executableURL: path.map { URL(fileURLWithPath: $0) },
            status: status,
            childPATH: "/usr/local/bin:/usr/bin:/bin",
            searchedDirectories: []
        )
    }
}
