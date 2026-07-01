import AppKit
import QuotaWakeCore
import SwiftUI

struct ProviderQuotaCard: View {
    let provider: ProviderReadinessUIState
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
                Spacer(minLength: 6)
            }

            QuotaWindowSection(
                title: "5h window",
                valueText: provider.fiveHourValueText,
                valueKnown: provider.hasFiveHourSignal,
                fraction: provider.remainingFraction,
                fill: provider.accent,
                known: provider.hasFiveHourSignal,
                footnote: provider.fiveHourResetFootnote,
                detailNote: provider.hasFiveHourSignal ? activityNote : "No local quota signal yet",
                actionTitle: provider.hasFiveHourSignal ? nil : "Observe",
                onAction: onObserve
            )

            QuotaWindowSection(
                title: "Weekly limit",
                valueText: provider.weeklyValueText,
                valueKnown: provider.hasWeeklyData,
                fraction: provider.weeklyRemainingFraction,
                fill: provider.accent,
                known: provider.hasWeeklyData,
                footnote: provider.hasWeeklyData && provider.weeklyResetCountdownText != "Unknown"
                    ? "Resets in \(provider.weeklyResetCountdownText)"
                    : nil
            )
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QWTheme.cardFill.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(QWTheme.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Uniform quota-window readout used for both 5h and weekly windows.
struct QuotaWindowSection: View {
    let title: String
    let valueText: String
    let valueKnown: Bool
    let fraction: Double?
    let fill: Color
    let known: Bool
    var footnote: String?
    var detailNote: String?
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QWTheme.popoverInkSecondary)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(valueKnown ? QWTheme.popoverInk : QWTheme.popoverInkSecondary)
                    .lineLimit(1)
            }
            QuotaBar(fraction: fraction, fill: fill, known: known)
            if footnote != nil || detailNote != nil || actionTitle != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    detailText
                    Spacer(minLength: 0)
                    if let actionTitle, let onAction {
                        Button(action: onAction) {
                            Text(actionTitle)
                        }
                        .buttonStyle(QWInlineChipButtonStyle())
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var detailText: some View {
        if let footnote, let detailNote {
            (
                Text(footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(QWTheme.popoverInkSecondary)
                + Text(" · \(detailNote)")
                    .foregroundColor(QWTheme.popoverInkTertiary)
            )
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
        } else if let footnote {
            Text(footnote)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(QWTheme.popoverInkTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let detailNote {
            Text(detailNote)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(QWTheme.popoverInkTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var accessibilityValue: String {
        let details = [footnote, detailNote].compactMap { $0 }
        if !details.isEmpty {
            return "\(valueText), \(details.joined(separator: ", "))"
        }
        return valueText
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
        guard let url = resourceURL(for: tool),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        cache[tool] = image
        return image
    }

    private static func resourceURL(for tool: ToolKind) -> URL? {
        if let bundled = Bundle.main.url(forResource: tool.providerIconResourceName, withExtension: "svg") {
            return bundled
        }

        let fileManager = FileManager.default
        let resourceName = "\(tool.providerIconResourceName).svg"
        var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(resourceName, isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
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

/// v2 horizontal footer: Reload · Pause/Resume · Settings … Quit.
struct PopoverMenuFooter: View {
    let reload: () -> Void
    let pauseTitle: String
    let pauseSystemImage: String
    let togglePause: () -> Void
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

                Button(action: togglePause) {
                    menuLabel(pauseTitle, systemImage: pauseSystemImage)
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
