import XCTest
@testable import QuotaWakeCore

#if canImport(Darwin)
import Darwin
#endif

final class CLIExecutorTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testFakeClaudeAndCodexSuccessUseExactArgvRunDirectoryPathAndLogs() throws {
        let fixture = try makeFixture()
        let claude = try makeFakeExecutable(name: "claude", in: fixture.binDirectory, captureDirectory: fixture.captureDirectory)
        let codex = try makeFakeExecutable(name: "codex", in: fixture.binDirectory, captureDirectory: fixture.captureDirectory)
        let runner = ToolRunner(logStore: fixture.logStore)
        let prompt = "hi"

        let results = runner.runTools([
            makeRequest(tool: .claude, executableURL: claude, fixture: fixture, prompt: prompt),
            makeRequest(tool: .codex, executableURL: codex, fixture: fixture, prompt: prompt)
        ])

        let entries = try results.map { try $0.get() }.sorted { $0.tool.rawValue < $1.tool.rawValue }
        XCTAssertEqual(entries.map(\.status), [.sent, .sent])
        XCTAssertEqual(entries.map(\.exitCode), [0, 0])
        XCTAssertEqual(try fixture.logStore.readAll().map(\.status).sorted { $0.rawValue < $1.rawValue }, [.sent, .sent])

        XCTAssertEqual(try resolvedPath(fixture.captureDirectory.appendingPathComponent("claude.cwd")), fixture.paths.runDirectory.resolvingSymlinksInPath().path)
        XCTAssertEqual(try resolvedPath(fixture.captureDirectory.appendingPathComponent("codex.cwd")), fixture.paths.runDirectory.resolvingSymlinksInPath().path)
        XCTAssertEqual(try readLines(fixture.captureDirectory.appendingPathComponent("claude.args")), [
            "--print",
            "--output-format",
            "text",
            "--no-session-persistence",
            prompt
        ])
        XCTAssertEqual(try readLines(fixture.captureDirectory.appendingPathComponent("codex.args")), [
            "exec",
            "--sandbox",
            "read-only",
            "--skip-git-repo-check",
            "--ephemeral",
            "--ignore-rules",
            "--color",
            "never",
            "-C",
            fixture.paths.runDirectory.path,
            prompt
        ])
        XCTAssertEqual(try readTrimmed(fixture.captureDirectory.appendingPathComponent("claude.path")), fixture.childPATH)
        XCTAssertEqual(try readTrimmed(fixture.captureDirectory.appendingPathComponent("codex.path")), fixture.childPATH)
        try copyLogEvidence(from: fixture, fileName: "fake-success.jsonl")
    }

    func testNonzeroExitLogsFailedWithExitCode() throws {
        let fixture = try makeFixture()
        let executable = try makeFakeExecutable(
            name: "codex",
            in: fixture.binDirectory,
            captureDirectory: fixture.captureDirectory,
            body: "printf 'bad stderr\\n' >&2\nexit 7\n"
        )
        let runner = ToolRunner(logStore: fixture.logStore)

        let entry = try runner.run(makeRequest(
            tool: .codex,
            executableURL: executable,
            fixture: fixture,
            timeoutSeconds: 5
        ))

        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.exitCode, 7)
        XCTAssertFalse(entry.timedOut)
        XCTAssertTrue(entry.stderrSummary.contains("bad stderr"))
        let logs = try fixture.logStore.readAll()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].status, .failed)
        XCTAssertEqual(logs[0].exitCode, 7)
    }

    func testTimeoutTerminatesProcessAndLogsTimedOut() throws {
        let fixture = try makeFixture()
        let executable = try makeFakeExecutable(
            name: "codex",
            in: fixture.binDirectory,
            captureDirectory: fixture.captureDirectory,
            body: "sleep 5\n"
        )
        let runner = ToolRunner(logStore: fixture.logStore)

        let entry = try runner.run(makeRequest(
            tool: .codex,
            executableURL: executable,
            fixture: fixture,
            timeoutSeconds: 1
        ))

        XCTAssertEqual(entry.status, .timedOut)
        XCTAssertNil(entry.exitCode)
        XCTAssertTrue(entry.timedOut)
        let logs = try fixture.logStore.readAll()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].status, .timedOut)
        XCTAssertTrue(logs[0].timedOut)
        try copyLogEvidence(from: fixture, fileName: "fake-timeout.jsonl")
    }

    func testTimeoutKillsSpawnedChildProcess() throws {
        #if canImport(Darwin)
        let fixture = try makeFixture()
        let childPidFile = fixture.captureDirectory.appendingPathComponent("cli-child.pid")
        let executable = try makeParentChildExecutable(directory: fixture.binDirectory, childPidFile: childPidFile)

        let result = try CLIExecutor().run(CLIExecutionRequest(
            tool: .codex,
            executableURL: executable,
            arguments: ["exec", "hi"],
            environment: ["PATH": fixture.childPATH],
            runDirectory: fixture.paths.runDirectory,
            timeoutSeconds: 1,
            prompt: "hi",
            scheduledAt: Self.referenceDate,
            eventId: "child-timeout"
        ))
        let childPid = Int32(try XCTUnwrap(Int(String(contentsOf: childPidFile))))
        defer { kill(childPid, SIGKILL) }

        XCTAssertTrue(result.timedOut)
        XCTAssertNil(result.exitCode)
        XCTAssertTrue(waitForProcessExit(pid: childPid), "CLI timeout must kill spawned child pid \(childPid)")
        #endif
    }

    func testSameToolOverlapLogsSkippedOverlap() throws {
        let fixture = try makeFixture()
        let executable = try makeFakeExecutable(
            name: "claude",
            in: fixture.binDirectory,
            captureDirectory: fixture.captureDirectory,
            body: "touch \"\(fixture.captureDirectory.path)/started\"\nsleep 1\n"
        )
        let runner = ToolRunner(logStore: fixture.logStore)
        let firstFinished = expectation(description: "first run finished")
        var firstEntry: RunLogEntry?
        var firstError: Error?

        DispatchQueue.global(qos: .utility).async {
            do {
                firstEntry = try runner.run(self.makeRequest(tool: .claude, executableURL: executable, fixture: fixture))
            } catch {
                firstError = error
            }
            firstFinished.fulfill()
        }

        try waitForFile(fixture.captureDirectory.appendingPathComponent("started"))
        let skipped = try runner.run(makeRequest(tool: .claude, executableURL: executable, fixture: fixture))
        wait(for: [firstFinished], timeout: 2)

        XCTAssertNil(firstError)
        XCTAssertEqual(firstEntry?.status, .sent)
        XCTAssertEqual(skipped.status, .skippedOverlap)
        let statuses = try fixture.logStore.readAll().map(\.status)
        XCTAssertTrue(statuses.contains(.sent))
        XCTAssertTrue(statuses.contains(.skippedOverlap))
    }

    func testMissingResolvedCommandLogsFailureWithoutExecutingFromProjectDirectory() throws {
        let fixture = try makeFixture()
        let command = ResolvedToolCommand(
            tool: .claude,
            executableURL: nil,
            status: .missing,
            childPATH: fixture.childPATH,
            searchedDirectories: [fixture.binDirectory]
        )
        let runner = ToolRunner(logStore: fixture.logStore)

        let entry = try runner.run(ToolRunRequest(
            command: command,
            prompt: "hi",
            eventId: "missing",
            scheduledAt: Self.referenceDate,
            runDirectory: fixture.paths.runDirectory
        ))

        XCTAssertEqual(entry.status, .failed)
        XCTAssertNil(entry.exitCode)
        XCTAssertTrue(entry.errorSummary?.contains("missing") ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.captureDirectory.appendingPathComponent("claude.cwd").path))
    }

    func testClaudeEnvironmentPolicyScrubsBillingKeysAfterRequestOverlay() {
        var parentEnvironment = Dictionary(
            uniqueKeysWithValues: Self.liveSmokeGuardKeys.map { ($0, "parent-value") }
        )
        parentEnvironment["PATH"] = "/parent/bin"
        parentEnvironment["HOME"] = "/Users/example"
        let requestEnvironment = Dictionary(
            uniqueKeysWithValues: Self.liveSmokeGuardKeys.map { ($0, "request-value") }
        )
        .merging(["PATH": "/child/bin"], uniquingKeysWith: { _, new in new })

        let policy = CLIChildEnvironmentPolicy.build(
            parentEnvironment: parentEnvironment,
            requestEnvironment: requestEnvironment,
            tool: .claude
        )

        XCTAssertEqual(policy.environment["PATH"], "/child/bin")
        XCTAssertEqual(policy.environment["HOME"], "/Users/example")
        for key in Self.liveSmokeGuardKeys {
            XCTAssertNil(policy.environment[key], "\(key) should not reach Claude child env")
        }
        XCTAssertEqual(Set(policy.scrubbedKeyNames), Self.liveSmokeGuardKeys)
        XCTAssertFalse(policy.scrubbedKeyNames.contains { $0.contains("sk-") || $0.contains("secret") })
    }

    func testClaudeEnvironmentPolicyContainsEveryLiveSmokeGuardKey() throws {
        let shellGuardKeys = try Self.readLiveSmokeGuardKeys()

        XCTAssertTrue(
            shellGuardKeys.isSubset(of: CLIChildEnvironmentPolicy.claudeBillingEnvironmentKeys),
            "Swift scrub list is missing shell guard keys: \(shellGuardKeys.subtracting(CLIChildEnvironmentPolicy.claudeBillingEnvironmentKeys).sorted())"
        )
    }

    func testCodexEnvironmentPolicyScrubsBillingKeysAfterRequestOverlay() {
        let policy = CLIChildEnvironmentPolicy.build(
            parentEnvironment: [
                "PATH": "/parent/bin",
                "ANTHROPIC_API_KEY": "fake-ant-parent",
                "OPENAI_API_KEY": "fake-openai-parent",
                "OPENAI_BASE_URL": "fake-openai-base-url"
            ],
            requestEnvironment: [
                "PATH": "/child/bin",
                "OPENAI_PROJECT": "proj-request"
            ],
            tool: .codex
        )

        XCTAssertEqual(policy.environment["PATH"], "/child/bin")
        XCTAssertNil(policy.environment["ANTHROPIC_API_KEY"])
        XCTAssertNil(policy.environment["OPENAI_API_KEY"])
        XCTAssertNil(policy.environment["OPENAI_BASE_URL"])
        XCTAssertNil(policy.environment["OPENAI_PROJECT"])
        XCTAssertEqual(Set(policy.scrubbedKeyNames), [
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "OPENAI_BASE_URL",
            "OPENAI_PROJECT"
        ])
    }

    func testClaudeExecutionScrubsRequestBillingEnvBeforeFakeProcess() throws {
        let fixture = try makeFixture()
        let executable = try makeFakeExecutable(
            name: "claude",
            in: fixture.binDirectory,
            captureDirectory: fixture.captureDirectory,
            body: """
            if [ "${ANTHROPIC_API_KEY+x}" = "x" ]; then
              printf 'protected env reached child\\n' >&2
              exit 42
            fi
            if [ "${CLAUDE_CODE_USE_BEDROCK+x}" = "x" ]; then
              printf 'protected env reached child\\n' >&2
              exit 43
            fi
            if [ "${AZURE_OPENAI_API_KEY+x}" = "x" ]; then
              printf 'protected env reached child\\n' >&2
              exit 44
            fi
            if [ "${FOUNDRY_ENDPOINT+x}" = "x" ]; then
              printf 'protected env reached child\\n' >&2
              exit 45
            fi
            printf 'guarded\\n'
            """
        )
        let request = CLIExecutionRequest(
            tool: .claude,
            executableURL: executable,
            arguments: ["--print", "hi"],
            environment: [
                "PATH": fixture.childPATH,
                "ANTHROPIC_API_KEY": "fake-ant-test",
                "CLAUDE_CODE_USE_BEDROCK": "1",
                "AZURE_OPENAI_API_KEY": "azure-openai-key",
                "FOUNDRY_ENDPOINT": "https://foundry.example"
            ],
            runDirectory: fixture.paths.runDirectory,
            timeoutSeconds: 2,
            prompt: "hi",
            scheduledAt: Self.referenceDate,
            eventId: "billing-env"
        )

        let result = try CLIExecutor().run(request)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertTrue(result.stdout.contains("guarded"))
        XCTAssertFalse(result.stderr.contains("protected env reached child"))
        XCTAssertEqual(try readTrimmed(fixture.captureDirectory.appendingPathComponent("claude.path")), fixture.childPATH)
    }

    func testCodexExecutionScrubsRequestBillingEnvBeforeFakeProcess() throws {
        let fixture = try makeFixture()
        let executable = try makeFakeExecutable(
            name: "codex",
            in: fixture.binDirectory,
            captureDirectory: fixture.captureDirectory,
            body: """
            for key in ANTHROPIC_API_KEY OPENAI_API_KEY OPENAI_BASE_URL OPENAI_ORGANIZATION OPENAI_PROJECT AZURE_OPENAI_API_KEY; do
              eval "present=\\${${key}+x}"
              if [ "${present}" = "x" ]; then
                printf 'protected env reached child: %s\\n' "${key}" >&2
                exit 42
              fi
            done
            printf 'guarded\\n'
            """
        )
        let request = CLIExecutionRequest(
            tool: .codex,
            executableURL: executable,
            arguments: ["exec", "hi"],
            environment: [
                "PATH": fixture.childPATH,
                "ANTHROPIC_API_KEY": "fake-ant-test",
                "OPENAI_API_KEY": "fake-openai-test",
                "OPENAI_BASE_URL": "fake-openai-base-url",
                "OPENAI_ORGANIZATION": "org-test",
                "OPENAI_PROJECT": "proj-test",
                "AZURE_OPENAI_API_KEY": "azure-openai-key"
            ],
            runDirectory: fixture.paths.runDirectory,
            timeoutSeconds: 2,
            prompt: "hi",
            scheduledAt: Self.referenceDate,
            eventId: "codex-billing-env"
        )

        let result = try CLIExecutor().run(request)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertTrue(result.stdout.contains("guarded"))
        XCTAssertFalse(result.stderr.contains("protected env reached child"))
        XCTAssertEqual(try readTrimmed(fixture.captureDirectory.appendingPathComponent("codex.path")), fixture.childPATH)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeCLIExecutorTests-\(UUID().uuidString)", isDirectory: true)
        let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        let captureDirectory = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        tempDirectories.append(root)

        let paths = QuotaWakePaths(applicationSupportDirectory: root.appendingPathComponent("ApplicationSupport", isDirectory: true))
        return Fixture(
            root: root,
            binDirectory: binDirectory,
            captureDirectory: captureDirectory,
            paths: paths,
            childPATH: "\(binDirectory.path):/usr/bin:/bin",
            logStore: RunLogStore(paths: paths, calendar: Self.utcCalendar)
        )
    }

    private func makeRequest(
        tool: ToolKind,
        executableURL: URL,
        fixture: Fixture,
        prompt: String = "hi",
        timeoutSeconds: TimeInterval = 2
    ) -> ToolRunRequest {
        let command = ResolvedToolCommand(
            tool: tool,
            executableURL: executableURL,
            status: .found,
            childPATH: fixture.childPATH,
            searchedDirectories: [fixture.binDirectory]
        )
        return ToolRunRequest(
            command: command,
            prompt: prompt,
            eventId: "event-\(tool.rawValue)",
            scheduledAt: Self.referenceDate,
            runDirectory: fixture.paths.runDirectory,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func makeFakeExecutable(
        name: String,
        in directory: URL,
        captureDirectory: URL,
        body: String? = nil
    ) throws -> URL {
        let executable = directory.appendingPathComponent(name, isDirectory: false)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$PWD" > "\(captureDirectory.path)/\(name).cwd"
        printf '%s\\n' "$PATH" > "\(captureDirectory.path)/\(name).path"
        : > "\(captureDirectory.path)/\(name).args"
        for arg in "$@"; do
          printf '%s\\n' "$arg" >> "\(captureDirectory.path)/\(name).args"
        done
        \(body ?? "printf 'ok\\n'\n")
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        #if canImport(Darwin)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)
        #endif
        return executable
    }

    private func makeParentChildExecutable(directory: URL, childPidFile: URL) throws -> URL {
        let source = directory.appendingPathComponent("parent-child.c")
        let executable = directory.appendingPathComponent("codex", isDirectory: false)
        try """
        #include <signal.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <unistd.h>

        int main(int argc, char **argv) {
          if (argc > 1 && strcmp(argv[1], "child") == 0) {
            close(STDOUT_FILENO);
            close(STDERR_FILENO);
            signal(SIGTERM, SIG_IGN);
            sleep(30);
            return 0;
          }
          pid_t child = fork();
          if (child == 0) {
            execl(argv[0], argv[0], "child", "\(childPidFile.path)", (char *)NULL);
            _exit(127);
          }
          FILE *file = fopen("\(childPidFile.path)", "w");
          if (!file) { return 2; }
          fprintf(file, "%d", child);
          fclose(file);
          sleep(30);
          return 0;
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [source.path, "-o", executable.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return executable
    }

    private func readTrimmed(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedPath(_ url: URL) throws -> String {
        let path = try readTrimmed(url)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func readLines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func waitForFile(_ url: URL) throws {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return
            }
            usleep(20_000)
        }
        XCTFail("Timed out waiting for \(url.path)")
    }

    private func waitForProcessExit(pid: Int32) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if kill(pid, 0) == -1, errno == ESRCH {
                return true
            }
            usleep(20_000)
        }
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    private func copyLogEvidence(from fixture: Fixture, fileName: String) throws {
        guard let evidencePath = ProcessInfo.processInfo.environment["QUOTAWAKE_TEST_EVIDENCE_DIR"] else {
            return
        }

        let evidenceDirectory = URL(fileURLWithPath: evidencePath, isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)

        let logFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.paths.logsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var output = Data()
        for logFile in logFiles {
            output.append(try Data(contentsOf: logFile))
        }
        try output.write(to: evidenceDirectory.appendingPathComponent(fileName), options: [.atomic])
    }

    private static func readLiveSmokeGuardKeys() throws -> Set<String> {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = packageRoot.appendingPathComponent("Scripts/live_cli_smoke.sh")
        let contents = try String(contentsOf: script, encoding: .utf8)

        guard let start = contents.range(of: "GUARD_KEYS=("),
              let end = contents[start.upperBound...].range(of: ")") else {
            XCTFail("Could not find GUARD_KEYS in \(script.path)")
            return []
        }

        return Set(contents[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line in
                guard line.hasPrefix("\""), line.hasSuffix("\"") else {
                    return nil
                }
                return String(line.dropFirst().dropLast())
            })
    }

    private static let liveSmokeGuardKeys: Set<String> = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_CUSTOM_HEADERS",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "OPENAI_API_BASE",
        "OPENAI_API_HOST",
        "OPENAI_ORGANIZATION",
        "OPENAI_ORG_ID",
        "OPENAI_PROJECT",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_ANTHROPIC_AWS",
        "CLAUDE_CODE_USE_FOUNDRY",
        "AWS_PROFILE",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "AZURE_API_KEY",
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_CLIENT_ID",
        "AZURE_CLIENT_SECRET",
        "AZURE_TENANT_ID",
        "AZURE_SUBSCRIPTION_ID",
        "AZURE_FOUNDRY_API_KEY",
        "AZURE_AI_FOUNDRY_API_KEY",
        "AZURE_INFERENCE_ENDPOINT",
        "AZURE_AUTHORITY_HOST",
        "FOUNDRY_API_KEY",
        "FOUNDRY_ENDPOINT"
    ]

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_782_518_400)

    private struct Fixture {
        let root: URL
        let binDirectory: URL
        let captureDirectory: URL
        let paths: QuotaWakePaths
        let childPATH: String
        let logStore: RunLogStore
    }
}
