import AppKit
import QuotaWakeCore
import SwiftUI

#if DEBUG
// Shared by the QA harness's fake-executable script generators.
func qaShellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

// Single home for QA evidence helpers used by both the normal-launch QA path
// and the --ui-qa scenario runner, so the two paths can never verify
// different fake CLIs or summary formats.
enum UIQASupport {
    @discardableResult
    static func makeFakeExecutable(tool: ToolKind, directory: URL, captureDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent(tool.rawValue, isDirectory: false)
        let capturePath = qaShellQuote(captureDirectory.path)
        let toolName = qaShellQuote(tool.rawValue)
        let script = """
        #!/bin/sh
        name=\(toolName)
        capture_dir=\(capturePath)
        printf '%s\\n' "$PWD" > "$capture_dir/$name.cwd"
        printf '%s\\n' "$PATH" > "$capture_dir/$name.path"
        : > "$capture_dir/$name.args"
        for arg in "$@"; do
          printf '%s\\n' "$arg" >> "$capture_dir/$name.args"
        done
        printf 'ok\\n'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    @discardableResult
    static func makeBrokenFakeCodexExecutable(directory: URL, captureDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent(ToolKind.codex.rawValue, isDirectory: false)
        let capturePath = qaShellQuote(captureDirectory.path)
        let script = """
        #!/bin/sh
        capture_dir=\(capturePath)
        if [ "${1:-}" = "--version" ]; then
          printf 'codex --version local probe\\n' >> "$capture_dir/codex.probe"
          printf 'codex local resolution failure\\n' >&2
          exit 127
        fi
        : > "$capture_dir/codex.args"
        for arg in "$@"; do
          printf '%s\\n' "$arg" >> "$capture_dir/codex.args"
        done
        printf 'unexpected prompt execution\\n' >&2
        exit 127
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    static func copyLogs(from logsDirectory: URL, to outputURL: URL) throws {
        let logFiles = ((try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        )) ?? [])
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var output = Data()
        for logFile in logFiles {
            output.append(try Data(contentsOf: logFile))
        }
        try output.write(to: outputURL, options: [.atomic])
    }

    static func writeRunSummary(logs: [RunLogEntry], to outputURL: URL) throws {
        let summary = logs
            .map { "\($0.tool.rawValue) \($0.status.rawValue) \($0.exitCode.map(String.init) ?? "-")" }
            .joined(separator: "\n")
        try (summary + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }
}

struct NormalLaunchQAConfig {
    let evidenceDirectory: URL
    let fakeCLIRoot: URL
    let paths: QuotaWakePaths
    let detector: CLIPathDetector

    static func parse(environment: [String: String] = ProcessInfo.processInfo.environment) -> NormalLaunchQAConfig? {
        guard let evidencePath = environment["QUOTAWAKE_NORMAL_QA_DIR"], !evidencePath.isEmpty else {
            return nil
        }

        let evidenceDirectory = URL(fileURLWithPath: evidencePath, isDirectory: true).standardizedFileURL
        let fakeCLIRoot = URL(
            fileURLWithPath: environment["QUOTAWAKE_FAKE_CLI_ROOT"] ?? evidenceDirectory.appendingPathComponent("fake-cli", isDirectory: true).path,
            isDirectory: true
        ).standardizedFileURL
        let appSupport = evidenceDirectory.appendingPathComponent("app-support", isDirectory: true)
        let detector = CLIPathDetector(
            commonBinDirectories: [fakeCLIRoot] + CLIPathDetector.defaultSystemBinDirectories.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        )
        return NormalLaunchQAConfig(
            evidenceDirectory: evidenceDirectory,
            fakeCLIRoot: fakeCLIRoot,
            paths: QuotaWakePaths(applicationSupportDirectory: appSupport),
            detector: detector
        )
    }

    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try fileManager.removeItemIfExists(at: evidenceDirectory.appendingPathComponent("normal-launch.json"))
        try fileManager.removeItemIfExists(at: evidenceDirectory.appendingPathComponent("normal-launch.jsonl"))
        try fileManager.removeItemIfExists(at: evidenceDirectory.appendingPathComponent("normal-launch-summary.txt"))
        try fileManager.removeItemIfExists(at: captureDirectory)
        try fileManager.removeItemIfExists(at: paths.applicationSupportDirectory)
        try fileManager.createDirectory(at: fakeCLIRoot, withIntermediateDirectories: true)
        try UIQASupport.makeFakeExecutable(tool: .claude, directory: fakeCLIRoot, captureDirectory: captureDirectory)
        try UIQASupport.makeFakeExecutable(tool: .codex, directory: fakeCLIRoot, captureDirectory: captureDirectory)

        let settings = AppSettings(firstRunCompleted: true)
        try SettingsStore(paths: paths).save(settings)
    }

    func writeEvidence(
        statusItemReady: Bool,
        statusItemTitle: String,
        statusItemHasImage: Bool,
        statusItemImageIsTemplate: Bool,
        statusItemImageSize: NSSize,
        statusItemImageName: String,
        statusItemImage: NSImage?,
        popoverShown: Bool,
        popoverSize: NSSize,
        settingsWindowShown: Bool,
        settingsWindowTitle: String,
        logs: [RunLogEntry]
    ) throws {
        let logStore = RunLogStore(paths: paths)
        let storedLogs = ((try? logStore.readAll()) ?? logs).sorted { $0.tool.rawValue < $1.tool.rawValue }
        let payload: [String: Any] = [
            "normalLaunch": true,
            "statusItemReady": statusItemReady,
            "statusItemTitle": statusItemTitle,
            "statusItemHasImage": statusItemHasImage,
            "statusItemImageIsTemplate": statusItemImageIsTemplate,
            "statusItemImageName": statusItemImageName,
            "statusItemImageWidth": Int(statusItemImageSize.width),
            "statusItemImageHeight": Int(statusItemImageSize.height),
            "popoverShown": popoverShown,
            "popoverWidth": Int(popoverSize.width),
            "popoverHeight": Int(popoverSize.height),
            "settingsWindowShown": settingsWindowShown,
            "settingsWindowTitle": settingsWindowTitle,
            "runLogCount": storedLogs.count,
            "runTools": storedLogs.map(\.tool.rawValue).sorted(),
            "runStatuses": storedLogs.map(\.status.rawValue).sorted()
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: evidenceDirectory.appendingPathComponent("normal-launch.json"), options: [.atomic])
        if let statusItemImage {
            try Self.writePNG(
                image: statusItemImage,
                to: evidenceDirectory.appendingPathComponent("status-item-image.png")
            )
        }
        try UIQASupport.copyLogs(from: paths.logsDirectory, to: evidenceDirectory.appendingPathComponent("normal-launch.jsonl"))
        try UIQASupport.writeRunSummary(
            logs: storedLogs,
            to: evidenceDirectory.appendingPathComponent("normal-launch-summary.txt")
        )
    }

    private var captureDirectory: URL {
        evidenceDirectory.appendingPathComponent("normal-captures", isDirectory: true)
    }

    private static func writePNG(image: NSImage, to url: URL) throws {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw UIQAError.pngCreationFailed
        }
        try data.write(to: url, options: [.atomic])
    }
}

struct UIQAConfig {
    let scenario: String
    let evidenceDirectory: URL
    let fakeCLIRoot: URL?
    let updateFixture: URL?
    let claudePath: URL?
    let codexPath: URL?

    private static let validScenarios: Set<String> = [
        "settings-only",
        "popover-settings",
        "settings-empty-logs",
        "settings-light",
        "settings-dark",
        "settings-resize",
        "missing-cli",
        "first-run",
        "run-now",
        "broken-codex",
        "live-run-now",
        "tool-toggle",
        "update-available",
        "update-error",
        "reset-due-active",
        "reset-due-idle",
        "unknown-quota",
        "quota-unavailable",
        "limit-reset-observed",
        "migrated-old-settings"
    ]

    // Once `--ui-qa` is present, any malformed invocation must exit instead of
    // returning nil: a nil config falls through to a normal launch that uses
    // the real Application Support directory and starts the readiness poller.
    static func parse(arguments: [String]) -> UIQAConfig? {
        guard let modeIndex = arguments.firstIndex(of: "--ui-qa") else {
            return nil
        }

        func failUsage(_ message: String) -> Never {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exit(64)
        }

        var scenario = "popover-settings"
        var evidenceDirectory: URL?
        var fakeCLIRoot: URL?
        var updateFixture: URL?
        var claudePath: URL?
        var codexPath: URL?
        var index = modeIndex + 1

        func nextValue(for flag: String) -> String {
            guard index + 1 < arguments.count else {
                failUsage("\(flag) requires a value")
            }
            defer { index += 2 }
            return arguments[index + 1]
        }

        while index < arguments.count {
            switch arguments[index] {
            case "--scenario":
                scenario = nextValue(for: "--scenario")
            case "--evidence-dir":
                evidenceDirectory = URL(fileURLWithPath: nextValue(for: "--evidence-dir"), isDirectory: true)
            case "--fake-cli-root":
                fakeCLIRoot = URL(fileURLWithPath: nextValue(for: "--fake-cli-root"), isDirectory: true)
            case "--update-fixture":
                updateFixture = URL(fileURLWithPath: nextValue(for: "--update-fixture"), isDirectory: false)
            case "--claude-path":
                claudePath = URL(fileURLWithPath: nextValue(for: "--claude-path"), isDirectory: false)
            case "--codex-path":
                codexPath = URL(fileURLWithPath: nextValue(for: "--codex-path"), isDirectory: false)
            default:
                failUsage("unknown --ui-qa argument: \(arguments[index])")
            }
        }

        guard let evidenceDirectory else {
            failUsage("--ui-qa requires --evidence-dir")
        }
        guard validScenarios.contains(scenario) else {
            failUsage("invalid --scenario: \(scenario)")
        }
        return UIQAConfig(
            scenario: scenario,
            evidenceDirectory: evidenceDirectory,
            fakeCLIRoot: fakeCLIRoot,
            updateFixture: updateFixture,
            claudePath: claudePath,
            codexPath: codexPath
        )
    }
}

enum UIQAFixture {
    static func make(scenario: String, fakeCLIRoot: URL?) -> (settings: AppSettings, logs: [RunLogEntry], commands: [ResolvedToolCommand], quotaStates: [QuotaWindowState]) {
        var settings = AppSettings.default
        settings.firstRunCompleted = true
        settings.background.launchAtLoginEnabled = true
        settings.prompt = """
        Prepare a concise session-readiness note for Claude and Codex. Confirm the current usage window, summarize the exact reset evidence, and only send if the user is active and the configured cooldown has elapsed. Include enough context that a long prompt preview proves Settings rows do not overlap or resize unexpectedly.
        """

        let now = Date()
        let fixtureLogs = [
            RunLogEntry(
                eventId: "qa-success",
                scheduledAt: now,
                startedAt: now,
                endedAt: now.addingTimeInterval(2),
                tool: .claude,
                commandPath: "/usr/local/bin/claude",
                status: .sent,
                exitCode: 0,
                durationMs: 2_000,
                timedOut: false,
                stdoutSummary: "ok",
                stderrSummary: "",
                prompt: settings.prompt
            ),
            RunLogEntry(
                eventId: "qa-codex-long-summary",
                scheduledAt: now.addingTimeInterval(-300),
                startedAt: now.addingTimeInterval(-300),
                endedAt: now.addingTimeInterval(-296),
                tool: .codex,
                commandPath: "/opt/homebrew/bin/codex",
                status: .failed,
                exitCode: 70,
                durationMs: 4_100,
                timedOut: false,
                stdoutSummary: "",
                stderrSummary: "Local quota probe returned an unusually long diagnostic summary that must wrap inside the log table without pushing the exit-code or summary columns out of view.",
                prompt: settings.prompt
            )
        ]
        let logs = scenario == "settings-empty-logs" ? [] : fixtureLogs

        if scenario == "missing-cli" {
            settings.tools.codex.manualPath = "/Users/example/.nvm/versions/node/v99.99.99/bin/codex-with-a-very-long-name"
            return (
                settings,
                logs,
                [
                    command(tool: .claude, status: .missing, fakeCLIRoot: fakeCLIRoot),
                    command(tool: .codex, status: .manualPathInvalid, fakeCLIRoot: fakeCLIRoot)
                ],
                defaultQuotaStates(now: now)
            )
        }

        return (
            settings,
            logs,
            [
                command(tool: .claude, status: .found, fakeCLIRoot: fakeCLIRoot),
                command(tool: .codex, status: .found, fakeCLIRoot: fakeCLIRoot)
            ],
            defaultQuotaStates(now: now)
        )
    }

    private static func defaultQuotaStates(now: Date) -> [QuotaWindowState] {
        ToolKind.allCases.map { tool in
            QuotaWindowState(
                tool: tool,
                source: tool == .codex ? .codexLocalAppServer : .claudeUsageProbe,
                confidence: .exactReset,
                classification: .limitReached(resetAt: now.addingTimeInterval(45 * 60)),
                observedAt: now,
                resetAt: now.addingTimeInterval(45 * 60),
                usedPercent: 100,
                remainingPercent: 0,
                windowLabel: "5h",
                summary: "limit reset observed from local fake QA state"
            )
        }
    }

    private static func command(tool: ToolKind, status: CLIResolutionStatus, fakeCLIRoot: URL?) -> ResolvedToolCommand {
        let path = fakeCLIRoot?.appendingPathComponent(tool.rawValue, isDirectory: false)
            ?? URL(fileURLWithPath: "/usr/local/bin/\(tool.rawValue)")
        return ResolvedToolCommand(
            tool: tool,
            executableURL: status == .missing ? nil : path,
            status: status,
            childPATH: path.deletingLastPathComponent().path,
            searchedDirectories: []
        )
    }
}

enum UIQARenderer {
    static func render<Content: View>(
        _ view: Content,
        size: NSSize,
        to url: URL,
        colorScheme: ColorScheme = .dark
    ) throws {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        let hostingView = NSHostingView(rootView: view.environment(\.colorScheme, colorScheme))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.appearance = appearance

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw UIQAError.bitmapCreationFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw UIQAError.pngCreationFailed
        }
        try data.write(to: url, options: [.atomic])
        window.close()
    }
}

enum UIQAError: Error {
    case bitmapCreationFailed
    case pngCreationFailed
    case invalidScenario(String)
    case missingFakeCLIRoot
    case missingLiveCLIPath(ToolKind)
    case invalidLiveCLIPath(ToolKind, String)
    case missingUpdateFixture
}

extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else {
            return
        }
        try removeItem(at: url)
    }
}
#endif
