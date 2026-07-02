import AppKit
import QuotaWakeCore
import SwiftUI

#if DEBUG
// Shared by the QA harness's fake-executable script generators.
func qaShellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
        try Self.makeFakeExecutable(tool: .claude, directory: fakeCLIRoot, captureDirectory: captureDirectory)
        try Self.makeFakeExecutable(tool: .codex, directory: fakeCLIRoot, captureDirectory: captureDirectory)

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
        try Self.copyLogs(from: paths.logsDirectory, to: evidenceDirectory.appendingPathComponent("normal-launch.jsonl"))
        try Self.writeRunSummary(
            logs: storedLogs,
            to: evidenceDirectory.appendingPathComponent("normal-launch-summary.txt")
        )
    }

    private var captureDirectory: URL {
        evidenceDirectory.appendingPathComponent("normal-captures", isDirectory: true)
    }

    private static func makeFakeExecutable(tool: ToolKind, directory: URL, captureDirectory: URL) throws {
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

    private static func copyLogs(from logsDirectory: URL, to outputURL: URL) throws {
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

    private static func writeRunSummary(logs: [RunLogEntry], to outputURL: URL) throws {
        let summary = logs
            .map { "\($0.tool.rawValue) \($0.status.rawValue) \($0.exitCode.map(String.init) ?? "-")" }
            .joined(separator: "\n")
        try (summary + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
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

    static func parse(arguments: [String]) -> UIQAConfig? {
        guard let modeIndex = arguments.firstIndex(of: "--ui-qa"), modeIndex < arguments.count else {
            return nil
        }

        var scenario = "popover-settings"
        var evidenceDirectory: URL?
        var fakeCLIRoot: URL?
        var updateFixture: URL?
        var claudePath: URL?
        var codexPath: URL?
        var index = modeIndex + 1

        while index < arguments.count {
            switch arguments[index] {
            case "--scenario" where index + 1 < arguments.count:
                scenario = arguments[index + 1]
                index += 2
            case "--evidence-dir" where index + 1 < arguments.count:
                evidenceDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                index += 2
            case "--fake-cli-root" where index + 1 < arguments.count:
                fakeCLIRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                index += 2
            case "--update-fixture" where index + 1 < arguments.count:
                updateFixture = URL(fileURLWithPath: arguments[index + 1], isDirectory: false)
                index += 2
            case "--claude-path" where index + 1 < arguments.count:
                claudePath = URL(fileURLWithPath: arguments[index + 1], isDirectory: false)
                index += 2
            case "--codex-path" where index + 1 < arguments.count:
                codexPath = URL(fileURLWithPath: arguments[index + 1], isDirectory: false)
                index += 2
            default:
                index += 1
            }
        }

        guard let evidenceDirectory else {
            return nil
        }
        guard validScenarios.contains(scenario) else {
            FileHandle.standardError.write(Data("invalid --scenario: \(scenario)\n".utf8))
            exit(64)
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

        let now = Date()
        let logs = [
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
            )
        ]

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
