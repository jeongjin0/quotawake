import XCTest

/// The UI QA scenario list exists in two places that must never drift:
/// `UIQAConfig.validScenarios` in `Sources/QuotaWake/DebugUIQA.swift` and the
/// `valid_scenario()` case pattern in `Scripts/ui_qa.sh`. The shell list adds
/// exactly two script-side entries: `full` (scenario chaining) and
/// `normal-launch` (driven through environment variables, not `--ui-qa`).
final class UIQAScenarioSyncTests: XCTestCase {
    private static let shellOnlyScenarios: Set<String> = ["full", "normal-launch"]

    func testShellScenarioListMatchesUIQAConfigValidScenarios() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: rootURL.appendingPathComponent("Scripts/ui_qa.sh", isDirectory: false),
            encoding: .utf8
        )
        let swiftSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/QuotaWake/DebugUIQA.swift", isDirectory: false),
            encoding: .utf8
        )

        guard let functionStart = script.range(of: "valid_scenario() {"),
              let functionEnd = script.range(of: "\n}", range: functionStart.upperBound..<script.endIndex) else {
            return XCTFail("valid_scenario() not found in ui_qa.sh")
        }
        let functionBody = script[functionStart.upperBound..<functionEnd.lowerBound]
        guard let patternLine = functionBody
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasSuffix(")") && $0.contains("|") }) else {
            return XCTFail("scenario case pattern not found in valid_scenario()")
        }
        let shellScenarios = Set(patternLine.dropLast().split(separator: "|").map(String.init))

        guard let listStart = swiftSource.range(of: "validScenarios: Set<String> = ["),
              let listEnd = swiftSource.range(of: "]", range: listStart.upperBound..<swiftSource.endIndex) else {
            return XCTFail("validScenarios literal not found in DebugUIQA.swift")
        }
        let swiftScenarios = Set(
            swiftSource[listStart.upperBound..<listEnd.lowerBound]
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\",")) }
                .filter { !$0.isEmpty }
        )

        XCTAssertFalse(shellScenarios.isEmpty)
        XCTAssertFalse(swiftScenarios.isEmpty)
        let expectedShellScenarios = swiftScenarios.union(Self.shellOnlyScenarios)
        XCTAssertEqual(
            shellScenarios, expectedShellScenarios,
            """
            ui_qa.sh valid_scenario() and UIQAConfig.validScenarios have drifted. \
            Missing from script: \(expectedShellScenarios.subtracting(shellScenarios).sorted()). \
            Missing from Swift: \(shellScenarios.subtracting(expectedShellScenarios).sorted()).
            """
        )
    }
}
