import Darwin
import XCTest
@testable import QuotaWakeCore

final class CLIPathDetectorTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testDetectsExecutableInHomebrewDirectoryAndBuildsChildPATH() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        try createExecutable(homebrew.appendingPathComponent("claude"))

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [homebrew])
        let result = detector.resolve(tool: .claude)

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, homebrew.appendingPathComponent("claude").path)
        XCTAssertEqual(result.childPATH.split(separator: ":").first.map(String.init), homebrew.path)
    }

    func testDetectsNewestNVMVersionBeforeOlderVersions() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let v18 = home.appendingPathComponent(".nvm/versions/node/v18.19.0/bin", isDirectory: true)
        let v20 = home.appendingPathComponent(".nvm/versions/node/v20.11.1/bin", isDirectory: true)
        try createExecutable(v18.appendingPathComponent("codex"))
        try createExecutable(v20.appendingPathComponent("codex"))

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [])
        let result = detector.resolve(tool: .codex)

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, v20.appendingPathComponent("codex").path)
        XCTAssertEqual(result.searchedDirectories.first?.path, v20.path)
    }

    func testBrokenCodexCandidateFallsBackToLaterHealthyCandidate() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let nvm = home.appendingPathComponent(".nvm/versions/node/v20.11.1/bin", isDirectory: true)
        let brokenCodex = homebrew.appendingPathComponent("codex")
        let validCodex = nvm.appendingPathComponent("codex")
        try createExecutable(brokenCodex, contents: "#!/bin/sh\nexit 127\n")
        try createExecutable(validCodex, contents: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex 1.0.0'; exit 0; fi\nexit 64\n")

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [homebrew])
        let result = detector.resolve(tool: .codex)

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, validCodex.path)
    }

    func testBrokenManualCodexPathReportsBrokenExecutable() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let manualCodex = root.appendingPathComponent("codex", isDirectory: false)
        try createExecutable(manualCodex, contents: "#!/bin/sh\nexit 127\n")

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [])
        let result = detector.resolve(tool: .codex, manualPath: manualCodex.path)

        XCTAssertEqual(result.status, .brokenExecutable)
        XCTAssertEqual(result.executableURL?.path, manualCodex.path)
    }

    func testCodexHealthProbeTimeoutIsBoundedAndFallsBack() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let nvm = home.appendingPathComponent(".nvm/versions/node/v20.11.1/bin", isDirectory: true)
        let hungCodex = homebrew.appendingPathComponent("codex")
        let validCodex = nvm.appendingPathComponent("codex")
        try createExecutable(hungCodex, contents: "#!/bin/sh\nwhile :; do :; done\n")
        try createExecutable(validCodex, contents: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex 1.0.0'; exit 0; fi\nexit 64\n")

        let detector = CLIPathDetector(
            homeDirectory: home,
            commonBinDirectories: [homebrew],
            codexHealthProbeTimeoutSeconds: 1
        )
        let startedAt = Date()
        let result = detector.resolve(tool: .codex)
        let duration = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(duration, 2.5)
        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, validCodex.path)
    }

    func testCodexHealthProbeTimeoutKillsSigtermResistantCandidate() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let nvm = home.appendingPathComponent(".nvm/versions/node/v20.11.1/bin", isDirectory: true)
        let pidFile = root.appendingPathComponent("sigterm-resistant-codex.pid", isDirectory: false)
        let hungCodex = homebrew.appendingPathComponent("codex")
        let validCodex = nvm.appendingPathComponent("codex")
        try createExecutable(
            hungCodex,
            contents: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo $$ > '\(pidFile.path)'; trap '' TERM; while :; do sleep 1; done; fi\nexit 64\n"
        )
        try createExecutable(validCodex, contents: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex 1.0.0'; exit 0; fi\nexit 64\n")

        let detector = CLIPathDetector(
            homeDirectory: home,
            commonBinDirectories: [homebrew, nvm],
            codexHealthProbeTimeoutSeconds: 1
        )
        let result = detector.resolve(tool: .codex)
        let leakedPID = try XCTUnwrap(waitForPID(in: pidFile, timeout: 1))
        defer {
            if isProcessRunning(leakedPID) {
                kill(leakedPID, SIGKILL)
            }
        }

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, validCodex.path)
        XCTAssertFalse(
            isProcessRunning(leakedPID),
            "SIGTERM-resistant fake codex process \(leakedPID) should not remain alive after timeout cleanup"
        )
    }

    func testCodexHealthProbeTimeoutKillsSpawnedChild() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let nvm = home.appendingPathComponent(".nvm/versions/node/v20.11.1/bin", isDirectory: true)
        let childPIDFile = root.appendingPathComponent("spawned-child.pid", isDirectory: false)
        let hungCodex = homebrew.appendingPathComponent("codex")
        let validCodex = nvm.appendingPathComponent("codex")
        try createExecutable(
            hungCodex,
            contents: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
                /bin/sh -c 'trap "" TERM; echo $$ > "\(childPIDFile.path)"; while :; do sleep 1; done' &
                while :; do sleep 1; done
            fi
            exit 64
            """
        )
        try createExecutable(validCodex, contents: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex 1.0.0'; exit 0; fi\nexit 64\n")

        let detector = CLIPathDetector(
            homeDirectory: home,
            commonBinDirectories: [homebrew, nvm],
            codexHealthProbeTimeoutSeconds: 1
        )
        let result = detector.resolve(tool: .codex)
        let childPID = try XCTUnwrap(waitForPID(in: childPIDFile, timeout: 1))
        defer {
            killIfRunning(childPID)
        }

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, validCodex.path)
        XCTAssertTrue(
            waitForProcessExit(childPID, timeout: 1),
            "SIGTERM-resistant fake codex child process \(childPID) should not remain alive after timeout cleanup"
        )
    }

    func testNonExecutableCodexCandidateFallsBackToLaterHealthyCandidate() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let nvm = home.appendingPathComponent(".nvm/versions/node/v20.11.1/bin", isDirectory: true)
        let nonExecutableCodex = homebrew.appendingPathComponent("codex")
        let validCodex = nvm.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: homebrew, withIntermediateDirectories: true)
        try "not executable".write(to: nonExecutableCodex, atomically: true, encoding: .utf8)
        try createExecutable(validCodex, contents: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex 1.0.0'; exit 0; fi\nexit 64\n")

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [homebrew])
        let result = detector.resolve(tool: .codex)

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, validCodex.path)
    }

    func testClaudeCandidateDoesNotRunHealthProbe() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let homebrew = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let claude = homebrew.appendingPathComponent("claude")
        try createExecutable(claude, contents: "#!/bin/sh\nexit 127\n")

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [homebrew])
        let result = detector.resolve(tool: .claude)

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.executableURL?.path, claude.path)
    }

    func testInvalidManualPathIsReportedBeforeSearch() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let manual = root.appendingPathComponent("claude", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not executable".write(to: manual, atomically: true, encoding: .utf8)

        let detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [])
        let result = detector.resolve(tool: .claude, manualPath: manual.path)

        XCTAssertEqual(result.status, .manualPathInvalid)
        XCTAssertNil(result.executableURL)
    }

    func testMissingCommandIsReportedWhenNoCandidateExists() throws {
        let root = try makeTempDirectory()
        let detector = CLIPathDetector(
            homeDirectory: root.appendingPathComponent("home", isDirectory: true),
            commonBinDirectories: []
        )

        let result = detector.resolve(tool: .codex)

        XCTAssertEqual(result.status, .missing)
        XCTAssertNil(result.executableURL)
    }

    func testEnvNodeShebangRequiresNodeRuntimeInChildPATH() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let codex = bin.appendingPathComponent("codex")
        try createExecutable(codex, contents: "#!/usr/bin/env node\nconsole.log('codex')\n")

        var detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [bin])
        var result = detector.resolve(tool: .codex)

        XCTAssertEqual(result.status, .nodeRuntimeMissing)
        XCTAssertEqual(result.executableURL?.path, codex.path)

        try createExecutable(bin.appendingPathComponent("node"))
        detector = CLIPathDetector(homeDirectory: home, commonBinDirectories: [bin])
        result = detector.resolve(tool: .codex)

        XCTAssertEqual(result.status, .found)
        XCTAssertEqual(result.childPATH.split(separator: ":").first.map(String.init), bin.path)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIPathDetectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectories.append(directory)
        return directory
    }

    private func createExecutable(_ url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func waitForPID(in file: URL, timeout: TimeInterval) -> pid_t? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: file, encoding: .utf8),
               let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return nil
    }

    private func isProcessRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isProcessRunning(pid) {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return !isProcessRunning(pid)
    }

    private func killIfRunning(_ pid: pid_t) {
        guard isProcessRunning(pid) else { return }
        kill(pid, SIGKILL)
    }
}
