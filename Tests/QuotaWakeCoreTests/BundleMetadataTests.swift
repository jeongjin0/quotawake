import XCTest
@testable import QuotaWakeCore

final class BundleMetadataTests: XCTestCase {
    func testValidMetadataPassesValidation() throws {
        let metadata = BundleMetadata(
            bundleIdentifier: "com.jeongjin.quotawake.menubar",
            minimumSystemVersion: "13.0",
            bundleName: "QuotaWake",
            executableName: "QuotaWake",
            isAgentApplication: true
        )

        XCTAssertNoThrow(try metadata.validate())
    }

    func testInvalidBundleIdentifierIsRejected() {
        let metadata = BundleMetadata(
            bundleIdentifier: "quotawake",
            minimumSystemVersion: "13.0",
            bundleName: "QuotaWake",
            executableName: "QuotaWake",
            isAgentApplication: true
        )

        XCTAssertThrowsError(try metadata.validate()) { error in
            XCTAssertEqual(error as? BundleMetadata.ValidationError, .invalidBundleIdentifier)
        }
    }

    func testMinimumSystemVersionBelowThirteenIsRejected() {
        let metadata = BundleMetadata(
            bundleIdentifier: "com.jeongjin.quotawake.menubar",
            minimumSystemVersion: "12.6",
            bundleName: "QuotaWake",
            executableName: "QuotaWake",
            isAgentApplication: true
        )

        XCTAssertThrowsError(try metadata.validate()) { error in
            XCTAssertEqual(error as? BundleMetadata.ValidationError, .unsupportedMinimumSystemVersion)
        }
    }

    func testEmptyBundleNameIsRejected() {
        let metadata = BundleMetadata(
            bundleIdentifier: "com.jeongjin.quotawake.menubar",
            minimumSystemVersion: "13.0",
            bundleName: "  ",
            executableName: "QuotaWake",
            isAgentApplication: true
        )

        XCTAssertThrowsError(try metadata.validate()) { error in
            XCTAssertEqual(error as? BundleMetadata.ValidationError, .emptyBundleName)
        }
    }

    func testAgentApplicationFlagMustBeTrue() {
        let metadata = BundleMetadata(
            bundleIdentifier: "com.jeongjin.quotawake.menubar",
            minimumSystemVersion: "13.0",
            bundleName: "QuotaWake",
            executableName: "QuotaWake",
            isAgentApplication: false
        )

        XCTAssertThrowsError(try metadata.validate()) { error in
            XCTAssertEqual(error as? BundleMetadata.ValidationError, .agentApplicationRequired)
        }
    }
}
