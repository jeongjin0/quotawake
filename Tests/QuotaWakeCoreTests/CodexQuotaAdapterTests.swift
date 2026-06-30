import XCTest
@testable import QuotaWakeCore

#if canImport(Darwin)
import Darwin
#endif

final class CodexQuotaAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_512_800)
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testObserveReadsCodexAppServerRateLimitsWhenJsonRpcReturnsWindow() throws {
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: #"{"jsonrpc":"2.0","id":2,"result":{"primaryWindow":{"resetAt":"2026-06-29T05:30:00Z","usedPercent":72.5,"window":"5h"}}}"#,
            stderr: "",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.source, .codexLocalAppServer)
        XCTAssertEqual(state.confidence, .observedLocalQuota)
        XCTAssertEqual(state.classification, .limitReached(resetAt: try XCTUnwrap(Self.iso.date(from: "2026-06-29T05:30:00Z"))))
        XCTAssertEqual(state.usedPercent, 72.5)
        XCTAssertEqual(runner.lastRequest?.arguments, ["app-server"])
        XCTAssertNil(runner.lastRequest?.stdin)
    }

    func testObserveReadsCurrentCodexRateLimitSnapshot() throws {
        let resetAt = Date(timeIntervalSince1970: 1_782_728_573)
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: """
            {"id":1,"result":{"userAgent":"QuotaWake/0.142.4","codexHome":"/Users/example/.codex"}}
            {"method":"remoteControl/status/changed","params":{"status":"disabled"}}
            {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":47,"windowDurationMins":300,"resetsAt":1782728573},"secondary":{"usedPercent":16,"windowDurationMins":10080,"resetsAt":1783297367}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":47,"windowDurationMins":300,"resetsAt":1782728573}}}}}
            """,
            stderr: "",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.confidence, .observedLocalQuota)
        XCTAssertEqual(state.classification, .limitReached(resetAt: resetAt))
        XCTAssertEqual(state.resetAt, resetAt)
        XCTAssertEqual(state.usedPercent, 47)
        XCTAssertEqual(state.remainingPercent, 53)
        XCTAssertEqual(state.windowLabel, "5h")
        XCTAssertEqual(state.weeklyUsedPercent, 16)
        XCTAssertEqual(state.weeklyRemainingPercent, 84)
        XCTAssertEqual(state.weeklyResetAt, Date(timeIntervalSince1970: 1_783_297_367))
        XCTAssertEqual(state.weeklyWindowLabel, "Weekly")
    }

    func testObserveClassifiesEmptyAppServerOutputAsQuotaUnavailable() {
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: "",
            stderr: "",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.confidence, .unknown)
        XCTAssertEqual(state.classification, .quotaUnavailable)
        XCTAssertTrue(state.summary.localizedCaseInsensitiveContains("unavailable"))
    }

    func testObserveClassifiesMissingAppServerSocketAsQuotaUnavailable() {
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: 1,
            timedOut: false,
            stdout: "",
            stderr: "Error: failed to connect to socket at /Users/example/.codex/app-server-control/app-server-control.sock\n\nCaused by:\n    No such file or directory (os error 2)",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.classification, .quotaUnavailable)
        XCTAssertTrue(state.summary.localizedCaseInsensitiveContains("unavailable"))
    }

    func testObserveUsesQuotaResponseEvenWhenAppServerWasTerminatedAfterResponse() {
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: nil,
            timedOut: true,
            stdout: #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":61,"windowDurationMins":300,"resetsAt":1782728573}}}}"#,
            stderr: "",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.confidence, .observedLocalQuota)
        XCTAssertEqual(state.usedPercent, 61)
        XCTAssertEqual(state.remainingPercent, 39)
    }

    func testObserveClassifiesMalformedJsonAsUnknownFailure() {
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: "{not json",
            stderr: "Bearer sk-proj-fake",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.confidence, .unknown)
        XCTAssertEqual(state.classification, .unknownFailure)
        XCTAssertFalse(state.summary.contains("sk-proj-fake"))
    }

    func testObserveClassifiesMethodUnavailableWithoutTreatingExitAsSuccess() {
        let runner = RecordingQuotaProbeRunner(result: .success(QuotaProbeResult(
            exitCode: 0,
            timedOut: false,
            stdout: #"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}"#,
            stderr: "",
            startedAt: now,
            endedAt: now
        )))
        let adapter = CodexQuotaAdapter(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            runDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner
        )

        let state = adapter.observe(observedAt: now)

        XCTAssertEqual(state.classification, .unknownFailure)
        XCTAssertTrue(state.summary.localizedCaseInsensitiveContains("method"))
    }

    func testObserveTimeoutTerminatesCodexAppServerProcess() throws {
        #if canImport(Darwin)
        let fixture = try makeFixture()
        let pidFile = fixture.appendingPathComponent("pid")
        let fakeCodex = try makeSleeperExecutable(directory: fixture, pidFile: pidFile)
        let adapter = CodexQuotaAdapter(
            executableURL: fakeCodex,
            runDirectory: fixture,
            runner: QuotaProbeProcessRunner(),
            timeoutSeconds: 1
        )

        let state = adapter.observe(observedAt: now)
        let pid = Int32(try XCTUnwrap(Int(String(contentsOf: pidFile))))

        XCTAssertEqual(state.classification, .unknownFailure)
        XCTAssertTrue(state.summary.localizedCaseInsensitiveContains("timed out"))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        #endif
    }

    func testProbeTimeoutKillsSpawnedChildProcess() throws {
        #if canImport(Darwin)
        let fixture = try makeFixture()
        let childPidFile = fixture.appendingPathComponent("probe-child.pid")
        let releaseFile = fixture.appendingPathComponent("probe-release")
        let fakeCodex = try makeParentChildExecutable(
            directory: fixture,
            childPidFile: childPidFile,
            releaseFile: releaseFile
        )
        let adapter = CodexQuotaAdapter(
            executableURL: fakeCodex,
            runDirectory: fixture,
            runner: QuotaProbeProcessRunner(),
            timeoutSeconds: 1
        )

        let observed = DispatchSemaphore(value: 0)
        var observedState: QuotaWindowState?
        DispatchQueue.global(qos: .userInitiated).async {
            observedState = adapter.observe(observedAt: self.now)
            observed.signal()
        }

        let childPid = try waitForPID(in: childPidFile, timeout: 1)
        try "release\n".write(to: releaseFile, atomically: true, encoding: .utf8)
        defer { kill(childPid, SIGKILL) }

        XCTAssertEqual(observed.wait(timeout: .now() + 3), .success)
        let state = try XCTUnwrap(observedState)
        XCTAssertEqual(state.classification, .unknownFailure)
        XCTAssertTrue(state.summary.localizedCaseInsensitiveContains("timed out"))
        XCTAssertTrue(waitForProcessExit(pid: childPid), "probe timeout must kill spawned child pid \(childPid)")
        #endif
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeCodexAdapterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectories.append(directory)
        return directory
    }

    private func makeSleeperExecutable(directory: URL, pidFile: URL) throws -> URL {
        let source = directory.appendingPathComponent("sleeper.c")
        let executable = directory.appendingPathComponent("codex")
        try """
        #include <signal.h>
        #include <stdio.h>
        #include <unistd.h>

        int main(void) {
          FILE *file = fopen("\(pidFile.path)", "w");
          if (!file) { return 2; }
          fprintf(file, "%d", getpid());
          fclose(file);
          fflush(NULL);
          sleep(10);
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

    private func makeParentChildExecutable(directory: URL, childPidFile: URL, releaseFile: URL) throws -> URL {
        let source = directory.appendingPathComponent("parent-child.c")
        let executable = directory.appendingPathComponent("qw-probe-timeout-child-\(UUID().uuidString)")
        try """
        #include <fcntl.h>
        #include <signal.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <sys/stat.h>
        #include <unistd.h>

        static int write_pid_file(const char *path, pid_t pid) {
          int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
          if (fd < 0) { return 2; }
          dprintf(fd, "%d\\n", pid);
          fsync(fd);
          close(fd);
          return 0;
        }

        static int wait_for_release(const char *path) {
          for (int attempt = 0; attempt < 500; attempt++) {
            if (access(path, F_OK) == 0) { return 0; }
            usleep(10000);
          }
          return 3;
        }

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
          int write_status = write_pid_file("\(childPidFile.path)", child);
          if (write_status != 0) { return write_status; }
          int release_status = wait_for_release("\(releaseFile.path)");
          if (release_status != 0) { return release_status; }
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

    private func waitForPID(in pidFile: URL, timeout: TimeInterval) throws -> Int32 {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let rawPID = try? String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines),
               let pid = Int32(rawPID) {
                return pid
            }
            usleep(10_000)
        } while Date() < deadline

        XCTFail("probe child pid file was not created before timeout cleanup")
        throw CocoaError(.fileNoSuchFile)
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

    private static let iso = ISO8601DateFormatter()
}

private final class RecordingQuotaProbeRunner: QuotaProbeRunning {
    private let result: Result<QuotaProbeResult, Error>
    private(set) var lastRequest: QuotaProbeRequest?

    init(result: Result<QuotaProbeResult, Error>) {
        self.result = result
    }

    func run(_ request: QuotaProbeRequest) throws -> QuotaProbeResult {
        lastRequest = request
        return try result.get()
    }
}
