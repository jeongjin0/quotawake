import QuotaWakeCore
import SwiftUI

struct QWPopoverMenuRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? QWTheme.glassPressed : Color.clear)
            )
    }

    private var foreground: Color {
        if !isEnabled {
            return QWTheme.secondaryText.opacity(0.65)
        }
        return destructive ? QWTheme.error : QWTheme.primaryText
    }
}

extension UIStatusTone {
    var qwStatusImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .info:
            return "clock.arrow.circlepath"
        case .neutral:
            return "circle"
        }
    }

    var qwStatusColor: Color {
        switch self {
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

extension ProviderReadinessUIState {
    var accent: Color {
        switch tool {
        case .claude:
            return QWTheme.claudeAccent
        case .codex:
            return QWTheme.codexAccent
        }
    }

    var wash: Color {
        switch tool {
        case .claude:
            return QWTheme.claudeWash
        case .codex:
            return QWTheme.codexWash
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

    var usedFraction: Double? {
        usedPercent.map { min(max($0, 0), 100) / 100 }
    }

    var quotaValueText: String {
        remainingPercent.map { "\(Self.percentText($0)) left" } ?? quotaText
    }

    var quotaUsedText: String {
        usedPercent.map { "\(Self.percentText($0)) used" } ?? "No local usage"
    }

    var quotaRemainingText: String {
        remainingPercent.map { "\(Self.percentText($0)) left" } ?? "Unknown left"
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
