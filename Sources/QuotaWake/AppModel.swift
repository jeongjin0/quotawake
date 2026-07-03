import AppKit
import QuotaWakeCore
import SwiftUI

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

// Poller/CLI work blocks on semaphores for up to the 120s execution timeout.
// It runs on this dedicated queue instead of inside Task.detached, which would
// pin one of the cooperative pool's per-core threads for the whole wait.
private let quotaWakeBlockingWorkQueue = DispatchQueue(
    label: "com.jeongjin.quotawake.blocking-work",
    qos: .utility
)

@MainActor
final class QuotaWakeAppModel: ObservableObject {
    @Published var settings: AppSettings { didSet { invalidateUIStates() } }
    @Published var logs: [RunLogEntry] { didSet { invalidateUIStates() } }
    @Published var quotaStates: [QuotaWindowState] { didSet { invalidateUIStates() } }
    @Published var resolvedCommands: [ResolvedToolCommand] { didSet { invalidateUIStates() } }
    @Published var isRunning: Bool { didSet { invalidateUIStates() } }
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

    // The UI state builders sort the full log history, so they are memoized
    // and invalidated when an input @Published property changes instead of
    // being rebuilt on every property access during a render pass.
    private var cachedPopoverState: PopoverUIState?
    private var cachedSettingsState: SettingsUIState?

    var popoverState: PopoverUIState {
        if let cachedPopoverState {
            return cachedPopoverState
        }
        let state = QuotaWakeUIStateBuilder.makePopoverState(
            settings: settings,
            logs: logs,
            resolvedCommands: resolvedCommands,
            quotaStates: quotaStates,
            isRunning: isRunning
        )
        cachedPopoverState = state
        return state
    }

    var settingsState: SettingsUIState {
        if let cachedSettingsState {
            return cachedSettingsState
        }
        let state = QuotaWakeUIStateBuilder.makeSettingsState(
            settings: settings,
            logs: logs,
            resolvedCommands: resolvedCommands,
            quotaStates: quotaStates,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        )
        cachedSettingsState = state
        return state
    }

    private func invalidateUIStates() {
        cachedPopoverState = nil
        cachedSettingsState = nil
    }

    func refresh() {
        // Assign @Published properties only on real changes; unconditional
        // reassignment re-rendered the popover and settings on every poll
        // tick even when nothing changed.
        let loadedSettings = syncLaunchAtLoginApproval((try? settingsStore.load()) ?? .default)
        if settings != loadedSettings {
            settings = loadedSettings
        }
        if !loadedSettings.firstRunCompleted {
            firstRunFlow = FirstRunFlow(settings: loadedSettings)
        }
        let loadedLogs = ((try? logStore.readAll()) ?? []).sorted { $0.startedAt > $1.startedAt }
        if logs != loadedLogs {
            logs = loadedLogs
        }
        let loadedQuotaStates = ToolKind.allCases.compactMap { try? quotaStateStore.load(tool: $0) }
        if quotaStates != loadedQuotaStates {
            quotaStates = loadedQuotaStates
        }
        let resolved = resolveCommands(settings: loadedSettings)
        if resolvedCommands != resolved {
            resolvedCommands = resolved
        }
    }

    nonisolated private static func runBlocking(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            quotaWakeBlockingWorkQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    func runNow() {
        guard !isRunning else {
            return
        }

        isRunning = true
        statusMessage = "Sending readiness now; this may use the current provider window."
        let poller = self.poller

        Task {
            await Self.runBlocking {
                try? poller.sendNow()
            }
            self.isRunning = false
            self.statusMessage = "Readiness send finished."
            self.refresh()
        }
    }

    func startResetAwarePoller(intervalSeconds: TimeInterval = 60) {
        guard pollerTask == nil else {
            return
        }
        let poller = self.poller
        pollerTask = Task { [weak self] in
            while !Task.isCancelled {
                await Self.runBlocking {
                    try? poller.tick()
                    // 55s (not 60) so every pass of the 60-second loop
                    // qualifies as stale and the displayed quota auto-updates.
                    try? poller.observeIfStale(maxAgeSeconds: 55)
                }
                self?.refreshAfterPollTick()
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

    func setReadinessPaused(_ paused: Bool) {
        settings.readiness.paused = paused
        statusMessage = paused ? "Background readiness paused." : "Background readiness resumed."
        saveSettings()
    }

    // Silent background refresh of the displayed quota state (popover open):
    // no isRunning/statusMessage churn, and only tools whose stored state is
    // older than maxAgeSeconds are re-observed.
    func observeQuotaIfStale(maxAgeSeconds: TimeInterval = 30) {
        let poller = self.poller
        Task {
            await Self.runBlocking {
                try? poller.observeIfStale(maxAgeSeconds: maxAgeSeconds)
            }
            self.refresh()
        }
    }

    func observeLastResult() {
        guard !isRunning else {
            return
        }

        isRunning = true
        statusMessage = "Observing local quota state."
        let poller = self.poller

        Task {
            var message = "Observed local quota state."
            await Self.runBlocking {
                do {
                    try poller.observeNow()
                } catch {
                    message = "Local quota observation failed: \(error.localizedDescription)"
                }
            }
            self.isRunning = false
            self.statusMessage = message
            self.refresh()
        }
    }

    // A registration that ends in requiresApproval stores the flag as false;
    // when the user later approves in System Settings nothing re-checked the
    // status, so background readiness stayed off until the toggle was flipped
    // again. Treat an OS-reported enabled state as approval and persist it.
    private func syncLaunchAtLoginApproval(_ settings: AppSettings) -> AppSettings {
        guard !settings.background.launchAtLoginEnabled,
              let status = try? LaunchAtLoginManager.mainApp.currentStatus(),
              status == .enabled else {
            return settings
        }
        var synced = settings
        synced.background.launchAtLoginEnabled = true
        try? settingsStore.save(synced)
        return synced
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

        Task {
            var state = UpdateCheckState.checking
            await Self.runBlocking {
                do {
                    state = try Self.makeUpdateCheckState(
                        currentVersion: currentVersion,
                        endpoint: endpoint,
                        fixtureURL: fixtureURL
                    )
                } catch {
                    state = .failed(error.localizedDescription)
                }
            }
            self.updateCheckState = state
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
            // Only tool enable/path changes affect command resolution; prompt
            // or readiness edits (fired per keystroke) must not re-run CLI
            // detection.
            if lastResolvedToolConfiguration != settings.tools {
                resolvedCommands = resolveCommands(settings: settings)
            }
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

    private var lastResolvedToolConfiguration: ToolSettingsSet?

    private func resolveCommands(settings: AppSettings) -> [ResolvedToolCommand] {
        lastResolvedToolConfiguration = settings.tools
        return ToolKind.allCases.map { tool in
            detector.resolve(tool: tool, manualPath: settings.tools[tool].manualPath)
        }
    }
}
