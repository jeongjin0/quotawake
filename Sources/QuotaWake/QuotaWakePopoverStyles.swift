import QuotaWakeCore
import SwiftUI

/// Horizontal footer menu item (Reload / Pause / Settings / Quit).
struct QWFooterChipStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? QWTheme.glassPressed : Color.clear)
            )
    }

    private var foreground: Color {
        if !isEnabled {
            return Color.black.opacity(0.3)
        }
        return destructive ? QWTheme.pillRed : Color.black.opacity(0.62)
    }
}

/// Small inline action chip used inside a card (v2 "Observe").
struct QWInlineChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(isEnabled ? QWTheme.pillBlue : Color.black.opacity(0.3))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(QWTheme.pillBlue.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
    }
}

extension UIStatusTone {
    /// Redesign v2 chip/pill color for the popover's fixed light mode.
    var qwPillColor: Color {
        switch self {
        case .success:
            return QWTheme.pillGreen
        case .info:
            return QWTheme.pillBlue
        case .warning:
            return QWTheme.pillOrange
        case .error:
            return QWTheme.pillRed
        case .neutral:
            return QWTheme.popoverInkSecondary
        }
    }
}

extension ProviderReadinessUIState {
    var accent: Color {
        switch tool {
        case .claude:
            return QWTheme.claudeAccent
        case .codex:
            return QWTheme.codexAccent
        }
    }

    var monogram: String {
        switch tool {
        case .claude:
            return "C"
        case .codex:
            return "X"
        }
    }

    /// Whether the 5h window has a usable local quota signal (drives striped vs filled bar).
    var hasFiveHourSignal: Bool {
        usedPercent != nil || remainingPercent != nil
    }

    /// v2 fills the quota bar by remaining capacity (a fuel gauge), not by usage.
    var remainingFraction: Double? {
        if let remainingPercent { return min(max(remainingPercent, 0), 100) / 100 }
        if let usedPercent { return min(max(100 - usedPercent, 0), 100) / 100 }
        return nil
    }

    var weeklyRemainingFraction: Double? {
        if let weeklyRemainingPercent { return min(max(weeklyRemainingPercent, 0), 100) / 100 }
        if let weeklyUsedPercent { return min(max(100 - weeklyUsedPercent, 0), 100) / 100 }
        return nil
    }

    /// "58% left" — the compact value shown in the 5h quota-window row.
    var fiveHourValueText: String {
        if let remainingPercent { return "\(Self.percentText(remainingPercent)) left" }
        if let usedPercent { return "\(Self.percentText(100 - usedPercent)) left" }
        return "Unknown"
    }

    /// The 5h/window reset footnote shown inside the 5h quota-window section.
    var fiveHourResetFootnote: String? {
        switch resetCountdownText {
        case "Unknown", "Not used":
            return nil
        case "Due now":
            return "Reset due"
        default:
            return "Resets in \(resetCountdownText)"
        }
    }

    private static func percentText(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        if clamped.rounded() == clamped {
            return "\(Int(clamped))%"
        }
        return String(format: "%.1f%%", clamped)
    }
}

extension ToolKind {
    var providerIconResourceName: String {
        switch self {
        case .claude:
            return "ProviderIcon-claude"
        case .codex:
            return "ProviderIcon-codex"
        }
    }
}
