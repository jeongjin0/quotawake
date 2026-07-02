import XCTest
@testable import QuotaWakeCore

final class QuotaSourceLicenseTests: XCTestCase {
    // Guard the shipped CodexBar attribution (see RELEASE.md third-party notices
    // requirement) using the in-repo notice file, not machine-local evidence paths.
    func testThirdPartyNoticesRecordCodexBarAttribution() throws {
        let noticesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/THIRD_PARTY_NOTICES.md", isDirectory: false)
        let notices = try String(contentsOf: noticesURL, encoding: .utf8)

        XCTAssertTrue(notices.contains("CodexBar"))
        XCTAssertTrue(notices.contains("MIT License"))
        XCTAssertTrue(notices.contains("https://github.com/steipete/CodexBar"))
        XCTAssertTrue(notices.contains("Peter Steinberger"))
        XCTAssertTrue(notices.contains("ProviderIcon-claude.svg"))
        XCTAssertTrue(notices.contains("ProviderIcon-codex.svg"))
    }
}
