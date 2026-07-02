import AppKit
import QuotaWakeCore
import SwiftUI

final class QuotaWakeApplicationDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var model: QuotaWakeAppModel?
    #if DEBUG
    private let qaConfig = UIQAConfig.parse(arguments: CommandLine.arguments)
    #endif

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = try? BundleMetadata.production.validate()

        #if DEBUG
        if let qaConfig {
            runUIQA(config: qaConfig)
            NSApp.terminate(nil)
            return
        }

        let normalLaunchQAConfig = NormalLaunchQAConfig.parse()
        do {
            try normalLaunchQAConfig?.prepare()
        } catch {
            FileHandle.standardError.write(Data("Normal launch QA setup failed: \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }

        let model = QuotaWakeAppModel(
            paths: normalLaunchQAConfig?.paths ?? QuotaWakePaths(),
            detector: normalLaunchQAConfig?.detector ?? CLIPathDetector()
        )
        #else
        let model = QuotaWakeAppModel()
        #endif
        self.model = model
        #if DEBUG
        if normalLaunchQAConfig == nil {
            model.startResetAwarePoller()
        }
        #else
        model.startResetAwarePoller()
        #endif

        let statusItem = NSStatusBar.system.statusItem(withLength: 44)
        if let button = statusItem.button {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "QW"
            button.alignment = .center
            button.toolTip = "QuotaWake"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.setAccessibilityLabel("QuotaWake")
        }
        statusItem.isVisible = true
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 580)
        popover.contentViewController = NSHostingController(
            rootView: QuotaWakePopoverView(
                model: model,
                openSettings: { [weak self] in self?.showSettings() },
                toggleReadinessPaused: { [weak model] in
                    guard let model else {
                        return
                    }
                    model.setReadinessPaused(!model.settings.readiness.paused)
                },
                quit: { NSApp.terminate(nil) }
            )
        )
        self.popover = popover

        if !model.settings.firstRunCompleted {
            showFirstRunSetup()
        }

        #if DEBUG
        if let normalLaunchQAConfig {
            runNormalLaunchQA(config: normalLaunchQAConfig, model: model)
        }
        #endif
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-opening the app from Finder should surface the menu-bar popover.
        if settingsWindow?.isVisible != true {
            togglePopover(nil)
        }
        return true
    }

    @MainActor
    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        model?.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func showSettings() {
        guard let model else {
            return
        }

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuotaWake Settings"
        window.minSize = NSSize(width: 900, height: 620)
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentViewController = NSHostingController(rootView: QuotaWakeSettingsView(model: model))
        alignSettingsWindowTrafficLights(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        alignSettingsWindowTrafficLights(window)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func alignSettingsWindowTrafficLights(_ window: NSWindow) {
        let buttonOrigins: [(NSWindow.ButtonType, CGFloat)] = [
            (.closeButton, 30),
            (.miniaturizeButton, 52),
            (.zoomButton, 74)
        ]

        for (buttonType, xOrigin) in buttonOrigins {
            guard let button = window.standardWindowButton(buttonType) else {
                continue
            }
            button.setFrameOrigin(NSPoint(x: xOrigin, y: button.frame.origin.y))
        }
    }

    @MainActor
    private func showFirstRunSetup() {
        guard let model else {
            return
        }

        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuotaWake Setup"
        window.minSize = NSSize(width: 720, height: 520)
        window.contentViewController = NSHostingController(
            rootView: FirstRunSetupView(
                model: model,
                close: { [weak self] in
                    self?.setupWindow?.close()
                    self?.setupWindow = nil
                }
            )
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        setupWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    @MainActor
    private func runNormalLaunchQA(config: NormalLaunchQAConfig, model: QuotaWakeAppModel) {
        showSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.togglePopover(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak model] in
            guard let self, let model else {
                NSApp.terminate(nil)
                return
            }

            do {
                let statusButton = self.statusItem?.button
                let statusImage = statusButton?.image
                try config.writeEvidence(
                    statusItemReady: statusButton != nil,
                    statusItemTitle: statusButton?.title ?? "",
                    statusItemHasImage: statusImage != nil,
                    statusItemImageIsTemplate: statusImage?.isTemplate ?? false,
                    statusItemImageSize: statusImage?.size ?? .zero,
                    statusItemImageName: statusImage?.name() ?? "",
                    statusItemImage: statusImage,
                    popoverShown: self.popover?.isShown ?? false,
                    popoverSize: self.popover?.contentSize ?? .zero,
                    settingsWindowShown: self.settingsWindow?.isVisible ?? false,
                    settingsWindowTitle: self.settingsWindow?.title ?? "",
                    logs: model.logs
                )
            } catch {
                FileHandle.standardError.write(Data("Normal launch QA failed: \(error)\n".utf8))
                exit(1)
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private func runUIQA(config: UIQAConfig) {
        do {
            try FileManager.default.createDirectory(
                at: config.evidenceDirectory,
                withIntermediateDirectories: true
            )
            let fixture = UIQAFixture.make(scenario: config.scenario, fakeCLIRoot: config.fakeCLIRoot)
            let openedURLFile = config.evidenceDirectory.appendingPathComponent("opened-url.txt")
            try? FileManager.default.removeItem(at: openedURLFile)
            let updateURLOpener: UpdateURLOpening = config.scenario.hasPrefix("update-")
                ? RecordingUpdateURLOpener(outputURL: openedURLFile)
                : WorkspaceUpdateURLOpener()
            let model = QuotaWakeAppModel.preview(
                settings: fixture.settings,
                logs: fixture.logs,
                quotaStates: fixture.quotaStates,
                commands: fixture.commands,
                updateURLOpener: updateURLOpener
            )

            switch config.scenario {
            case "missing-cli":
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: model, openSettings: {}, quit: {})
                        .frame(width: 360, height: 580),
                    size: NSSize(width: 360, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("missing-cli.png")
                )
            case "broken-codex":
                let result = try runFakeBrokenCodexScenario(
                    settings: fixture.settings,
                    fakeCLIRoot: config.fakeCLIRoot,
                    evidenceDirectory: config.evidenceDirectory,
                    logFileName: "broken-codex.jsonl"
                )
                let brokenModel = QuotaWakeAppModel.preview(
                    settings: result.settings,
                    logs: result.logs,
                    quotaStates: result.quotaStates,
                    commands: result.commands,
                    updateURLOpener: updateURLOpener
                )
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: brokenModel, openSettings: {}, quit: {})
                        .frame(width: 360, height: 580),
                    size: NSSize(width: 360, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("broken-codex.png")
                )
                brokenModel.selectedPane = .tools
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: brokenModel)
                        .frame(width: 980, height: 680),
                    size: NSSize(width: 980, height: 680),
                    to: config.evidenceDirectory.appendingPathComponent("broken-codex-settings-tools.png")
                )
            case "first-run":
                model.firstRunFlow.settings.firstRunCompleted = false
                model.settings.firstRunCompleted = false
                let stepFiles: [(FirstRunStep, String)] = [
                    (.welcome, "01-welcome.png"),
                    (.detectTools, "02-detect-tools.png"),
                    (.windowReadiness, "03-window-readiness.png"),
                    (.testRun, "04-test-run.png")
                ]
                for (step, fileName) in stepFiles {
                    model.firstRunFlow.step = step
                    model.settings = model.firstRunFlow.settings
                    try UIQARenderer.render(
                        FirstRunSetupView(model: model, close: {})
                            .frame(width: 820, height: 580),
                        size: NSSize(width: 820, height: 580),
                        to: config.evidenceDirectory.appendingPathComponent(fileName)
                    )
                }
                var completed = model.firstRunFlow.settings
                completed.firstRunCompleted = true
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(completed).write(
                    to: config.evidenceDirectory.appendingPathComponent("setup-complete.json"),
                    options: [.atomic]
                )
            case "update-available":
                guard let updateFixture = config.updateFixture else {
                    throw UIQAError.missingUpdateFixture
                }
                model.selectedPane = .general
                model.checkForUpdatesForUIQA(fixtureURL: updateFixture)
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: model)
                        .frame(width: 980, height: 680),
                    size: NSSize(width: 980, height: 680),
                    to: config.evidenceDirectory.appendingPathComponent("settings-update-available.png")
                )
                model.openAvailableUpdate()
            case "update-error":
                guard let updateFixture = config.updateFixture else {
                    throw UIQAError.missingUpdateFixture
                }
                model.selectedPane = .general
                model.checkForUpdatesForUIQA(fixtureURL: updateFixture)
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: model)
                        .frame(width: 980, height: 680),
                        size: NSSize(width: 980, height: 680),
                        to: config.evidenceDirectory.appendingPathComponent("settings-update-error.png")
                )
            case "run-now":
                let result = try runFakeToolScenario(
                    settings: fixture.settings,
                    fakeCLIRoot: config.fakeCLIRoot,
                    evidenceDirectory: config.evidenceDirectory,
                    logFileName: "fake-success.jsonl"
                )
                let runModel = QuotaWakeAppModel.preview(
                    settings: result.settings,
                    logs: result.logs,
                    quotaStates: result.quotaStates,
                    commands: result.commands,
                    updateURLOpener: updateURLOpener
                )
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: runModel, openSettings: {}, quit: {})
                        .frame(width: 360, height: 580),
                    size: NSSize(width: 360, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("run-now.png")
                )
            case "live-run-now":
                let result = try runLiveToolScenario(
                    settings: fixture.settings,
                    claudePath: config.claudePath,
                    codexPath: config.codexPath,
                    evidenceDirectory: config.evidenceDirectory,
                    logFileName: "live-run-now.jsonl"
                )
                let runModel = QuotaWakeAppModel.preview(
                    settings: result.settings,
                    logs: result.logs,
                    quotaStates: result.quotaStates,
                    commands: result.commands,
                    updateURLOpener: updateURLOpener
                )
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: runModel, openSettings: {}, quit: {})
                        .frame(width: 360, height: 580),
                    size: NSSize(width: 360, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("live-run-now.png")
                )
            case "tool-toggle":
                var toggledSettings = fixture.settings
                toggledSettings.tools[.codex].enabled = false
                let result = try runFakeToolScenario(
                    settings: toggledSettings,
                    fakeCLIRoot: config.fakeCLIRoot,
                    evidenceDirectory: config.evidenceDirectory,
                    logFileName: "tool-toggle.jsonl"
                )
                let toggledModel = QuotaWakeAppModel.preview(
                    settings: result.settings,
                    logs: result.logs,
                    quotaStates: result.quotaStates,
                    commands: result.commands,
                    updateURLOpener: updateURLOpener
                )
                toggledModel.selectedPane = .tools
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: toggledModel)
                        .frame(width: 980, height: 680),
                        size: NSSize(width: 980, height: 680),
                        to: config.evidenceDirectory.appendingPathComponent("tool-toggle.png")
                )
            case "reset-due-active", "reset-due-idle", "unknown-quota", "quota-unavailable", "limit-reset-observed", "migrated-old-settings":
                let result = try runFakeReadinessScenario(
                    scenario: config.scenario,
                    settings: fixture.settings,
                    fakeCLIRoot: config.fakeCLIRoot,
                    evidenceDirectory: config.evidenceDirectory
                )
                let readinessModel = QuotaWakeAppModel.preview(
                    settings: result.settings,
                    logs: result.logs,
                    quotaStates: result.quotaStates,
                    commands: result.commands,
                    updateURLOpener: updateURLOpener
                )
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: readinessModel, openSettings: {}, quit: {})
                        .frame(width: 360, height: 580),
                    size: NSSize(width: 360, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("popover.png")
                )
                readinessModel.selectedPane = .readiness
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: readinessModel)
                        .frame(width: 980, height: 680),
                    size: NSSize(width: 980, height: 680),
                    to: config.evidenceDirectory.appendingPathComponent("settings-readiness.png")
                )
            case "settings-only":
                for pane in SettingsPaneID.allCases {
                    model.selectedPane = pane
                    let fileName = pane == .general ? "settings.png" : "settings-\(pane.rawValue).png"
                    try UIQARenderer.render(
                        QuotaWakeSettingsView(model: model)
                            .frame(width: 980, height: 680),
                        size: NSSize(width: 980, height: 680),
                        to: config.evidenceDirectory.appendingPathComponent(fileName)
                    )
                }
            case "popover-settings":
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: model, openSettings: {}, quit: {})
                        .frame(width: 360, height: 580),
                    size: NSSize(width: 360, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("popover.png")
                )
                for pane in SettingsPaneID.allCases {
                    model.selectedPane = pane
                    let fileName = pane == .general ? "settings.png" : "settings-\(pane.rawValue).png"
                    try UIQARenderer.render(
                        QuotaWakeSettingsView(model: model)
                            .frame(width: 980, height: 680),
                        size: NSSize(width: 980, height: 680),
                        to: config.evidenceDirectory.appendingPathComponent(fileName)
                    )
                }
            default:
                throw UIQAError.invalidScenario(config.scenario)
            }

            print("Rendered UI QA scenario \(config.scenario) to \(config.evidenceDirectory.path)")
        } catch {
            FileHandle.standardError.write(Data("UI QA failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private func runFakeToolScenario(
        settings: AppSettings,
        fakeCLIRoot: URL?,
        evidenceDirectory: URL,
        logFileName: String
    ) throws -> (settings: AppSettings, commands: [ResolvedToolCommand], logs: [RunLogEntry], quotaStates: [QuotaWindowState]) {
        guard let fakeCLIRoot else {
            throw UIQAError.missingFakeCLIRoot
        }

        let fileManager = FileManager.default
        let evidenceRoot = evidenceDirectory.standardizedFileURL
        let fakeRoot = fakeCLIRoot.standardizedFileURL
        let captureDirectory = evidenceRoot.appendingPathComponent("captures", isDirectory: true)
        let appSupport = evidenceRoot.appendingPathComponent("app-support", isDirectory: true)
        try fileManager.createDirectory(at: fakeRoot, withIntermediateDirectories: true)
        try fileManager.removeItemIfExists(at: captureDirectory)
        try fileManager.removeItemIfExists(at: appSupport)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        for tool in ToolKind.allCases {
            _ = try makeFakeExecutable(
                tool: tool,
                directory: fakeRoot,
                captureDirectory: captureDirectory
            )
        }

        let childPATH = "\(fakeRoot.path):/usr/bin:/bin"
        let commands = ToolKind.allCases.map { tool in
            ResolvedToolCommand(
                tool: tool,
                executableURL: fakeRoot.appendingPathComponent(tool.rawValue, isDirectory: false),
                status: .found,
                childPATH: childPATH,
                searchedDirectories: [fakeRoot]
            )
        }
        let paths = QuotaWakePaths(applicationSupportDirectory: appSupport)
        let logStore = RunLogStore(paths: paths)
        let runner = ToolRunner(logStore: logStore)
        let eventId = "uiqa-run-now-\(Int(Date().timeIntervalSince1970))"
        let scheduledAt = Date()
        try fileManager.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)

        for command in commands where settings.tools[command.tool].enabled {
            _ = try runner.run(
                ToolRunRequest(
                    command: command,
                    prompt: settings.prompt,
                    eventId: eventId,
                    scheduledAt: scheduledAt,
                    runDirectory: paths.runDirectory,
                    timeoutSeconds: 5
                )
            )
        }
        let logs = try logStore.readAll().sorted { $0.tool.rawValue < $1.tool.rawValue }
        try copyLogs(from: paths.logsDirectory, to: evidenceDirectory.appendingPathComponent(logFileName))
        try writeRunSummary(
            logs: logs,
            to: evidenceDirectory.appendingPathComponent(logFileName.replacingOccurrences(of: ".jsonl", with: "-summary.txt"))
        )
        return (settings, commands, logs, [])
    }

    private func runFakeBrokenCodexScenario(
        settings: AppSettings,
        fakeCLIRoot: URL?,
        evidenceDirectory: URL,
        logFileName: String
    ) throws -> (settings: AppSettings, commands: [ResolvedToolCommand], logs: [RunLogEntry], quotaStates: [QuotaWindowState]) {
        guard let fakeCLIRoot else {
            throw UIQAError.missingFakeCLIRoot
        }

        let fileManager = FileManager.default
        let evidenceRoot = evidenceDirectory.standardizedFileURL
        let fakeRoot = fakeCLIRoot.standardizedFileURL
        let captureDirectory = evidenceRoot.appendingPathComponent("captures", isDirectory: true)
        let appSupport = evidenceRoot.appendingPathComponent("broken-app-support", isDirectory: true)
        try fileManager.createDirectory(at: fakeRoot, withIntermediateDirectories: true)
        try fileManager.removeItemIfExists(at: captureDirectory)
        try fileManager.removeItemIfExists(at: appSupport)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        _ = try makeFakeExecutable(
            tool: .claude,
            directory: fakeRoot,
            captureDirectory: captureDirectory
        )
        _ = try makeBrokenFakeCodexExecutable(
            directory: fakeRoot,
            captureDirectory: captureDirectory
        )

        var brokenSettings = settings
        brokenSettings.tools[.codex].enabled = true
        let detector = CLIPathDetector(
            homeDirectory: evidenceRoot.appendingPathComponent("home", isDirectory: true),
            commonBinDirectories: [fakeRoot],
            codexHealthProbeTimeoutSeconds: 1
        )
        let commands = [
            detector.resolve(tool: .claude),
            detector.resolve(tool: .codex)
        ]
        guard let codexCommand = commands.first(where: { $0.tool == .codex }) else {
            throw UIQAError.missingLiveCLIPath(.codex)
        }

        let paths = QuotaWakePaths(applicationSupportDirectory: appSupport)
        let logStore = RunLogStore(paths: paths)
        let runner = ToolRunner(logStore: logStore)
        let eventId = "uiqa-broken-codex-\(Int(Date().timeIntervalSince1970))"
        let scheduledAt = Date()
        try fileManager.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)
        _ = try runner.run(
            ToolRunRequest(
                command: codexCommand,
                prompt: brokenSettings.prompt,
                eventId: eventId,
                scheduledAt: scheduledAt,
                runDirectory: paths.runDirectory,
                timeoutSeconds: 5
            )
        )

        let logs = try logStore.readAll().sorted { $0.tool.rawValue < $1.tool.rawValue }
        try copyLogs(from: paths.logsDirectory, to: evidenceDirectory.appendingPathComponent(logFileName))
        try writeRunSummary(
            logs: logs,
            to: evidenceDirectory.appendingPathComponent(logFileName.replacingOccurrences(of: ".jsonl", with: "-summary.txt"))
        )
        try writeBrokenCodexResolutionSummary(
            command: codexCommand,
            logs: logs,
            captureDirectory: captureDirectory,
            to: evidenceDirectory.appendingPathComponent("local-resolution-failure.txt")
        )
        return (brokenSettings, commands, logs, [])
    }

    private func runFakeReadinessScenario(
        scenario: String,
        settings: AppSettings,
        fakeCLIRoot: URL?,
        evidenceDirectory: URL
    ) throws -> (settings: AppSettings, commands: [ResolvedToolCommand], logs: [RunLogEntry], quotaStates: [QuotaWindowState]) {
        guard let fakeCLIRoot else {
            throw UIQAError.missingFakeCLIRoot
        }

        let fileManager = FileManager.default
        let evidenceRoot = evidenceDirectory.standardizedFileURL
        let fakeRoot = fakeCLIRoot.standardizedFileURL
        let captureDirectory = evidenceRoot.appendingPathComponent("captures", isDirectory: true)
        let appSupport = evidenceRoot.appendingPathComponent("readiness-app-support", isDirectory: true)
        try fileManager.createDirectory(at: fakeRoot, withIntermediateDirectories: true)
        try fileManager.removeItemIfExists(at: captureDirectory)
        try fileManager.removeItemIfExists(at: appSupport)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        for tool in ToolKind.allCases {
            _ = try makeFakeExecutable(tool: tool, directory: fakeRoot, captureDirectory: captureDirectory)
        }

        var scenarioSettings = settings
        let paths = QuotaWakePaths(applicationSupportDirectory: appSupport)
        let logStore = RunLogStore(paths: paths)
        let quotaStateStore = QuotaWindowStateStore(paths: paths)
        let runner = ToolRunner(logStore: logStore)
        let now = Date()
        let resetAt = scenario == "limit-reset-observed" ? now.addingTimeInterval(38 * 60) : now.addingTimeInterval(-60)
        let commands = ToolKind.allCases.map { tool in
            ResolvedToolCommand(
                tool: tool,
                executableURL: fakeRoot.appendingPathComponent(tool.rawValue, isDirectory: false),
                status: .found,
                childPATH: "\(fakeRoot.path):/usr/bin:/bin",
                searchedDirectories: [fakeRoot]
            )
        }
        try fileManager.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)

        if scenario == "migrated-old-settings" {
            let legacy = legacySettingsFixture()
            try legacy.write(to: evidenceDirectory.appendingPathComponent("legacy-settings.json"), atomically: true, encoding: .utf8)
            scenarioSettings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
            scenarioSettings.firstRunCompleted = true
            try SettingsStore(paths: paths).save(scenarioSettings)
            try Data(contentsOf: paths.settingsFile).write(
                to: evidenceDirectory.appendingPathComponent("migrated-settings.json"),
                options: [.atomic]
            )
        }

        let quotaStates = makeReadinessQuotaStates(scenario: scenario, now: now, resetAt: resetAt)
        for state in quotaStates {
            try quotaStateStore.save(state)
        }
        try writeQuotaStates(quotaStates, to: evidenceDirectory.appendingPathComponent("quota-window-states.json"))

        switch scenario {
        case "reset-due-active":
            for command in commands where scenarioSettings.tools[command.tool].enabled {
                _ = try runner.run(ToolRunRequest(
                    command: command,
                    prompt: scenarioSettings.prompt,
                    eventId: QuotaResetWindowEvent.resetWindowId(tool: command.tool, resetAt: resetAt),
                    scheduledAt: now,
                    runDirectory: paths.runDirectory,
                    timeoutSeconds: 5,
                    decisionSource: .quotaWindow,
                    quotaConfidence: .exactReset
                ))
            }
        case "reset-due-idle":
            for command in commands where scenarioSettings.tools[command.tool].enabled {
                try logStore.append(skipEntry(
                    tool: command.tool,
                    commandPath: command.executableURL?.path ?? "",
                    eventId: QuotaResetWindowEvent.resetWindowId(tool: command.tool, resetAt: resetAt),
                    scheduledAt: now,
                    prompt: scenarioSettings.prompt,
                    decisionSource: .activityGate,
                    confidence: .exactReset,
                    reason: "idle",
                    summary: "Active-use gate skipped readiness because the Mac was idle."
                ))
            }
        case "unknown-quota":
            for command in commands where scenarioSettings.tools[command.tool].enabled {
                try logStore.append(skipEntry(
                    tool: command.tool,
                    commandPath: command.executableURL?.path ?? "",
                    eventId: "observe-needed-\(command.tool.rawValue)-\(Int(now.timeIntervalSince1970))",
                    scheduledAt: now,
                    prompt: scenarioSettings.prompt,
                    decisionSource: .providerState,
                    confidence: .unknown,
                    reason: "unknown_quota",
                    summary: "Quota state unknown; observe last result before sending."
                ))
            }
        case "quota-unavailable":
            for command in commands where command.tool == .codex && scenarioSettings.tools[command.tool].enabled {
                try logStore.append(skipEntry(
                    tool: command.tool,
                    commandPath: command.executableURL?.path ?? "",
                    eventId: "quota-unavailable-\(command.tool.rawValue)-\(Int(now.timeIntervalSince1970))",
                    scheduledAt: now,
                    prompt: scenarioSettings.prompt,
                    decisionSource: .providerState,
                    confidence: .unknown,
                    reason: "quota_observe_unavailable",
                    summary: "Codex local quota source is unavailable from this CLI install."
                ))
            }
        case "limit-reset-observed":
            for command in commands where scenarioSettings.tools[command.tool].enabled {
                try logStore.append(skipEntry(
                    tool: command.tool,
                    commandPath: command.executableURL?.path ?? "",
                    eventId: "observed-reset-\(command.tool.rawValue)-\(Int(now.timeIntervalSince1970))",
                    scheduledAt: now,
                    prompt: scenarioSettings.prompt,
                    decisionSource: .quotaWindow,
                    confidence: .observedLocalQuota,
                    reason: "reset_not_due",
                    summary: "Limit reset observed; next reset candidate is not due yet."
                ))
            }
        case "migrated-old-settings":
            for command in commands where scenarioSettings.tools[command.tool].enabled {
                try logStore.append(skipEntry(
                    tool: command.tool,
                    commandPath: command.executableURL?.path ?? "",
                    eventId: "migrated-settings-\(command.tool.rawValue)-\(Int(now.timeIntervalSince1970))",
                    scheduledAt: now,
                    prompt: scenarioSettings.prompt,
                    decisionSource: .estimatedFiveHour,
                    confidence: .estimatedFiveHour,
                    reason: "migration_verified",
                    summary: "Old settings migrated into window readiness without provider execution."
                ))
            }
        default:
            break
        }

        let logs = try logStore.readAll().sorted { $0.tool.rawValue < $1.tool.rawValue }
        try copyLogs(from: paths.logsDirectory, to: evidenceDirectory.appendingPathComponent("\(scenario).jsonl"))
        try writeRunSummary(logs: logs, to: evidenceDirectory.appendingPathComponent("\(scenario)-summary.txt"))
        try writeReadinessScenarioReceipt(
            scenario: scenario,
            logs: logs,
            quotaStates: quotaStates,
            captureDirectory: captureDirectory,
            to: evidenceDirectory.appendingPathComponent("scenario-receipt.txt")
        )
        return (scenarioSettings, commands, logs, quotaStates)
    }

    private func runLiveToolScenario(
        settings: AppSettings,
        claudePath: URL?,
        codexPath: URL?,
        evidenceDirectory: URL,
        logFileName: String
    ) throws -> (settings: AppSettings, commands: [ResolvedToolCommand], logs: [RunLogEntry], quotaStates: [QuotaWindowState]) {
        guard let claudePath else {
            throw UIQAError.missingLiveCLIPath(.claude)
        }
        guard let codexPath else {
            throw UIQAError.missingLiveCLIPath(.codex)
        }

        let fileManager = FileManager.default
        let evidenceRoot = evidenceDirectory.standardizedFileURL
        let appSupport = evidenceRoot.appendingPathComponent("live-app-support", isDirectory: true)
        try fileManager.removeItemIfExists(at: appSupport)

        let commands = try [
            makeLiveCommand(tool: .claude, executableURL: claudePath),
            makeLiveCommand(tool: .codex, executableURL: codexPath)
        ]
        guard let claudeCommand = commands.first(where: { $0.tool == .claude }) else {
            throw UIQAError.missingLiveCLIPath(.claude)
        }
        try writeBillingEnvironmentPolicy(
            claudeCommand: claudeCommand,
            to: evidenceDirectory.appendingPathComponent("billing-env-policy.txt")
        )

        let paths = QuotaWakePaths(applicationSupportDirectory: appSupport)
        let logStore = RunLogStore(paths: paths)
        let runner = ToolRunner(logStore: logStore)
        let eventId = "uiqa-live-run-now-\(Int(Date().timeIntervalSince1970))"
        let scheduledAt = Date()
        var liveSettings = settings
        liveSettings.prompt = "hi"
        try fileManager.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)

        for command in commands where liveSettings.tools[command.tool].enabled {
            _ = try runner.run(
                ToolRunRequest(
                    command: command,
                    prompt: liveSettings.prompt,
                    eventId: eventId,
                    scheduledAt: scheduledAt,
                    runDirectory: paths.runDirectory,
                    timeoutSeconds: 90
                )
            )
        }

        let logs = try logStore.readAll().sorted { $0.tool.rawValue < $1.tool.rawValue }
        try copyLogs(from: paths.logsDirectory, to: evidenceDirectory.appendingPathComponent(logFileName))
        try writeRunSummary(
            logs: logs,
            to: evidenceDirectory.appendingPathComponent(logFileName.replacingOccurrences(of: ".jsonl", with: "-summary.txt"))
        )
        return (liveSettings, commands, logs, [])
    }

    private func makeLiveCommand(tool: ToolKind, executableURL: URL) throws -> ResolvedToolCommand {
        let path = executableURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: path.path) else {
            throw UIQAError.invalidLiveCLIPath(tool, path.path)
        }

        let resolved = CLIPathDetector().resolve(tool: tool, manualPath: path.path)
        guard resolved.status == .found else {
            throw UIQAError.invalidLiveCLIPath(tool, path.path)
        }
        return resolved
    }

    private func writeBillingEnvironmentPolicy(
        claudeCommand: ResolvedToolCommand,
        to outputURL: URL
    ) throws {
        let policy = CLIChildEnvironmentPolicy.build(
            requestEnvironment: ["PATH": claudeCommand.childPATH],
            tool: .claude
        )
        let presentGuardedKeys = CLIChildEnvironmentPolicy.claudeBillingEnvironmentKeys
            .filter { ProcessInfo.processInfo.environment[$0] != nil }
            .sorted()
        let lines = [
            "scenario: live-run-now",
            "tool: claude",
            "selectedPath: \(claudeCommand.executableURL?.path ?? "")",
            "policy: production CLIChildEnvironmentPolicy",
            "valuesRecorded: false",
            "guardedKeyNames: \(CLIChildEnvironmentPolicy.claudeBillingEnvironmentKeys.sorted().joined(separator: ","))",
            "presentGuardedKeyNames: \(presentGuardedKeys.joined(separator: ","))",
            "scrubbedKeyNames: \(policy.scrubbedKeyNames.joined(separator: ","))",
            "anthropicApiKeyPassedToClaude: \(policy.environment["ANTHROPIC_API_KEY"] == nil ? "false" : "true")",
            "guardedEnvPassedToClaude: \(policy.scrubbedKeyNames.isEmpty ? "none-present" : "false")"
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func makeFakeExecutable(
        tool: ToolKind,
        directory: URL,
        captureDirectory: URL
    ) throws -> URL {
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

    private func makeBrokenFakeCodexExecutable(
        directory: URL,
        captureDirectory: URL
    ) throws -> URL {
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

    private func writeBrokenCodexResolutionSummary(
        command: ResolvedToolCommand,
        logs: [RunLogEntry],
        captureDirectory: URL,
        to outputURL: URL
    ) throws {
        let sentCount = logs.filter { $0.status == .sent }.count
        let promptExecutionPath = captureDirectory.appendingPathComponent("codex.args", isDirectory: false)
        let lines = [
            "scenario: broken-codex",
            "tool: codex",
            "resolutionStatus: \(command.status.rawValue)",
            "selectedPath: \(command.executableURL?.path ?? "")",
            "sentCount: \(sentCount)",
            "promptExecutionRecorded: \(FileManager.default.fileExists(atPath: promptExecutionPath.path) ? "true" : "false")",
            "providerCLI: fake-local-only"
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func copyLogs(from logsDirectory: URL, to outputURL: URL) throws {
        let logFiles = try FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var output = Data()
        for logFile in logFiles {
            output.append(try Data(contentsOf: logFile))
        }
        try output.write(to: outputURL, options: [.atomic])
    }

    private func writeRunSummary(logs: [RunLogEntry], to outputURL: URL) throws {
        let summary = logs
            .map { "\($0.tool.rawValue) \($0.status.rawValue) \($0.exitCode.map(String.init) ?? "-")" }
            .joined(separator: "\n")
        try (summary + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func makeReadinessQuotaStates(scenario: String, now: Date, resetAt: Date) -> [QuotaWindowState] {
        ToolKind.allCases.map { tool in
            switch scenario {
            case "unknown-quota":
                return QuotaWindowState(
                    tool: tool,
                    source: .none,
                    confidence: .unknown,
                    classification: .unknownFailure,
                    observedAt: now,
                    summary: "unknown quota state with a deliberately long local-only diagnostic string that should truncate in the popover and wrap cleanly in settings without overlapping nearby controls"
                )
            case "quota-unavailable" where tool == .codex:
                return QuotaWindowState(
                    tool: tool,
                    source: .codexLocalAppServer,
                    confidence: .unknown,
                    classification: .quotaUnavailable,
                    observedAt: now,
                    summary: "Codex local quota source is unavailable from this CLI install."
                )
            case "limit-reset-observed":
                return QuotaWindowState(
                    tool: tool,
                    source: tool == .codex ? .codexLocalAppServer : .claudeUsageProbe,
                    confidence: .observedLocalQuota,
                    classification: .limitReached(resetAt: resetAt),
                    observedAt: now,
                    resetAt: resetAt,
                    usedPercent: 100,
                    remainingPercent: 0,
                    windowLabel: "5h",
                    weeklyUsedPercent: tool == .codex ? 58 : 71,
                    weeklyRemainingPercent: tool == .codex ? 42 : 29,
                    weeklyResetAt: now.addingTimeInterval((tool == .codex ? 4 : 3) * 86_400 + 5 * 3_600),
                    weeklyWindowLabel: "Weekly",
                    summary: "limit reset observed locally; next reset candidate is not due yet"
                )
            case "migrated-old-settings":
                return QuotaWindowState(
                    tool: tool,
                    source: .cliMessageParser,
                    confidence: .estimatedFiveHour,
                    classification: .limitReached(resetAt: resetAt),
                    observedAt: now,
                    resetAt: resetAt,
                    summary: "migrated old settings into window readiness state"
                )
            default:
                return QuotaWindowState(
                    tool: tool,
                    source: .cliMessageParser,
                    confidence: .exactReset,
                    classification: .limitReached(resetAt: resetAt),
                    observedAt: now,
                    resetAt: resetAt,
                    usedPercent: tool == .codex ? 73 : 42,
                    remainingPercent: tool == .codex ? 27 : 58,
                    windowLabel: "5h",
                    weeklyUsedPercent: tool == .codex ? 49 : 38,
                    weeklyRemainingPercent: tool == .codex ? 51 : 62,
                    weeklyResetAt: now.addingTimeInterval((tool == .codex ? 5 : 4) * 86_400),
                    weeklyWindowLabel: "Weekly",
                    summary: "reset candidate due from fake local CLI limit output"
                )
            }
        }
    }

    private func skipEntry(
        tool: ToolKind,
        commandPath: String,
        eventId: String,
        scheduledAt: Date,
        prompt: String,
        decisionSource: QuotaReadinessDecisionSource,
        confidence: QuotaWindowConfidence,
        reason: String,
        summary: String
    ) -> RunLogEntry {
        RunLogEntry(
            eventId: eventId,
            scheduledAt: scheduledAt,
            startedAt: scheduledAt,
            endedAt: scheduledAt,
            tool: tool,
            commandPath: commandPath,
            status: .skippedMissedWindow,
            exitCode: nil,
            durationMs: 0,
            timedOut: false,
            stdoutSummary: "",
            stderrSummary: "",
            prompt: prompt,
            errorSummary: summary,
            decisionSource: decisionSource,
            quotaConfidence: confidence,
            skipReason: reason
        )
    }

    private func writeQuotaStates(_ states: [QuotaWindowState], to outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(states).write(to: outputURL, options: [.atomic])
    }

    private func writeReadinessScenarioReceipt(
        scenario: String,
        logs: [RunLogEntry],
        quotaStates: [QuotaWindowState],
        captureDirectory: URL,
        to outputURL: URL
    ) throws {
        let sentCount = logs.filter { $0.status == .sent }.count
        let skippedCount = logs.filter { $0.status == .skippedMissedWindow }.count
        let promptCaptures = ToolKind.allCases
            .map { "\($0.rawValue)=\(FileManager.default.fileExists(atPath: captureDirectory.appendingPathComponent("\($0.rawValue).args").path))" }
            .joined(separator: ",")
        let confidence = quotaStates.map { "\($0.tool.rawValue):\($0.confidence.rawValue)" }.joined(separator: ",")
        let lines = [
            "scenario: \(scenario)",
            "providerCLI: fake-local-only",
            "sentCount: \(sentCount)",
            "skippedCount: \(skippedCount)",
            "promptCaptures: \(promptCaptures)",
            "quotaConfidence: \(confidence)"
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func legacySettingsFixture() -> String {
        """
        {
          "schemaVersion": 1,
          "firstRunCompleted": true,
          "prompt": "hi",
          "tools": {
            "claude": { "enabled": true, "manualPath": null },
            "codex": { "enabled": true, "manualPath": null }
          },
          "schedule": {
            "weekdays": [2,3,4,5,6],
            "times": [{ "hour": 6, "minute": 0 }],
            "paused": false,
            "missedRunGraceMinutes": 30
          },
          "background": { "launchAtLoginEnabled": true },
          "wake": {
            "enabled": true,
            "leadMinutes": 10,
            "helperInstalled": true,
            "lastRequestedWake": null
          }
        }
        """
    }

    #endif
}
