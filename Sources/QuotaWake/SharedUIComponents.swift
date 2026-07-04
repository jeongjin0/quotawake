import AppKit
import QuotaWakeCore
import SwiftUI

// Adaptive control palette consumed by the shared first-run components below.
fileprivate enum QWSettingsTheme {
    static let strongBorder = Color(nsColor: .separatorColor).opacity(0.85)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let control = Color(nsColor: .controlBackgroundColor)
    static let controlPressed = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let accent = Color.accentColor
    static let accentPressed = Color(nsColor: .selectedContentBackgroundColor)
    static let accentForeground = Color(nsColor: .alternateSelectedControlTextColor)
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
            return "Providers"
        case .windowReadiness:
            return "Readiness"
        case .testRun:
            return "Test"
        case .complete:
            return "Done"
        }
    }
}
