import XCTest
@testable import QuotaWakeCore

/// The API-billing guard keys exist in two places that must never drift:
/// `CLIChildEnvironmentPolicy.apiBillingEnvironmentKeys` (scrubbed from every
/// child CLI environment) and the `GUARD_KEYS` array in
/// `Scripts/live_cli_smoke.sh` (fails the release smoke closed when present).
final class BillingGuardKeySyncTests: XCTestCase {
    func testLiveSmokeGuardKeysMatchChildEnvironmentPolicy() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/live_cli_smoke.sh", isDirectory: false)
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        guard let arrayStart = script.range(of: "GUARD_KEYS=("),
              let arrayEnd = script.range(of: ")", range: arrayStart.upperBound..<script.endIndex) else {
            return XCTFail("GUARD_KEYS array not found in live_cli_smoke.sh")
        }
        let body = script[arrayStart.upperBound..<arrayEnd.lowerBound]
        let scriptKeys = Set(
            body.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                .filter { !$0.isEmpty }
        )

        let policyKeys = CLIChildEnvironmentPolicy.apiBillingEnvironmentKeys

        XCTAssertFalse(scriptKeys.isEmpty)
        XCTAssertEqual(
            scriptKeys, policyKeys,
            """
            live_cli_smoke.sh GUARD_KEYS and \
            CLIChildEnvironmentPolicy.apiBillingEnvironmentKeys have drifted. \
            Missing from script: \(policyKeys.subtracting(scriptKeys).sorted()). \
            Missing from policy: \(scriptKeys.subtracting(policyKeys).sorted()).
            """
        )
    }
}
