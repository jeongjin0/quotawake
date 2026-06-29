import XCTest
@testable import QuotaWakeCore

final class QuotaSourceLicenseTests: XCTestCase {
    func testLicenseSourceReviewRecordsReferenceAndAttributionDecision() throws {
        let reviewURL = URL(fileURLWithPath: "../.omo/evidence/quotawake-phase4-reset-aware-readiness/task-2/license-source-review.md")
        let review = try String(contentsOf: reviewURL)

        XCTAssertTrue(review.contains("CodexBar"))
        XCTAssertTrue(review.contains("MIT"))
        XCTAssertTrue(review.contains("reference-only"))
        XCTAssertTrue(review.contains("No CodexBar source was copied"))
        XCTAssertTrue(review.contains("Claude Code Usage Monitor"))
        XCTAssertTrue(review.contains("Current repository and LICENSE page presented MIT"))
        XCTAssertTrue(review.contains("reference-only adjacency check"))
    }
}
