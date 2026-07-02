import AppKit
import QuotaWakeCore
import SwiftUI

enum QWTheme {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let glassSurface = Color(nsColor: .windowBackgroundColor).opacity(0.62)
    static let glassPressed = Color(nsColor: .controlAccentColor).opacity(0.10)
    static let surfaceSubtle = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let glassBorder = Color(nsColor: .separatorColor).opacity(0.62)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let accent = Color.accentColor
    static let accentPressed = Color(nsColor: .selectedContentBackgroundColor)
    static let accentForeground = Color.white
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let info = Color(nsColor: .systemBlue)
    // Provider identity accents follow the Redesign v2 marks.
    static let claudeAccent = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
    static let claudeWash = Color(red: 0.851, green: 0.467, blue: 0.341).opacity(0.12)
    static let codexAccent = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let codexWash = Color(red: 0.051, green: 0.051, blue: 0.051).opacity(0.08)

    // Redesign v2 status/pill palette (popover renders in fixed light mode).
    static let pillGreen = Color(red: 0.114, green: 0.541, blue: 0.263) // #1d8a43
    static let pillOrange = Color(red: 0.784, green: 0.388, blue: 0.102) // #c8631a
    static let pillBlue = Color(red: 0.039, green: 0.435, blue: 0.839) // #0a6fd6
    static let pillRed = Color(red: 0.824, green: 0.231, blue: 0.188) // #d23b30

    // Neutral translucent card surface used by provider cards in the popover.
    static let cardFill = Color.white
    static let cardStroke = Color.black.opacity(0.10)
    static let popoverInk = Color.black.opacity(0.86)
    static let popoverInkSecondary = Color.black.opacity(0.5)
    static let popoverInkTertiary = Color.black.opacity(0.4)
    static let popoverHairline = Color.black.opacity(0.08)
}

enum QWSettingsTheme {
    static let window = Color(red: 0.112, green: 0.122, blue: 0.122)
    static let sidebarOuter = Color(red: 0.118, green: 0.136, blue: 0.132)
    static let sidebarBlockTop = Color(red: 0.075, green: 0.081, blue: 0.079)
    static let sidebarBlockBottom = Color(red: 0.061, green: 0.066, blue: 0.064)
    static let block = Color(red: 0.082, green: 0.086, blue: 0.086)
    static let blockRow = Color(red: 0.095, green: 0.099, blue: 0.098)
    static let blockRowRaised = Color(red: 0.116, green: 0.120, blue: 0.119)
    static let panel = block
    static let panelRaised = blockRowRaised
    static let rowPressed = Color.white.opacity(0.085)
    static let sidebarSelected = Color(red: 0.285, green: 0.285, blue: 0.285)
    static let border = Color.white.opacity(0.075)
    static let strongBorder = Color.white.opacity(0.15)
    static let sidebarBorder = Color.white.opacity(0.20)
    static let primaryText = Color.white.opacity(0.88)
    static let secondaryText = Color.white.opacity(0.64)
    static let tertiaryText = Color.white.opacity(0.42)
    static let control = Color.white.opacity(0.105)
    static let controlPressed = Color.white.opacity(0.14)
    static let input = Color(red: 0.075, green: 0.078, blue: 0.078)
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let accentForeground = Color.white

    static let sidebarBlock = LinearGradient(
        colors: [sidebarBlockTop, sidebarBlockBottom],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct QWCommandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(background(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(prominent ? Color.clear : border, lineWidth: 1)
            )
    }

    private var border: Color {
        colorScheme == .dark ? QWSettingsTheme.strongBorder : QWTheme.border
    }

    private var foreground: Color {
        if !isEnabled {
            return colorScheme == .dark ? QWSettingsTheme.tertiaryText : QWTheme.secondaryText.opacity(0.65)
        }
        if colorScheme == .dark {
            return prominent ? QWSettingsTheme.accentForeground : QWSettingsTheme.primaryText
        }
        return prominent ? QWTheme.accentForeground : QWTheme.primaryText
    }

    private func background(configuration: Configuration) -> Color {
        if !isEnabled {
            return colorScheme == .dark ? QWSettingsTheme.control.opacity(0.55) : QWTheme.surfaceSubtle
        }
        if prominent {
            if colorScheme == .dark {
                return configuration.isPressed ? QWSettingsTheme.accent.opacity(0.78) : QWSettingsTheme.accent
            }
            return configuration.isPressed ? QWTheme.accentPressed : QWTheme.accent
        }
        if colorScheme == .dark {
            return configuration.isPressed ? QWSettingsTheme.controlPressed : QWSettingsTheme.control
        }
        return configuration.isPressed ? QWTheme.surfaceSubtle : QWTheme.surface
    }
}

struct QWSidebarButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: selected ? .semibold : .semibold))
            .foregroundStyle(selected ? QWSettingsTheme.primaryText : QWSettingsTheme.secondaryText)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(sidebarBackground(configuration: configuration))
            )
    }

    private func sidebarBackground(configuration: Configuration) -> Color {
        if selected {
            return QWSettingsTheme.sidebarSelected
        }
        return configuration.isPressed ? QWSettingsTheme.rowPressed : Color.clear
    }
}

struct QWGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QWTheme.primaryText)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QWTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(QWTheme.border.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

struct QuotaWakeSettingsView: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar

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
            .background(QWSettingsTheme.window)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(QWSettingsTheme.window)
        .foregroundStyle(QWSettingsTheme.primaryText)
        .tint(QWSettingsTheme.accent)
        .groupBoxStyle(QWGroupBoxStyle())
        .environment(\.colorScheme, .dark)
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(QWSettingsTheme.sidebarBlock)
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(QWSettingsTheme.sidebarBorder, lineWidth: 1)
                )
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 92)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SettingsPaneID.allCases, id: \.self) { pane in
                        Button {
                            model.selectedPane = pane
                        } label: {
                            SidebarNavigationItem(pane: pane)
                        }
                        .buttonStyle(QWSidebarButtonStyle(selected: (model.selectedPane ?? .general) == pane))
                    }
                }

                Spacer(minLength: 20)

                Text(model.settingsState.appVersionText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QWSettingsTheme.tertiaryText)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .frame(width: 254)
        .background(QWSettingsTheme.sidebarOuter)
    }
}

struct SidebarNavigationItem: View {
    let pane: SettingsPaneID

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, alignment: .center)
            Text(pane.title)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
            Spacer(minLength: 0)
        }
    }
}

struct GeneralPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "General") {
            SettingsSection("Status") {
                SettingsStatusBanner(
                    title: model.popoverState.statusTitle,
                    detail: model.popoverState.statusDetail,
                    tone: model.popoverState.statusTone
                ) {
                    Button {
                        model.runNow()
                    } label: {
                        Label(model.popoverState.runNowTitle, systemImage: "paperplane")
                    }
                    .buttonStyle(QWCommandButtonStyle(prominent: true))
                    .disabled(!model.popoverState.canRunNow)
                }
            }

            SettingsSection("Application") {
                SettingsValueRow(
                    label: "App",
                    detail: "Installed QuotaWake build.",
                    value: model.settingsState.appVersionText
                )
                SettingsDivider()
                SettingsControlRow(
                    label: "Launch at Login",
                    detail: "Start session readiness after you sign in."
                ) {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.settings.background.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsControlRow(
                    label: "Background readiness",
                    detail: "Pause automatic quota window readiness without changing manual actions."
                ) {
                    Toggle(
                        "Background readiness",
                        isOn: Binding(
                            get: { !model.settings.readiness.paused },
                            set: { model.setReadinessPaused(!$0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsControlRow(
                    label: "Manual updates",
                    detail: "Check the release page for a signed DMG."
                ) {
                    HStack(spacing: 10) {
                        Button {
                            model.checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(QWCommandButtonStyle())
                        .disabled(updateIsChecking)
                        Text(updateStatusText)
                            .foregroundStyle(QWSettingsTheme.secondaryText)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }
                if case let .available(version, _) = model.updateCheckState {
                    SettingsDivider()
                    SettingsControlRow(
                        label: "Available download",
                        detail: "Open the latest manual installer."
                    ) {
                        Button {
                            model.openAvailableUpdate()
                        } label: {
                            Label("Download QuotaWake \(version)", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(QWCommandButtonStyle(prominent: true))
                    }
                }
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(QWSettingsTheme.secondaryText)
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
                SettingsSection(state.displayName) {
                    SettingsControlRow(
                        label: "Enabled",
                        detail: "Allow readiness prompts through this installed CLI."
                    ) {
                        Toggle(
                            state.displayName,
                            isOn: Binding(
                                get: { model.settings.tools[state.tool].enabled },
                                set: { model.setToolEnabled(state.tool, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    SettingsDivider()
                    SettingsValueRow(label: "Status", value: state.statusText)
                    SettingsDivider()
                    SettingsValueRow(label: "Detected path", value: state.pathText, monospaced: true)
                    SettingsDivider()
                    SettingsControlRow(
                        label: "Manual path",
                        detail: "Optional override when auto-detection picks the wrong executable."
                    ) {
                        TextField(
                            "Manual path",
                            text: Binding(
                                get: { model.settings.tools[state.tool].manualPath ?? "" },
                                set: { model.setManualPath(state.tool, path: $0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .frame(width: 280)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(QWSettingsTheme.input)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(QWSettingsTheme.strongBorder, lineWidth: 1)
                        )
                    }
                    SettingsDivider()
                    SettingsControlRow(label: "Readiness test", detail: state.detailText) {
                        HStack(spacing: 8) {
                            Button {
                                model.runNow()
                            } label: {
                                Label("Test", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(QWCommandButtonStyle())
                            .disabled(!state.canTest)
                        }
                    }
                }
            }
        }
    }
}

struct ReadinessPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Window Readiness") {
            SettingsSection("Session readiness") {
                SettingsValueRow(label: "Summary", value: model.settingsState.readinessSummary)
                SettingsDivider()
                SettingsValueRow(label: "Next reset", value: model.settingsState.nextResetText)
                SettingsDivider()
                SettingsValueRow(label: "Confidence", value: model.settingsState.confidenceText)
                SettingsDivider()
                SettingsControlRow(
                    label: "Background readiness",
                    detail: "Automatic readiness pauses while this is off."
                ) {
                    Toggle(
                        "Background readiness",
                        isOn: Binding(
                            get: { !model.settings.readiness.paused },
                            set: { model.setReadinessPaused(!$0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsSection("Usage window scheduling") {
                SettingsControlRow(
                    label: "Require active use",
                    detail: "Send only when this Mac appears active."
                ) {
                    Toggle(
                        "Require active use",
                        isOn: Binding(
                            get: { model.settings.readiness.activeOnly },
                            set: { model.setActiveOnly($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsControlRow(label: "Idle threshold") {
                    Stepper(
                        "\(model.settings.readiness.idleThresholdSeconds) seconds",
                        value: Binding(
                            get: { model.settings.readiness.idleThresholdSeconds },
                            set: { model.setIdleThresholdSeconds($0) }
                        ),
                        in: 30...3_600,
                        step: 30
                    )
                    .frame(width: 190, alignment: .trailing)
                }
                SettingsDivider()
                SettingsControlRow(label: "Minimum cooldown") {
                    Stepper(
                        "\(model.settings.readiness.minimumSendCooldownMinutes) minutes",
                        value: Binding(
                            get: { model.settings.readiness.minimumSendCooldownMinutes },
                            set: { model.setMinimumSendCooldownMinutes($0) }
                        ),
                        in: 0...360,
                        step: 5
                    )
                    .frame(width: 190, alignment: .trailing)
                }
                SettingsDivider()
                SettingsControlRow(
                    label: "Reset estimation",
                    detail: "How quota window wake candidates are selected."
                ) {
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
                    .frame(width: 270, height: 30)
                }
            }

            SettingsSection("Provider status") {
                ForEach(Array(model.settingsState.providerStates.enumerated()), id: \.element.tool) { index, provider in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            StatusDot(tone: provider.statusTone)
                            Text(provider.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(provider.statusText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(QWSettingsTheme.secondaryText)
                                .lineLimit(1)
                        }
                        SettingsRow(label: "Last readiness", value: provider.lastReadinessText)
                        SettingsRow(label: "Next reset", value: provider.nextResetText)
                        SettingsRow(label: "Confidence", value: provider.confidenceText)
                        SettingsRow(label: "Source", value: provider.sourceText)
                        Text(provider.detailText)
                            .font(.system(size: 11))
                            .foregroundStyle(QWSettingsTheme.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(QWSettingsTheme.blockRow)
                    if index < model.settingsState.providerStates.count - 1 {
                        SettingsDivider()
                    }
                }
            }

            SettingsSection("Actions") {
                SettingsControlRow(
                    label: "Manual actions",
                    detail: "Run or observe readiness without waiting for the next schedule."
                ) {
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
    }
}

struct PromptPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Prompt") {
            SettingsSection("Readiness prompt") {
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
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(QWSettingsTheme.input)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(QWSettingsTheme.border, lineWidth: 1)
                    )
                    Text("Current preview: \(model.settingsState.promptPreview)")
                        .font(.caption)
                        .foregroundStyle(QWSettingsTheme.secondaryText)
                }
                .padding(14)
                .background(QWSettingsTheme.blockRow)
            }
        }
    }
}

struct LogsPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Logs") {
            SettingsSection("Run history") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Time").frame(width: 72, alignment: .leading)
                        Text("Tool").frame(width: 72, alignment: .leading)
                        Text("Status").frame(width: 120, alignment: .leading)
                        Text("Duration").frame(width: 76, alignment: .leading)
                        Text("Summary").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QWSettingsTheme.secondaryText)

                    SettingsDivider()

                    if model.settingsState.logRows.isEmpty {
                        Text("No runs yet")
                            .foregroundStyle(QWSettingsTheme.secondaryText)
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
                .padding(14)
                .background(QWSettingsTheme.blockRow)
            }
        }
    }
}

struct SettingsPaneLayout<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(QWSettingsTheme.primaryText)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(QWSettingsTheme.tertiaryText)
                }
                content
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(QWSettingsTheme.window)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QWSettingsTheme.tertiaryText)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(QWSettingsTheme.block)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(QWSettingsTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

struct SettingsStatusBanner<Action: View>: View {
    let title: String
    let detail: String
    let tone: UIStatusTone
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(alignment: .top, spacing: 10) {
                StatusDot(tone: tone)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(QWSettingsTheme.primaryText)
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(QWSettingsTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            action
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 58)
        .background(QWSettingsTheme.blockRow)
    }
}

struct SettingsControlRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let control: Control

    init(label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QWSettingsTheme.primaryText)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(QWSettingsTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
        .background(QWSettingsTheme.blockRow)
    }
}

struct SettingsValueRow: View {
    let label: String
    var detail: String?
    let value: String
    var monospaced = false

    var body: some View {
        SettingsControlRow(label: label, detail: detail) {
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .system(size: 13, weight: .semibold))
                .foregroundStyle(QWSettingsTheme.secondaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 360, alignment: .trailing)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(QWSettingsTheme.border)
            .frame(height: 1)
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(QWSettingsTheme.secondaryText)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .body)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .foregroundStyle(QWSettingsTheme.primaryText)
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
