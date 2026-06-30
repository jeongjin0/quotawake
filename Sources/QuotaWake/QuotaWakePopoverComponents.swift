import AppKit
import QuotaWakeCore
import SwiftUI

struct ProviderQuotaCard: View {
    let provider: ProviderReadinessUIState
    var isNextDue: Bool = false
    var activityNote: String = ""
    var onObserve: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProviderIdentityMark(provider: provider)
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(QWTheme.popoverInk)
                    .lineLimit(1)
                StatusChip(text: provider.shortStatusLabel, tone: provider.statusTone)
                Spacer(minLength: 6)
                if isNextDue {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(provider.accent))
                        .accessibilityLabel("Next due")
                }
                Text(provider.resetCountdownDisplay)
                    .font(.system(size: 21, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(provider.resetCountdownDisplay == "—" ? QWTheme.popoverInk.opacity(0.28) : QWTheme.popoverInk)
                    .lineLimit(1)
                    .fixedSize()
            }

            QuotaBar(fraction: provider.remainingFraction, fill: provider.accent, known: provider.hasFiveHourSignal)

            FiveHourSummaryLine(provider: provider, note: activityNote, onObserve: onObserve)

            Rectangle()
                .fill(QWTheme.popoverHairline)
                .frame(height: 1)
                .padding(.top, 1)

            WeeklyQuotaRow(provider: provider)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QWTheme.cardFill.opacity(isNextDue ? 0.55 : 0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(QWTheme.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Small tinted status tag (v2: "Observed" green / "Unknown" orange).
struct StatusChip: View {
    let text: String
    let tone: UIStatusTone

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tone.qwPillColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(tone.qwPillColor.opacity(0.12)))
    }
}

/// The line beneath the 5h bar: "58% quota left · sends only while Mac is active",
/// or an unknown state with an inline Observe action.
struct FiveHourSummaryLine: View {
    let provider: ProviderReadinessUIState
    var note: String = ""
    var onObserve: (() -> Void)?

    var body: some View {
        if provider.hasFiveHourSignal {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.fiveHourLeftText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(QWTheme.popoverInk)
                if !note.isEmpty {
                    Text("· \(note)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(QWTheme.popoverInkTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 8) {
                Text("No local quota signal yet")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(QWTheme.popoverInkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if let onObserve {
                    Button(action: onObserve) {
                        Text("Observe")
                    }
                    .buttonStyle(QWInlineChipButtonStyle())
                }
            }
        }
    }
}

/// Secondary weekly limit readout kept at the bottom of each provider card.
struct WeeklyQuotaRow: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Weekly limit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QWTheme.popoverInkSecondary)
                Spacer(minLength: 8)
                Text(provider.weeklyValueText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(provider.hasWeeklyData ? QWTheme.popoverInk : QWTheme.popoverInkSecondary)
                    .lineLimit(1)
            }
            QuotaBar(
                fraction: provider.weeklyRemainingFraction,
                fill: provider.accent.opacity(0.55),
                known: provider.hasWeeklyData,
                height: 4
            )
            if provider.hasWeeklyData, provider.weeklyResetCountdownText != "Unknown" {
                Text("Resets in \(provider.weeklyResetCountdownText)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(QWTheme.popoverInkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName) weekly limit")
        .accessibilityValue(provider.hasWeeklyData ? "\(provider.weeklyValueText), resets in \(provider.weeklyResetCountdownText)" : "Unknown")
    }
}

/// A thin quota bar. When the signal is unknown it renders a diagonal striped placeholder.
struct QuotaBar: View {
    let fraction: Double?
    var fill: Color
    var known: Bool = true
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if known {
                    Capsule().fill(Color.black.opacity(0.09))
                    if let fraction, fraction > 0 {
                        Capsule()
                            .fill(fill)
                            .frame(width: max(3, width * min(fraction, 1)))
                    }
                } else {
                    StripedTrack()
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
    }
}

/// Diagonal hatch fill used for an unknown quota window (v2 striped track).
struct StripedTrack: View {
    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.black.opacity(0.06))
            )
            let spacing: CGFloat = 8
            var x: CGFloat = -size.height
            var path = Path()
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Color.black.opacity(0.16)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

struct ProviderIdentityMark: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        ZStack {
            Circle()
                .fill(provider.accent)
            if let image = ProviderBrandIcon.image(for: provider.tool) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            } else {
                Text(provider.monogram)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("\(provider.displayName) identity")
    }
}

@MainActor
private enum ProviderBrandIcon {
    private static var cache: [ToolKind: NSImage] = [:]

    static func image(for tool: ToolKind) -> NSImage? {
        if let cached = cache[tool] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: tool.providerIconResourceName, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        cache[tool] = image
        return image
    }
}

/// Compact log feed for the most recent readiness runs (v2 RECENT ACTIVITY).
struct RecentActivitySection: View {
    let items: [LogRowUIState]
    let openLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(QWTheme.popoverInkTertiary)
                Spacer(minLength: 0)
                Button(action: openLogs) {
                    Text("All logs")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(QWTheme.pillBlue)
                }
                .buttonStyle(.plain)
            }

            if items.isEmpty {
                Text("No readiness runs yet")
                    .font(.system(size: 11))
                    .foregroundStyle(QWTheme.popoverInkSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, row in
                        ActivityRow(row: row)
                    }
                }
            }
        }
    }
}

struct ActivityRow: View {
    let row: LogRowUIState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(row.tone == .success ? QWTheme.pillGreen : (row.tone == .warning ? QWTheme.popoverInkTertiary : row.tone.qwPillColor))
                .frame(width: 6, height: 6)
            Text(String(row.timeText.prefix(5)))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(QWTheme.popoverInkTertiary)
                .frame(width: 42, alignment: .leading)
            Text(row.toolText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(QWTheme.popoverInk)
            Text(row.statusText)
                .font(.system(size: 11))
                .foregroundStyle(QWTheme.popoverInkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// v2 horizontal footer: Reload · Settings … Quit.
struct PopoverMenuFooter: View {
    let reload: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(QWTheme.popoverHairline)
                .frame(height: 1)

            HStack(spacing: 2) {
                Button(action: reload) {
                    menuLabel("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(QWFooterChipStyle())

                Button(action: openSettings) {
                    menuLabel("Settings", systemImage: "gearshape")
                }
                .buttonStyle(QWFooterChipStyle())

                Spacer(minLength: 0)

                Button(action: quit) {
                    menuLabel("Quit", systemImage: "power")
                }
                .buttonStyle(QWFooterChipStyle(destructive: true))
            }
        }
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
    }
}
