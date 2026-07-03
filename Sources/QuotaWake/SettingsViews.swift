import AppKit
import QuotaWakeCore
import SwiftUI

enum QWTheme {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let glassSurface = Color(nsColor: .windowBackgroundColor).opacity(0.34)
    static let glassPressed = Color(nsColor: .controlAccentColor).opacity(0.10)
    static let surfaceSubtle = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let glassBorder = Color(nsColor: .separatorColor).opacity(0.42)
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
    static let cardStroke = Color.black.opacity(0.075)
    static let popoverInk = Color.black.opacity(0.86)
    static let popoverInkSecondary = Color.black.opacity(0.5)
    static let popoverInkTertiary = Color.black.opacity(0.4)
    static let popoverHairline = Color.black.opacity(0.08)
    static let popoverExitGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.46),
            Color.white.opacity(0.20),
            Color.white.opacity(0.04)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

enum QWSettingsTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let sidebarOuter = Color(nsColor: .underPageBackgroundColor)
    static let block = Color(nsColor: .controlBackgroundColor)
    static let blockRow = Color(nsColor: .windowBackgroundColor)
    static let blockRowRaised = Color(nsColor: .controlBackgroundColor)
    static let panel = block
    static let panelRaised = blockRowRaised
    static let rowPressed = Color(nsColor: .controlAccentColor).opacity(0.12)
    static let sidebarSelected = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let strongBorder = Color(nsColor: .separatorColor).opacity(0.85)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let control = Color(nsColor: .controlBackgroundColor)
    static let controlPressed = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let input = Color(nsColor: .textBackgroundColor)
    static let accent = Color.accentColor
    static let accentPressed = Color(nsColor: .selectedContentBackgroundColor)
    static let accentForeground = Color(nsColor: .alternateSelectedControlTextColor)
}

enum PaneRowControlPlacement {
    case trailing
    case fullWidth
    case below
}

enum PaneRowMetrics {
    static let labelWidth: CGFloat = 240
    static let rowMinHeight: CGFloat = 52
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 10
    static let labelControlGap: CGFloat = 16
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
            return QWSettingsTheme.tertiaryText
        }
        if colorScheme == .dark {
            return prominent ? QWSettingsTheme.accentForeground : QWSettingsTheme.primaryText
        }
        return prominent ? QWTheme.accentForeground : QWTheme.primaryText
    }

    private func background(configuration: Configuration) -> Color {
        if !isEnabled {
            return QWSettingsTheme.control.opacity(0.55)
        }
        if prominent {
            if colorScheme == .dark {
                return configuration.isPressed ? QWSettingsTheme.accentPressed : QWSettingsTheme.accent
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

            Divider()

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
        .frame(minWidth: 720, minHeight: 520)
        .background(QWSettingsTheme.window)
        .foregroundStyle(QWSettingsTheme.primaryText)
        .tint(QWSettingsTheme.accent)
        .groupBoxStyle(QWGroupBoxStyle())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPaneID.allCases, id: \.self) { pane in
                    Button {
                        model.selectedPane = pane
                    } label: {
                        SidebarNavigationItem(pane: pane)
                    }
                    .buttonStyle(QWSidebarButtonStyle(selected: (model.selectedPane ?? .general) == pane))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: 212)
        .background(QWSettingsTheme.sidebarOuter)
    }
}

struct SidebarNavigationItem: View {
    let pane: SettingsPaneID

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, alignment: .center)
            Text(pane.title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
    }
}

struct GeneralPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "General") {
            PaneGroup("Status") {
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

            PaneGroup("Application") {
                PaneValueRow(
                    label: "App",
                    detail: "Installed QuotaWake build.",
                    value: model.settingsState.appVersionText
                )
                PaneSeparator()
                PaneControlRow(
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
                PaneSeparator()
                PaneControlRow(
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
                PaneSeparator()
                PaneControlRow(
                    label: "Manual updates",
                    detail: "Check the release page for a signed DMG.",
                    placement: .below
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
                    PaneSeparator()
                    PaneControlRow(
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
                PaneGroup(state.displayName) {
                    PaneControlRow(
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
                    PaneSeparator()
                    PaneValueRow(label: "Status", value: state.statusText)
                    PaneSeparator()
                    PaneValueRow(label: "Detected path", value: state.pathText, monospaced: true)
                    PaneSeparator()
                    PaneControlRow(
                        label: "Manual path",
                        detail: "Optional override when auto-detection picks the wrong executable.",
                        placement: .below
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
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(QWSettingsTheme.input)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(QWSettingsTheme.strongBorder, lineWidth: 1)
                        )
                    }
                    PaneSeparator()
                    PaneControlRow(label: "Readiness test", detail: state.detailText) {
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
            PaneGroup("Session readiness") {
                PaneValueRow(label: "Summary", value: model.settingsState.readinessSummary)
                PaneSeparator()
                PaneValueRow(label: "Next reset", value: model.settingsState.nextResetText)
                PaneSeparator()
                PaneValueRow(label: "Confidence", value: model.settingsState.confidenceText)
                PaneSeparator()
                PaneControlRow(
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

            PaneGroup("Usage window scheduling") {
                PaneControlRow(
                    label: "Reset estimation",
                    detail: "How quota window wake candidates are selected.",
                    placement: .below
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
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 420, alignment: .leading)
                }
                PaneSeparator()
                PaneControlRow(
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
                PaneSeparator()
                PaneControlRow(label: "Idle threshold") {
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
                PaneSeparator()
                PaneControlRow(label: "Minimum cooldown") {
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
            }

            PaneGroup("Provider status") {
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
                        PaneInlineValue(label: "Last readiness", value: provider.lastReadinessText)
                        PaneInlineValue(label: "Next reset", value: provider.nextResetText)
                        PaneInlineValue(label: "Confidence", value: provider.confidenceText)
                        PaneInlineValue(label: "Source", value: provider.sourceText)
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
                        PaneSeparator()
                    }
                }
            }

            PaneGroup("Actions") {
                PaneControlRow(
                    label: "Manual actions",
                    detail: "Run readiness now without waiting for the next schedule.",
                    placement: .fullWidth
                ) {
                    readinessNowButton
                }
            }
        }
    }

    private var readinessNowButton: some View {
        Button {
            model.runNow()
        } label: {
            Label("Send Readiness Now", systemImage: "paperplane")
        }
        .buttonStyle(QWCommandButtonStyle(prominent: true))
        .disabled(!model.popoverState.canRunNow)
    }
}

struct PromptPane: View {
    @ObservedObject var model: QuotaWakeAppModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        SettingsPaneLayout(title: "Prompt") {
            PaneGroup("Readiness prompt") {
                PaneControlRow(
                    label: "Prompt text",
                    detail: "Used for readiness prompts sent through enabled installed CLIs.",
                    placement: .below
                ) {
                    TextEditor(
                        text: Binding(
                            get: { model.settings.prompt },
                            set: { model.setPrompt($0) }
                        )
                    )
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 168)
                    .background(PaneInputBackground(isFocused: promptFocused))
                    .focused($promptFocused)
                    .accessibilityLabel("Readiness prompt")
                }
                PaneSeparator()
                PaneControlRow(
                    label: "Preview",
                    detail: "Compact surfaces use the same middle-truncated preview.",
                    placement: .below
                ) {
                    Text(model.settingsState.promptPreview.isEmpty ? "No prompt preview" : model.settingsState.promptPreview)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(QWSettingsTheme.secondaryText)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct LogsPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        SettingsPaneLayout(title: "Logs") {
            PaneGroup("Run history") {
                PaneControlRow(
                    label: "Entries",
                    detail: "Latest session readiness runs, newest first.",
                    placement: .below
                ) {
                    LogTable(rows: model.settingsState.logRows)
                }
            }
        }
    }
}

struct PaneInputBackground: View {
    let isFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(QWSettingsTheme.input)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? QWSettingsTheme.accent : QWSettingsTheme.border, lineWidth: isFocused ? 2 : 1)
            )
    }
}

private enum LogTableMetrics {
    static let timeWidth: CGFloat = 76
    static let toolWidth: CGFloat = 66
    static let statusWidth: CGFloat = 112
    static let durationWidth: CGFloat = 78
    static let exitCodeWidth: CGFloat = 58
    static let summaryMinWidth: CGFloat = 240
    static let columnSpacing: CGFloat = 12
    static let minimumWidth: CGFloat = (
        timeWidth
        + toolWidth
        + statusWidth
        + durationWidth
        + exitCodeWidth
        + summaryMinWidth
        + (columnSpacing * 5)
    )
}

struct LogTable: View {
    let rows: [LogRowUIState]

    var body: some View {
        GeometryReader { proxy in
            let tableWidth = max(proxy.size.width, LogTableMetrics.minimumWidth)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    LogTableHeader()
                    tableSeparator
                    if rows.isEmpty {
                        LogTableEmptyState()
                            .frame(width: tableWidth, alignment: .leading)
                            .frame(minHeight: 96, alignment: .leading)
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                    LogTableRow(row: row, isLatest: index == 0)
                                    if index < rows.count - 1 {
                                        tableSeparator
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: tableWidth, alignment: .leading)
            }
        }
        .frame(minHeight: tableHeight, maxHeight: tableHeight)
        .background(QWSettingsTheme.blockRow)
    }

    private var tableHeight: CGFloat {
        if rows.isEmpty {
            return 138
        }
        return min(342, CGFloat(rows.count) * 48 + 36)
    }

    private var tableSeparator: some View {
        Rectangle()
            .fill(QWSettingsTheme.border)
            .frame(height: 1)
    }
}

struct LogTableHeader: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LogTableMetrics.columnSpacing) {
            LogHeaderCell("Time", width: LogTableMetrics.timeWidth)
            LogHeaderCell("Tool", width: LogTableMetrics.toolWidth)
            LogHeaderCell("Status", width: LogTableMetrics.statusWidth)
            LogHeaderCell("Duration", width: LogTableMetrics.durationWidth)
            LogHeaderCell("Exit", width: LogTableMetrics.exitCodeWidth)
            Text("Summary")
                .frame(minWidth: LogTableMetrics.summaryMinWidth, maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(QWSettingsTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(QWSettingsTheme.blockRowRaised)
    }
}

struct LogHeaderCell: View {
    let title: String
    let width: CGFloat

    init(_ title: String, width: CGFloat) {
        self.title = title
        self.width = width
    }

    var body: some View {
        Text(title)
            .frame(width: width, alignment: .leading)
    }
}

struct LogTableRow: View {
    let row: LogRowUIState
    let isLatest: Bool

    var body: some View {
        HStack(alignment: .top, spacing: LogTableMetrics.columnSpacing) {
            LogCell(row.timeText, width: LogTableMetrics.timeWidth, monospaced: true)
            LogCell(row.toolText, width: LogTableMetrics.toolWidth)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusDot(tone: row.tone)
                    .padding(.top, 3)
                Text(row.statusText)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(width: LogTableMetrics.statusWidth, alignment: .leading)
            LogCell(row.durationText, width: LogTableMetrics.durationWidth, monospaced: true)
            LogCell(row.exitCodeText, width: LogTableMetrics.exitCodeWidth, monospaced: true)
            Text(row.summaryText.isEmpty ? "No summary" : row.summaryText)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(minWidth: LogTableMetrics.summaryMinWidth, maxWidth: .infinity, alignment: .leading)
                .help(row.summaryText)
        }
        .font(.system(size: 11))
        .foregroundStyle(QWSettingsTheme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isLatest ? QWSettingsTheme.sidebarSelected.opacity(0.48) : QWSettingsTheme.blockRow)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(row.timeText), \(row.toolText), \(row.statusText), duration \(row.durationText), exit \(row.exitCodeText), \(row.summaryText)"
    }
}

struct LogCell: View {
    let value: String
    let width: CGFloat
    var monospaced = false

    init(_ value: String, width: CGFloat, monospaced: Bool = false) {
        self.value = value
        self.width = width
        self.monospaced = monospaced
    }

    var body: some View {
        Text(value)
            .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
            .help(value)
    }
}

struct LogTableEmptyState: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(QWSettingsTheme.tertiaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text("No readiness runs yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(QWSettingsTheme.primaryText)
                Text("New local run results will appear here after a readiness check.")
                    .font(.system(size: 11))
                    .foregroundStyle(QWSettingsTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
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

struct PaneGroup<Content: View>: View {
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
            .background(QWSettingsTheme.block)
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

struct PaneControlRow<Control: View>: View {
    let label: String
    var detail: String?
    var placement: PaneRowControlPlacement
    @ViewBuilder let control: Control

    init(
        label: String,
        detail: String? = nil,
        placement: PaneRowControlPlacement = .trailing,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.detail = detail
        self.placement = placement
        self.control = control()
    }

    var body: some View {
        Group {
            switch placement {
            case .trailing:
                trailingRow(controlAlignment: .trailing)
            case .fullWidth:
                trailingRow(controlAlignment: .leading)
            case .below:
                belowRow
            }
        }
        .padding(.horizontal, PaneRowMetrics.rowHorizontalPadding)
        .padding(.vertical, PaneRowMetrics.rowVerticalPadding)
        .frame(minHeight: PaneRowMetrics.rowMinHeight)
        .background(QWSettingsTheme.blockRow)
    }

    private func trailingRow(controlAlignment: Alignment) -> some View {
        HStack(alignment: .center, spacing: PaneRowMetrics.labelControlGap) {
            labelStack
                .frame(width: PaneRowMetrics.labelWidth, alignment: .leading)
                .layoutPriority(1)
            control
                .frame(maxWidth: .infinity, alignment: controlAlignment)
                .layoutPriority(2)
        }
    }

    private var belowRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            labelStack
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var labelStack: some View {
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
    }
}

struct PaneValueRow: View {
    let label: String
    var detail: String?
    let value: String
    var monospaced = false

    var body: some View {
        PaneControlRow(label: label, detail: detail) {
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .system(size: 13, weight: .semibold))
                .foregroundStyle(QWSettingsTheme.secondaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .help(value)
        }
    }
}

struct PaneSeparator: View {
    var body: some View {
        Rectangle()
            .fill(QWSettingsTheme.border)
            .frame(height: 1)
            .padding(.leading, PaneRowMetrics.rowHorizontalPadding)
    }
}

struct PaneInlineValue: View {
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

typealias SettingsRow = PaneInlineValue

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
