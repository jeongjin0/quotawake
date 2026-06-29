import XCTest
@testable import QuotaWakeCore

final class LaunchAtLoginManagerTests: XCTestCase {
    func testEnableRegistersOnceAndDisableUnregistersOnce() throws {
        var status = LaunchAtLoginStatus.notRegistered
        var registerCount = 0
        var unregisterCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { status },
            registerAction: {
                registerCount += 1
                status = .enabled
            },
            unregisterAction: {
                unregisterCount += 1
                status = .notRegistered
            }
        )

        XCTAssertEqual(try manager.currentStatus(), .notRegistered)
        XCTAssertEqual(try manager.enable(), .enabled)
        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(unregisterCount, 0)

        XCTAssertEqual(try manager.enable(), .enabled)
        XCTAssertEqual(registerCount, 1)

        XCTAssertEqual(try manager.disable(), .notRegistered)
        XCTAssertEqual(unregisterCount, 1)

        XCTAssertEqual(try manager.disable(), .notRegistered)
        XCTAssertEqual(unregisterCount, 1)
    }

    func testRequiresApprovalNotFoundAndUnknownStatesArePreservedForUI() throws {
        var actions = 0

        for status in [LaunchAtLoginStatus.requiresApproval, .notFound, .unknown] {
            let manager = LaunchAtLoginManager(
                statusProvider: { status },
                registerAction: { actions += 1 },
                unregisterAction: { actions += 1 }
            )

            XCTAssertEqual(try manager.currentStatus(), status)
            XCTAssertEqual(try manager.enable(), status)
        }

        XCTAssertEqual(actions, 0)
    }

    func testRequiresApprovalCanBeDisabledToClearPendingRegistration() throws {
        var status = LaunchAtLoginStatus.requiresApproval
        var unregisterCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { status },
            registerAction: {
                XCTFail("Enabling while requiresApproval should not re-register")
            },
            unregisterAction: {
                unregisterCount += 1
                status = .notRegistered
            }
        )

        XCTAssertEqual(try manager.disable(), .notRegistered)
        XCTAssertEqual(unregisterCount, 1)
    }

    func testRegisterAndUnregisterErrorsAreSurfaced() {
        let registerFailure = LaunchAtLoginManager(
            statusProvider: { .notRegistered },
            registerAction: { throw TestError.registerFailed },
            unregisterAction: {}
        )
        XCTAssertThrowsError(try registerFailure.enable()) { error in
            XCTAssertEqual(error as? TestError, .registerFailed)
        }

        let unregisterFailure = LaunchAtLoginManager(
            statusProvider: { .enabled },
            registerAction: {},
            unregisterAction: { throw TestError.unregisterFailed }
        )
        XCTAssertThrowsError(try unregisterFailure.disable()) { error in
            XCTAssertEqual(error as? TestError, .unregisterFailed)
        }
    }

    func testNotFoundAndUnknownDoNotInvokeActionsWhenDisabling() throws {
        var actions = 0

        for status in [LaunchAtLoginStatus.notFound, .unknown] {
            let manager = LaunchAtLoginManager(
                statusProvider: { status },
                registerAction: { actions += 1 },
                unregisterAction: { actions += 1 }
            )
            XCTAssertEqual(try manager.disable(), status)
        }

        XCTAssertEqual(actions, 0)
    }

    private enum TestError: Error, Equatable {
        case registerFailed
        case unregisterFailed
    }
}
