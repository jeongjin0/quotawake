import AppKit
import QuotaWakeCore
import SwiftUI

// SIZE_OK(MVP): executable composition root plus native views remain together until
// the first release cut. Release builds exclude the DEBUG-only UIQA harness below;
// follow-up split targets are AppModel.swift, AppDelegate.swift, SettingsViews.swift,
// FirstRunViews.swift, and DebugUIQA.swift.

protocol UpdateURLOpening {
    func open(_ url: URL) -> Bool
}

struct WorkspaceUpdateURLOpener: UpdateURLOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

struct RecordingUpdateURLOpener: UpdateURLOpening {
    let outputURL: URL

    func open(_ url: URL) -> Bool {
        do {
            try url.absoluteString.write(to: outputURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
final class QuotaWakeAppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var logs: [RunLogEntry]
    @Published var quotaStates: [QuotaWindowState]
    @Published var resolvedCommands: [ResolvedToolCommand]
    @Published var isRunning: Bool
    @Published var selectedPane: SettingsPaneID?
    @Published var statusMessage: String?
    @Published var firstRunFlow: FirstRunFlow
    @Published var setupStatusMessage: String?
    @Published var updateCheckState: UpdateCheckState
    @Published var openedUpdateURL: URL?

    private let paths: QuotaWakePaths
    private let settingsStore: SettingsStore
    private let logStore: RunLogStore
    private let quotaStateStore: QuotaWindowStateStore
    private let detector: CLIPathDetector
    private let runner: ToolRunning
    private let updateURLOpener: UpdateURLOpening
    private let poller: QuotaReadinessPoller
    private var pollerTask: Task<Void, Never>?

    init(
        paths: QuotaWakePaths = QuotaWakePaths(),
        settingsStore: SettingsStore? = nil,
        logStore: RunLogStore? = nil,
        detector: CLIPathDetector = CLIPathDetector(),
        runner: ToolRunner? = nil,
        updateURLOpener: UpdateURLOpening = WorkspaceUpdateURLOpener(),
        loadFromDisk: Bool = true
    ) {
        self.paths = paths
        self.settingsStore = settingsStore ?? SettingsStore(paths: paths)
        let store = logStore ?? RunLogStore(paths: paths)
        self.logStore = store
        let quotaStateStore = QuotaWindowStateStore(paths: paths)
        self.quotaStateStore = quotaStateStore
        self.detector = detector
        self.runner = runner ?? ToolRunner(logStore: store)
        self.updateURLOpener = updateURLOpener
        self.poller = QuotaReadinessPoller(
            paths: paths,
            settingsStore: self.settingsStore,
            logStore: store,
            quotaStateStore: quotaStateStore,
            commandsProvider: { [detector, settingsStore = self.settingsStore] in
                let loadedSettings = (try? settingsStore.load()) ?? .default
                return ToolKind.allCases.map { tool in
                    detector.resolve(tool: tool, manualPath: loadedSettings.tools[tool].manualPath)
                }
            },
            runner: self.runner
        )
        self.settings = .default
        self.logs = []
        self.quotaStates = []
        self.resolvedCommands = []
        self.isRunning = false
        self.selectedPane = .general
        self.firstRunFlow = FirstRunFlow(settings: .default)
        self.setupStatusMessage = nil
        self.updateCheckState = .idle
        self.openedUpdateURL = nil

        if loadFromDisk {
            refresh()
        } else {
            resolvedCommands = resolveCommands(settings: settings)
        }
    }

    static func preview(
        settings: AppSettings,
        logs: [RunLogEntry],
        quotaStates: [QuotaWindowState] = [],
        commands: [ResolvedToolCommand],
        updateURLOpener: UpdateURLOpening = WorkspaceUpdateURLOpener()
    ) -> QuotaWakeAppModel {
        let model = QuotaWakeAppModel(updateURLOpener: updateURLOpener, loadFromDisk: false)
        model.settings = settings
        model.logs = logs
        model.quotaStates = quotaStates
        model.resolvedCommands = commands
        model.firstRunFlow = FirstRunFlow(settings: settings)
        return model
    }

    var popoverState: PopoverUIState {
        QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: logs,
            resolvedCommands: resolvedCommands,
            quotaStates: quotaStates,
            isRunning: isRunning
        )
    }

    var settingsState: SettingsUIState {
        QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: logs,
            resolvedCommands: resolvedCommands,
            quotaStates: quotaStates,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        )
    }

    func refresh() {
        let loadedSettings = (try? settingsStore.load()) ?? .default
        settings = loadedSettings
        if !loadedSettings.firstRunCompleted {
            firstRunFlow = FirstRunFlow(settings: loadedSettings)
        }
        logs = ((try? logStore.readAll()) ?? []).sorted { $0.startedAt > $1.startedAt }
        quotaStates = ToolKind.allCases.compactMap { try? quotaStateStore.load(tool: $0) }
        resolvedCommands = resolveCommands(settings: settings)
    }

    func runNow() {
        guard !isRunning else {
            return
        }

        isRunning = true
        statusMessage = "Sending readiness now; this may use the current provider window."
        let poller = self.poller

        Task.detached {
            try? poller.sendNow()

            await MainActor.run {
                self.isRunning = false
                self.statusMessage = "Readiness send finished."
                self.refresh()
            }
        }
    }

    func startResetAwarePoller(intervalSeconds: TimeInterval = 60) {
        guard pollerTask == nil else {
            return
        }
        let poller = self.poller
        pollerTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? poller.tick()
                await self?.refreshAfterPollTick()
                let nanoseconds = UInt64(max(1, intervalSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    func stopResetAwarePoller() {
        pollerTask?.cancel()
        pollerTask = nil
    }

    private func refreshAfterPollTick() {
        refresh()
    }

    func setToolEnabled(_ tool: ToolKind, enabled: Bool) {
        settings.tools[tool].enabled = enabled
        saveSettings()
    }

    func setManualPath(_ tool: ToolKind, path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.tools[tool].manualPath = normalized.isEmpty ? nil : normalized
        saveSettings()
    }

    func setPrompt(_ prompt: String) {
        settings.prompt = prompt
        saveSettings()
    }

    func setActiveOnly(_ enabled: Bool) {
        settings.readiness.activeOnly = enabled
        saveSettings()
    }

    func setIdleThresholdSeconds(_ seconds: Int) {
        settings.readiness.idleThresholdSeconds = min(max(30, seconds), 3_600)
        saveSettings()
    }

    func setMinimumSendCooldownMinutes(_ minutes: Int) {
        settings.readiness.minimumSendCooldownMinutes = min(max(0, minutes), 360)
        saveSettings()
    }

    func setResetEstimationMode(_ mode: ResetEstimationMode) {
        settings.readiness.resetEstimationMode = mode
        saveSettings()
    }

    func observeLastResult() {
        guard !isRunning else {
            return
        }

        isRunning = true
        statusMessage = "Observing local quota state."
        let poller = self.poller

        Task.detached {
            let message: String
            do {
                try poller.observeNow()
                message = "Observed local quota state."
            } catch {
                message = "Local quota observation failed: \(error.localizedDescription)"
            }

            await MainActor.run {
                self.isRunning = false
                self.statusMessage = message
                self.refresh()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let status = try LaunchAtLoginManager.mainApp.setEnabled(enabled)
            if enabled {
                settings.background.launchAtLoginEnabled = status == .enabled
                statusMessage = launchAtLoginMessage(for: status, requestedEnabled: true)
            } else {
                settings.background.launchAtLoginEnabled = false
                statusMessage = "Launch at Login disabled."
            }
            saveSettings()
        } catch {
            statusMessage = "Launch at Login update failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func setupContinue() -> FirstRunTransition {
        let transition = firstRunFlow.advance()
        settings = firstRunFlow.settings
        switch transition {
        case .advanced:
            setupStatusMessage = nil
        case let .blocked(reason):
            setupStatusMessage = reason.message
        case let .completed(completedSettings):
            settings = completedSettings
            setupStatusMessage = "Setup complete."
            saveSettings()
        }
        return transition
    }

    func setupBack() {
        firstRunFlow.moveBack()
        settings = firstRunFlow.settings
        setupStatusMessage = nil
    }

    func setupSetManualPath(_ tool: ToolKind, path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        firstRunFlow.settings.tools[tool].manualPath = normalized.isEmpty ? nil : normalized
        settings = firstRunFlow.settings
        saveSettings()
    }

    func setupSetLaunchAtLogin(_ enabled: Bool) {
        do {
            let status = try LaunchAtLoginManager.mainApp.setEnabled(enabled)
            firstRunFlow.setLaunchAtLoginEnabled(enabled ? status == .enabled : false)
            settings = firstRunFlow.settings
            setupStatusMessage = enabled
                ? launchAtLoginMessage(for: status, requestedEnabled: true)
                : "Launch at Login disabled."
            saveSettings()
        } catch {
            setupStatusMessage = "Launch at Login update failed: \(error.localizedDescription)"
        }
    }

    func setupRunTest() {
        runNow()
        firstRunFlow.markTestRunCompleted()
        settings = firstRunFlow.settings
        setupStatusMessage = "Test run marked complete."
    }

    func setupSetSkipTestAcknowledged(_ acknowledged: Bool) {
        if acknowledged {
            firstRunFlow.acknowledgeTestRunSkip()
        } else {
            firstRunFlow.testRunSkippedAcknowledged = false
        }
        settings = firstRunFlow.settings
    }

    func checkForUpdates(fixtureURL: URL? = nil) {
        updateCheckState = .checking
        let currentVersion = Self.currentVersion()
        let endpoint = Self.updateEndpoint()

        Task.detached {
            let state: UpdateCheckState
            do {
                state = try Self.makeUpdateCheckState(
                    currentVersion: currentVersion,
                    endpoint: endpoint,
                    fixtureURL: fixtureURL
                )
            } catch {
                state = .failed(error.localizedDescription)
            }

            await MainActor.run {
                self.updateCheckState = state
            }
        }
    }

    func checkForUpdatesForUIQA(fixtureURL: URL? = nil) {
        updateCheckState = .checking
        do {
            updateCheckState = try Self.makeUpdateCheckState(
                currentVersion: Self.currentVersion(),
                endpoint: Self.updateEndpoint(),
                fixtureURL: fixtureURL
            )
        } catch {
            updateCheckState = .failed(error.localizedDescription)
        }
    }

    func openAvailableUpdate() {
        guard case let .available(_, url) = updateCheckState else {
            return
        }
        if updateURLOpener.open(url) {
            openedUpdateURL = url
        } else {
            updateCheckState = .failed("Could not open update URL.")
        }
    }

    private nonisolated static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private nonisolated static func updateEndpoint() -> String {
        Bundle.main.object(forInfoDictionaryKey: "QuotaWakeReleasesLatestAPIURL") as? String
            ?? "https://api.github.com/repos/jeongjin0/quotawake/releases/latest"
    }

    private nonisolated static func makeUpdateCheckState(
        currentVersion: String,
        endpoint: String,
        fixtureURL: URL?
    ) throws -> UpdateCheckState {
        let checker = try UpdateChecker(currentVersion: currentVersion, endpoint: endpoint) { url in
            if let fixtureURL {
                return try Data(contentsOf: fixtureURL)
            }
            return try Data(contentsOf: url)
        }
        switch try checker.check() {
        case let .upToDate(_, latest):
            return .upToDate("QuotaWake \(latest) is current.")
        case let .available(info):
            return .available(version: info.version.description, url: info.preferredOpenURL)
        }
    }

    private func saveSettings() {
        do {
            try settingsStore.save(settings)
            resolvedCommands = resolveCommands(settings: settings)
        } catch {
            statusMessage = "Settings save failed: \(error.localizedDescription)"
        }
    }

    private func launchAtLoginMessage(for status: LaunchAtLoginStatus, requestedEnabled: Bool) -> String {
        guard requestedEnabled else {
            return "Launch at Login disabled."
        }

        switch status {
        case .enabled:
            return "Launch at Login enabled."
        case .requiresApproval:
            return "Launch at Login requires approval in System Settings."
        case .notRegistered:
            return "Launch at Login is not registered."
        case .notFound:
            return "Launch at Login service was not found."
        case .unknown:
            return "Launch at Login status is unknown."
        }
    }

    private func resolveCommands(settings: AppSettings) -> [ResolvedToolCommand] {
        ToolKind.allCases.map { tool in
            detector.resolve(tool: tool, manualPath: settings.tools[tool].manualPath)
        }
    }
}

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
        model.startResetAwarePoller()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "QW"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: QuotaWakePopoverView(
                model: model,
                openSettings: { [weak self] in self?.showSettings() },
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuotaWake Settings"
        window.minSize = NSSize(width: 720, height: 520)
        window.contentViewController = NSHostingController(rootView: QuotaWakeSettingsView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
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
                try config.writeEvidence(
                    statusItemReady: self.statusItem?.button != nil,
                    statusItemTitle: self.statusItem?.button?.title ?? "",
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
                        .frame(width: 360, height: 500),
                    size: NSSize(width: 360, height: 500),
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
                        .frame(width: 360, height: 500),
                    size: NSSize(width: 360, height: 500),
                    to: config.evidenceDirectory.appendingPathComponent("broken-codex.png")
                )
                brokenModel.selectedPane = .tools
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: brokenModel)
                        .frame(width: 820, height: 580),
                    size: NSSize(width: 820, height: 580),
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
                        .frame(width: 820, height: 580),
                    size: NSSize(width: 820, height: 580),
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
                        .frame(width: 820, height: 580),
                        size: NSSize(width: 820, height: 580),
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
                        .frame(width: 360, height: 500),
                    size: NSSize(width: 360, height: 500),
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
                        .frame(width: 360, height: 500),
                    size: NSSize(width: 360, height: 500),
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
                        .frame(width: 820, height: 580),
                        size: NSSize(width: 820, height: 580),
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
                        .frame(width: 360, height: 500),
                    size: NSSize(width: 360, height: 500),
                    to: config.evidenceDirectory.appendingPathComponent("popover.png")
                )
                readinessModel.selectedPane = .readiness
                try UIQARenderer.render(
                    QuotaWakeSettingsView(model: readinessModel)
                        .frame(width: 820, height: 580),
                    size: NSSize(width: 820, height: 580),
                    to: config.evidenceDirectory.appendingPathComponent("settings-readiness.png")
                )
            case "popover-settings":
                try UIQARenderer.render(
                    QuotaWakePopoverView(model: model, openSettings: {}, quit: {})
                        .frame(width: 360, height: 500),
                    size: NSSize(width: 360, height: 500),
                    to: config.evidenceDirectory.appendingPathComponent("popover.png")
                )
                for pane in SettingsPaneID.allCases {
                    model.selectedPane = pane
                    let fileName = pane == .general ? "settings.png" : "settings-\(pane.rawValue).png"
                    try UIQARenderer.render(
                        QuotaWakeSettingsView(model: model)
                            .frame(width: 820, height: 580),
                        size: NSSize(width: 820, height: 580),
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
        let capturePath = WakeHelperRenderer.shellQuote(captureDirectory.path)
        let toolName = WakeHelperRenderer.shellQuote(tool.rawValue)
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
        let capturePath = WakeHelperRenderer.shellQuote(captureDirectory.path)
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
                    usedPercent: 100,
                    remainingPercent: 0,
                    windowLabel: "5h",
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

enum QWTheme {
    static let windowBackground = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let sidebarBackground = Color(red: 0.90, green: 0.92, blue: 0.94)
    static let surface = Color(red: 1.00, green: 1.00, blue: 1.00)
    static let surfaceSubtle = Color(red: 0.91, green: 0.93, blue: 0.95)
    static let border = Color(red: 0.76, green: 0.79, blue: 0.83)
    static let primaryText = Color(red: 0.08, green: 0.10, blue: 0.13)
    static let secondaryText = Color(red: 0.38, green: 0.42, blue: 0.48)
    static let accent = Color(red: 0.12, green: 0.36, blue: 0.72)
    static let accentPressed = Color(red: 0.09, green: 0.28, blue: 0.58)
    static let success = Color(red: 0.05, green: 0.58, blue: 0.30)
    static let warning = Color(red: 0.82, green: 0.45, blue: 0.08)
    static let error = Color(red: 0.78, green: 0.16, blue: 0.16)
    static let info = Color(red: 0.12, green: 0.36, blue: 0.72)
}

struct QWCommandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(background(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(prominent ? Color.clear : QWTheme.border, lineWidth: 1)
            )
    }

    private var foreground: Color {
        if !isEnabled {
            return QWTheme.secondaryText.opacity(0.65)
        }
        return prominent ? QWTheme.surface : QWTheme.primaryText
    }

    private func background(configuration: Configuration) -> Color {
        if !isEnabled {
            return QWTheme.surfaceSubtle
        }
        if prominent {
            return configuration.isPressed ? QWTheme.accentPressed : QWTheme.accent
        }
        return configuration.isPressed ? QWTheme.surfaceSubtle : QWTheme.surface
    }
}

struct QWIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? QWTheme.primaryText : QWTheme.secondaryText.opacity(0.65))
            .frame(width: 32, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? QWTheme.surfaceSubtle : QWTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(QWTheme.border, lineWidth: 1)
            )
    }
}

struct QWSidebarButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? QWTheme.primaryText : QWTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(sidebarBackground(configuration: configuration))
            )
    }

    private func sidebarBackground(configuration: Configuration) -> Color {
        if selected {
            return QWTheme.surface
        }
        return configuration.isPressed ? QWTheme.surfaceSubtle : Color.clear
    }
}

struct QWGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QWTheme.primaryText)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(QWTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(QWTheme.border, lineWidth: 1)
        )
    }
}

extension SettingsPaneID {
    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .tools:
            return "terminal"
        case .readiness:
            return "sparkles"
        case .prompt:
            return "text.bubble"
        case .logs:
            return "list.bullet.rectangle"
        }
    }
}

extension FirstRunStep {
    var systemImage: String {
        switch self {
        case .welcome:
            return "sparkles"
        case .detectTools:
            return "terminal"
        case .windowReadiness:
            return "clock.badge.checkmark"
        case .testRun:
            return "paperplane"
        case .complete:
            return "checkmark.circle"
        }
    }

    var setupSummary: String {
        switch self {
        case .welcome:
            return "Connect installed CLIs and keep readiness behavior explicit."
        case .detectTools:
            return "Confirm Claude and Codex paths before background sends are allowed."
        case .windowReadiness:
            return "Choose when this Mac is allowed to send reset-aware readiness prompts."
        case .testRun:
            return "Verify the path with one optional readiness prompt."
        case .complete:
            return "Setup is complete."
        }
    }

    var compactTitle: String {
        switch self {
        case .welcome:
            return "Intro"
        case .detectTools:
            return "Tools"
        case .windowReadiness:
            return "Readiness"
        case .testRun:
            return "Test"
        case .complete:
            return "Done"
        }
    }
}

struct QuotaWakePopoverView: View {
    @ObservedObject var model: QuotaWakeAppModel
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        let state = model.popoverState

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("QuotaWake")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                StatusDot(tone: state.statusTone)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(state.statusDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(QWTheme.secondaryText)
                    .lineLimit(2)
            }

            Divider()

            StatusLine(label: "Window", value: state.readinessText, tone: .neutral)
            StatusLine(label: "Provider", value: state.providerStatusText, tone: state.statusTone)
            StatusLine(label: "5h quota", value: state.fiveHourQuotaText, tone: .neutral)
            StatusLine(label: "Reset", value: state.resetTimeText, tone: .neutral)
            StatusLine(label: "Confidence", value: state.confidenceText, tone: .neutral)
            StatusLine(label: "Tools", value: state.enabledToolsText, tone: .neutral)
            StatusLine(label: "Activity", value: state.activityText, tone: .neutral)
            StatusLine(label: "Last", value: state.lastRunText, tone: state.statusTone)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.providerStates, id: \.tool) { provider in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            StatusDot(tone: provider.statusTone)
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(provider.statusText)
                                .font(.system(size: 12))
                                .foregroundStyle(QWTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(provider.confidenceText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(QWTheme.secondaryText)
                                .lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            Text(provider.quotaText)
                                .font(.system(size: 11))
                                .foregroundStyle(QWTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("Reset \(provider.nextResetText)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(QWTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(10)
            .background(QWTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(QWTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let message = model.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(QWTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    model.runNow()
                } label: {
                    Label(state.runNowTitle, systemImage: "paperplane")
                }
                .disabled(!state.canRunNow)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(QWCommandButtonStyle(prominent: true))

                Button {
                    model.observeLastResult()
                } label: {
                    Label("Observe", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(QWCommandButtonStyle())

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(QWIconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Settings")

                Button {
                    quit()
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(QWIconButtonStyle())
                .help("Quit")
                .accessibilityLabel("Quit")
            }
        }
        .padding(16)
        .frame(width: 360, height: 500)
        .background(QWTheme.windowBackground)
        .foregroundStyle(QWTheme.primaryText)
        .environment(\.colorScheme, .light)
    }

    private func tone(for tool: ToolUIState) -> UIStatusTone {
        if !tool.enabled {
            return .neutral
        }
        switch tool.status {
        case .found:
            return .success
        case .missing, .manualPathInvalid, .nodeRuntimeMissing, .brokenExecutable:
            return .warning
        }
    }
}

struct FirstRunSetupView: View {
    @ObservedObject var model: QuotaWakeAppModel
    let close: () -> Void
    private let setupSteps = FirstRunStep.allCases.filter { $0 != .complete }

    var body: some View {
        VStack(spacing: 0) {
            FirstRunProgressHeader(
                step: model.firstRunFlow.step,
                stepIndex: currentStepIndex,
                stepCount: setupSteps.count,
                progressValue: progressValue
            )

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.firstRunFlow.step.title)
                                .font(.system(size: 24, weight: .semibold))
                            Text(model.firstRunFlow.step.setupSummary)
                                .font(.system(size: 13))
                                .foregroundStyle(QWTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        FirstRunStepContentView(model: model)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Divider()

                HStack(spacing: 12) {
                    if let message = model.setupStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(QWTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        model.setupBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(QWCommandButtonStyle())
                    .disabled(!model.firstRunFlow.canMoveBack)

                    Button {
                        let transition = model.setupContinue()
                        if case .completed = transition {
                            close()
                        }
                    } label: {
                        Label(continueTitle, systemImage: continueIcon)
                    }
                    .buttonStyle(QWCommandButtonStyle(prominent: true))
                }
                .padding(16)
                .background(QWTheme.windowBackground)
            }
            .background(QWTheme.windowBackground)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(QWTheme.windowBackground)
        .foregroundStyle(QWTheme.primaryText)
        .tint(QWTheme.accent)
        .groupBoxStyle(QWGroupBoxStyle())
        .environment(\.colorScheme, .light)
    }

    private var currentStepIndex: Int {
        setupSteps.firstIndex(of: model.firstRunFlow.step).map { $0 + 1 } ?? setupSteps.count
    }

    private var progressValue: Double {
        guard !setupSteps.isEmpty else {
            return 1
        }
        return Double(currentStepIndex) / Double(setupSteps.count)
    }

    private var continueTitle: String {
        model.firstRunFlow.step == .testRun ? "Finish" : "Continue"
    }

    private var continueIcon: String {
        model.firstRunFlow.step == .testRun ? "checkmark" : "chevron.right"
    }
}

struct FirstRunProgressHeader: View {
    let step: FirstRunStep
    let stepIndex: Int
    let stepCount: Int
    let progressValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QuotaWake")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Session readiness setup")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(QWTheme.secondaryText)
                }

                Spacer()

                Text("Step \(stepIndex) of \(stepCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QWTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(QWTheme.surfaceSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(QWTheme.border, lineWidth: 1)
                    )
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(QWTheme.surfaceSubtle)
                    Capsule()
                        .fill(QWTheme.accent)
                        .frame(width: max(0, min(geometry.size.width, geometry.size.width * progressValue)))
                }
            }
            .frame(height: 6)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(stepIndex) of \(stepCount)")

            HStack(spacing: 8) {
                Image(systemName: step.systemImage)
                    .frame(width: 16)
                Text("Current: \(step.compactTitle)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(QWTheme.primaryText)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(QWTheme.surface)
    }
}

struct FirstRunStepContentView: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        switch model.firstRunFlow.step {
        case .welcome:
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("QuotaWake watches local quota-window signals and sends a small readiness prompt only when the window appears due.")
                        .font(.system(size: 15, weight: .semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        FirstRunFeatureLine(
                            icon: "terminal",
                            title: "Use your installed tools",
                            detail: "Claude and Codex run from explicit CLI paths."
                        )
                        FirstRunFeatureLine(
                            icon: "person.crop.circle.badge.checkmark",
                            title: "Respect active time",
                            detail: "Background sends wait until this Mac appears in use."
                        )
                        FirstRunFeatureLine(
                            icon: "paperplane",
                            title: "Verify before finishing",
                            detail: "The final step lets you run or explicitly skip one live test."
                        )
                    }

                    Text("The test run may consume a small amount of provider usage.")
                        .foregroundStyle(QWTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        case .detectTools:
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-detected paths are used by default. Add a manual path only when the detected command is missing or points to the wrong install.")
                    .font(.system(size: 13))
                    .foregroundStyle(QWTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(model.settingsState.toolStates, id: \.tool) { state in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StatusDot(tone: state.status == .found ? .success : .warning)
                                Text(state.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(state.statusText)
                                    .foregroundStyle(QWTheme.secondaryText)
                            }
                            SettingsRow(label: "Path", value: state.pathText, monospaced: true)
                            TextField(
                                "Manual path",
                                text: Binding(
                                    get: { model.settings.tools[state.tool].manualPath ?? "" },
                                    set: { model.setupSetManualPath(state.tool, path: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding(12)
                    }
                }
            }
        case .windowReadiness:
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.firstRunFlow.settings.background.launchAtLoginEnabled },
                            set: { model.setupSetLaunchAtLogin($0) }
                        )
                    )
                    Text("Session readiness starts after login when this is enabled.")
                        .foregroundStyle(QWTheme.secondaryText)
                    Divider()
                    Toggle(
                        "Require active use",
                        isOn: Binding(
                            get: { model.firstRunFlow.settings.readiness.activeOnly },
                            set: {
                                model.firstRunFlow.settings.readiness.activeOnly = $0
                                model.settings = model.firstRunFlow.settings
                            }
                        )
                    )
                    SettingsRow(
                        label: "Idle threshold",
                        value: "\(model.firstRunFlow.settings.readiness.idleThresholdSeconds) seconds"
                    )
                    SettingsRow(
                        label: "Cooldown",
                        value: "\(model.firstRunFlow.settings.readiness.minimumSendCooldownMinutes) minutes"
                    )
                    Text("Readiness sends only when a reset candidate is due and this Mac appears active.")
                        .foregroundStyle(QWTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        case .testRun:
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Send the readiness prompt now or acknowledge skipping the test.")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Live tools are used only when you press Run Test. Finish stays blocked until you either run it or acknowledge the skip.")
                        .foregroundStyle(QWTheme.secondaryText)
                    Button {
                        model.setupRunTest()
                    } label: {
                        Label("Run Test", systemImage: "paperplane")
                    }
                    .buttonStyle(QWCommandButtonStyle(prominent: true))
                    .disabled(model.popoverState.toolStates.filter(\.enabled).allSatisfy { $0.status != .found })

                    Toggle(
                        "Skip test with acknowledgment",
                        isOn: Binding(
                            get: { model.firstRunFlow.testRunSkippedAcknowledged },
                            set: { model.setupSetSkipTestAcknowledged($0) }
                        )
                    )
                }
                .padding(12)
            }
        case .complete:
            GroupBox {
                Text("Setup complete.")
                    .padding(12)
            }
        }
    }
}

struct FirstRunFeatureLine: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QWTheme.accent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(QWTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct QuotaWakeSettingsView: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QuotaWake")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 8)

                ForEach(SettingsPaneID.allCases, id: \.self) { pane in
                    Button {
                        model.selectedPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.systemImage)
                    }
                    .buttonStyle(QWSidebarButtonStyle(selected: (model.selectedPane ?? .general) == pane))
                }

                Spacer()

                Text(model.settingsState.appVersionText)
                    .font(.caption)
                    .foregroundStyle(QWTheme.secondaryText)
            }
            .padding(16)
            .frame(width: 180)
            .background(QWTheme.sidebarBackground)

            Rectangle()
                .fill(QWTheme.border)
                .frame(width: 1)

            Group {
                switch model.selectedPane ?? .general {
                case .general:
                    GeneralPane(model: model)
                case .tools:
                    ToolsPane(model: model)
                case .readiness:
                    ReadinessPane(model: model)
                case .prompt:
                    PromptPane(model: model)
                case .logs:
                    LogsPane(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(QWTheme.windowBackground)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(QWTheme.windowBackground)
        .foregroundStyle(QWTheme.primaryText)
        .tint(QWTheme.accent)
        .groupBoxStyle(QWGroupBoxStyle())
        .environment(\.colorScheme, .light)
    }
}

struct GeneralPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "General") {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(label: "App", value: model.settingsState.appVersionText)
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.settings.background.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    HStack {
                        Button {
                            model.checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(updateIsChecking)
                        Spacer()
                        Text(updateStatusText)
                            .foregroundStyle(QWTheme.secondaryText)
                    }
                    if case let .available(version, _) = model.updateCheckState {
                        Button {
                            model.openAvailableUpdate()
                        } label: {
                            Label("Download QuotaWake \(version)", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(QWCommandButtonStyle(prominent: true))
                    }
                }
                .padding(12)
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(QWTheme.secondaryText)
            }
        }
    }

    private var updateIsChecking: Bool {
        if case .checking = model.updateCheckState {
            return true
        }
        return false
    }

    private var updateStatusText: String {
        switch model.updateCheckState {
        case .idle:
            return "Manual"
        case .checking:
            return "Checking"
        case let .upToDate(message):
            return message
        case let .available(version, _):
            return "QuotaWake \(version) available"
        case let .failed(message):
            return message
        }
    }
}

struct ToolsPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Tools") {
            ForEach(model.settingsState.toolStates, id: \.tool) { state in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            state.displayName,
                            isOn: Binding(
                                get: { model.settings.tools[state.tool].enabled },
                                set: { model.setToolEnabled(state.tool, enabled: $0) }
                            )
                        )
                        SettingsRow(label: "Status", value: state.statusText)
                        SettingsRow(label: "Detected path", value: state.pathText, monospaced: true)
                        TextField(
                            "Manual path",
                            text: Binding(
                                get: { model.settings.tools[state.tool].manualPath ?? "" },
                                set: { model.setManualPath(state.tool, path: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        HStack {
                            Text(state.detailText)
                                .font(.caption)
                                .foregroundStyle(QWTheme.secondaryText)
                            Spacer()
                            Button {
                                model.runNow()
                            } label: {
                                Label("Test", systemImage: "checkmark.circle")
                            }
                            .disabled(!state.canTest)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

struct ReadinessPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Window Readiness") {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(label: "Summary", value: model.settingsState.readinessSummary)
                    SettingsRow(label: "Next reset", value: model.settingsState.nextResetText)
                    SettingsRow(label: "Confidence", value: model.settingsState.confidenceText)
                }
                .padding(12)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Require active use",
                        isOn: Binding(
                            get: { model.settings.readiness.activeOnly },
                            set: { model.setActiveOnly($0) }
                        )
                    )
                    Stepper(
                        "Idle threshold: \(model.settings.readiness.idleThresholdSeconds) seconds",
                        value: Binding(
                            get: { model.settings.readiness.idleThresholdSeconds },
                            set: { model.setIdleThresholdSeconds($0) }
                        ),
                        in: 30...3_600,
                        step: 30
                    )
                    Stepper(
                        "Minimum send cooldown: \(model.settings.readiness.minimumSendCooldownMinutes) minutes",
                        value: Binding(
                            get: { model.settings.readiness.minimumSendCooldownMinutes },
                            set: { model.setMinimumSendCooldownMinutes($0) }
                        ),
                        in: 0...360,
                        step: 5
                    )
                    Picker(
                        "Reset estimation",
                        selection: Binding(
                            get: { model.settings.readiness.resetEstimationMode },
                            set: { model.setResetEstimationMode($0) }
                        )
                    ) {
                        Text("Local signals only").tag(ResetEstimationMode.localSignalsOnly)
                        Text("Allow estimated candidate").tag(ResetEstimationMode.allowFiveHourEstimate)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.settingsState.providerStates, id: \.tool) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                StatusDot(tone: provider.statusTone)
                                Text(provider.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(provider.statusText)
                                    .foregroundStyle(QWTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            SettingsRow(label: "Last readiness", value: provider.lastReadinessText)
                            SettingsRow(label: "Next reset", value: provider.nextResetText)
                            SettingsRow(label: "Confidence", value: provider.confidenceText)
                            SettingsRow(label: "Source", value: provider.sourceText)
                            Text(provider.detailText)
                                .font(.caption)
                                .foregroundStyle(QWTheme.secondaryText)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        if provider.tool != model.settingsState.providerStates.last?.tool {
                            Divider()
                        }
                    }
                }
                .padding(12)
            } label: {
                Text("Provider Status")
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button {
                    model.runNow()
                } label: {
                    Label("Send Readiness Now", systemImage: "paperplane")
                }
                .buttonStyle(QWCommandButtonStyle(prominent: true))
                .disabled(!model.popoverState.canRunNow)

                Button {
                    model.observeLastResult()
                } label: {
                    Label("Observe Last Result", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(QWCommandButtonStyle())
            }
        }
    }
}

struct PromptPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Prompt") {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Readiness prompt")
                        .font(.system(size: 14, weight: .semibold))
                    TextEditor(
                        text: Binding(
                            get: { model.settings.prompt },
                            set: { model.setPrompt($0) }
                        )
                    )
                    .font(.body)
                    .frame(minHeight: 160)
                    Text("Current preview: \(model.settingsState.promptPreview)")
                        .font(.caption)
                        .foregroundStyle(QWTheme.secondaryText)
                }
                .padding(12)
            }
        }
    }
}

struct LogsPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Logs") {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Time").frame(width: 72, alignment: .leading)
                        Text("Tool").frame(width: 72, alignment: .leading)
                        Text("Status").frame(width: 120, alignment: .leading)
                        Text("Duration").frame(width: 76, alignment: .leading)
                        Text("Summary").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QWTheme.secondaryText)

                    Divider()

                    if model.settingsState.logRows.isEmpty {
                        Text("No runs yet")
                            .foregroundStyle(QWTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(model.settingsState.logRows.enumerated()), id: \.offset) { _, row in
                                    HStack(alignment: .top) {
                                        Text(row.timeText).frame(width: 72, alignment: .leading)
                                        Text(row.toolText).frame(width: 72, alignment: .leading)
                                        Text(row.statusText).frame(width: 120, alignment: .leading)
                                        Text(row.durationText).frame(width: 76, alignment: .leading)
                                        Text(row.summaryText)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

struct SettingsPaneLayout<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(QWTheme.windowBackground)
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(QWTheme.secondaryText)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .body)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }
}

struct StatusLine: View {
    let label: String
    let value: String
    let tone: UIStatusTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(QWTheme.secondaryText)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}

struct StatusDot: View {
    let tone: UIStatusTone

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch tone {
        case .neutral:
            return QWTheme.secondaryText
        case .success:
            return QWTheme.success
        case .warning:
            return QWTheme.warning
        case .error:
            return QWTheme.error
        case .info:
            return QWTheme.info
        }
    }
}

#if DEBUG
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
        let capturePath = WakeHelperRenderer.shellQuote(captureDirectory.path)
        let toolName = WakeHelperRenderer.shellQuote(tool.rawValue)
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
    static func render<Content: View>(_ view: Content, size: NSSize, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: .aqua)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1)
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

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else {
            return
        }
        try removeItem(at: url)
    }
}
#endif

let application = NSApplication.shared
let delegate = QuotaWakeApplicationDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
