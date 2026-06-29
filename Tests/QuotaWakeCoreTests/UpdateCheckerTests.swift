import XCTest
@testable import QuotaWakeCore

final class UpdateCheckerTests: XCTestCase {
    func testSemVerParseCompareAndTagStripping() throws {
        XCTAssertLessThan(try SemVer("0.0.9"), try SemVer("0.1.0"))
        XCTAssertLessThan(try SemVer("1.2.3"), try SemVer("1.2.4"))
        XCTAssertEqual(try SemVer.tag("v1.2.3"), try SemVer("1.2.3"))
        XCTAssertEqual(try SemVer.tag("V1.2.3"), try SemVer("1.2.3"))
        XCTAssertThrowsError(try SemVer("1.2"))
        XCTAssertThrowsError(try SemVer("01.2.3"))
    }

    func testNewerReleaseUsesDMGAssetURL() throws {
        let result = try checker(current: "0.0.0", data: fixture("latest-newer")).check()
        guard case let .available(info) = result else {
            return XCTFail("Expected available update")
        }
        XCTAssertEqual(info.version, try SemVer("0.1.0"))
        XCTAssertEqual(info.preferredOpenURL.absoluteString, "https://github.com/jeongjin0/quotawake/releases/download/v0.1.0/QuotaWake-0.1.0.dmg")
    }

    func testMissingDMGAssetFallsBackToReleaseURL() throws {
        let json = """
        {"tag_name":"v0.1.0","html_url":"https://example.com/release","assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"}]}
        """
        let result = try checker(current: "0.0.0", data: Data(json.utf8)).check()
        guard case let .available(info) = result else {
            return XCTFail("Expected available update")
        }
        XCTAssertEqual(info.downloadURL, nil)
        XCTAssertEqual(info.preferredOpenURL.absoluteString, "https://example.com/release")
    }

    func testEqualAndOlderVersionsAreUpToDate() throws {
        let equal = try checker(current: "0.1.0", data: fixture("latest-newer")).check()
        XCTAssertEqual(equal, .upToDate(current: try SemVer("0.1.0"), latest: try SemVer("0.1.0")))

        let older = try checker(current: "0.2.0", data: fixture("latest-newer")).check()
        XCTAssertEqual(older, .upToDate(current: try SemVer("0.2.0"), latest: try SemVer("0.1.0")))
    }

    func testMalformedJSONInvalidTagNetworkFailureAndEmptyEndpoint() throws {
        XCTAssertThrowsError(try checker(current: "0.0.0", data: Data("{".utf8)).check()) { error in
            XCTAssertEqual(error as? UpdateCheckerError, .malformedRelease)
        }
        XCTAssertThrowsError(try checker(current: "0.0.0", data: fixture("latest-malformed")).check()) { error in
            XCTAssertEqual(error as? UpdateCheckerError, .invalidVersion("not-semver"))
        }
        XCTAssertThrowsError(try UpdateChecker(currentVersion: "0.0.0", endpoint: "", fetchReleaseData: { _ in Data() })) { error in
            XCTAssertEqual(error as? UpdateCheckerError, .emptyEndpoint)
        }
        let throwingChecker = try UpdateChecker(currentVersion: "0.0.0", endpoint: "https://example.com") { _ in
            throw UpdateCheckerError.transport("offline")
        }
        XCTAssertThrowsError(try throwingChecker.check()) { error in
            XCTAssertEqual(error as? UpdateCheckerError, .transport("offline"))
        }
    }

    private func checker(current: String, data: Data) throws -> UpdateChecker {
        try UpdateChecker(currentVersion: current, endpoint: "https://example.com/releases/latest") { _ in
            data
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/releases/\(name).json")
        return try Data(contentsOf: url)
    }
}
