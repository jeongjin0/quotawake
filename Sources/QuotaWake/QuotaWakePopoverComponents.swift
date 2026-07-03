import AppKit
import QuotaWakeCore
import SwiftUI

/// Segmented provider tab bar: Overview plus one tab per runnable provider.
struct PopoverTabBar: View {
    let providers: [ProviderReadinessUIState]
    @Binding var selection: PopoverTab

    var body: some View {
        HStack(spacing: 4) {
            tabItem(
                title: "Overview",
                isSelected: selection == .overview,
                action: { selection = .overview }
            ) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
            }

            ForEach(providers, id: \.tool) { provider in
                tabItem(
                    title: provider.displayName,
                    isSelected: selection == .provider(provider.tool),
                    action: { selection = .provider(provider.tool) }
                ) {
                    ProviderIdentityMark(provider: provider, diameter: 15, glyphSize: 9)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider tabs")
    }

    private func tabItem(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon()
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? QWTheme.popoverInk : QWTheme.popoverInkSecondary)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? QWTheme.cardFill.opacity(0.85) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? QWTheme.cardStroke : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Overview tab: hero countdown, one compact row per provider, recent activity.
struct PopoverOverviewTab: View {
    let state: PopoverUIState
    let openLogs: () -> Void
    let selectProvider: (ToolKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            NextResetHero(state: state)

            if state.providerStates.isEmpty {
                Text("No runnable tools. Check CLI paths in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(QWTheme.popoverInkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.providerStates.enumerated()), id: \.element.tool) { index, provider in
                        if index > 0 {
                            Rectangle()
                                .fill(QWTheme.popoverHairline)
                                .frame(height: 1)
                        }
                        ProviderSummaryRow(provider: provider) {
                            selectProvider(provider.tool)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(QWTheme.cardFill.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(QWTheme.cardStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            RecentActivitySection(items: state.recentActivity, openLogs: openLogs)
        }
    }
}

/// One compact provider line on the overview; tapping opens the provider tab.
struct ProviderSummaryRow: View {
    let provider: ProviderReadinessUIState
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProviderIdentityMark(provider: provider, diameter: 22, glyphSize: 13)
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(QWTheme.popoverInk)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    summaryValue
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(QWTheme.popoverInkTertiary)
                }
                QuotaBar(
                    fraction: provider.remainingFraction,
                    fill: provider.accent,
                    known: provider.hasFiveHourSignal,
                    height: 4
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.displayName): \(accessibilitySummary). Opens \(provider.displayName) detail.")
    }

    /// "58% left · 45m" — 5h remaining plus its reset countdown at a glance.
    private var summaryValue: some View {
        (
            Text(provider.hasFiveHourSignal ? provider.fiveHourValueText : "No signal")
                .fontWeight(.semibold)
                .foregroundColor(provider.hasFiveHourSignal ? QWTheme.popoverInk : QWTheme.popoverInkSecondary)
            + Text(summaryCountdownSuffix)
                .foregroundColor(QWTheme.popoverInkSecondary)
        )
        .font(.system(size: 11.5))
        .lineLimit(1)
    }

    private var summaryCountdownSuffix: String {
        switch provider.resetCountdownText {
        case "Unknown", "Not used":
            return ""
        case "Due now":
            return " · due now"
        default:
            return " · \(provider.resetCountdownText)"
        }
    }

    private var accessibilitySummary: String {
        provider.hasFiveHourSignal
            ? "\(provider.fiveHourValueText)\(summaryCountdownSuffix)"
            : "No local quota signal yet"
    }
}

/// Provider tab: full quota detail for the selected provider only.
struct ProviderDetailTab: View {
    let provider: ProviderReadinessUIState
    let activity: [LogRowUIState]
    let openLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ProviderIdentityMark(provider: provider, diameter: 28, glyphSize: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(QWTheme.popoverInk)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(provider.statusTone.qwPillColor)
                            .frame(width: 5, height: 5)
                        Text(provider.statusText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(QWTheme.popoverInkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 11) {
                QuotaWindowSection(
                    title: "5h window",
                    valueText: provider.fiveHourValueText,
                    valueKnown: provider.hasFiveHourSignal,
                    fraction: provider.remainingFraction,
                    fill: provider.accent,
                    known: provider.hasFiveHourSignal,
                    footnote: provider.fiveHourResetFootnote,
                    detailNote: provider.hasFiveHourSignal ? nil : "No local quota signal yet",
                    prominent: true
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
                        : nil,
                    prominent: true
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(QWTheme.cardFill.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(QWTheme.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                ProviderMetaRow(label: "Source", value: provider.sourceText)
                ProviderMetaRow(label: "Confidence", value: provider.confidenceText)
                ProviderMetaRow(label: "Last run", value: provider.lastReadinessText)
            }

            RecentActivitySection(items: activity, openLogs: openLogs)
                .padding(.top, 5)
        }
    }
}

/// Quiet label/value line for provider diagnostics (source, confidence, last run).
struct ProviderMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(QWTheme.popoverInkTertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(QWTheme.popoverInkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
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
    /// Provider-tab sections read larger: bigger value, taller bar.
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QWTheme.popoverInkSecondary)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.system(size: prominent ? 14 : 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(valueKnown ? QWTheme.popoverInk : QWTheme.popoverInkSecondary)
                    .lineLimit(1)
            }
            QuotaBar(fraction: fraction, fill: fill, known: known, height: prominent ? 6 : 5)
            if footnote != nil || detailNote != nil {
                detailText
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
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
        } else if let footnote {
            Text(footnote)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(QWTheme.popoverInkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let detailNote {
            Text(detailNote)
                .font(.system(size: 11, weight: .medium))
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
            context.stroke(path, with: .color(Color.black.opacity(0.12)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

struct ProviderIdentityMark: View {
    let provider: ProviderReadinessUIState
    var diameter: CGFloat = 26
    var glyphSize: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(provider.accent)
            if let image = ProviderBrandIcon.image(for: provider.tool) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: glyphSize, height: glyphSize)
                    .accessibilityHidden(true)
            } else {
                Text(provider.monogram)
                    .font(.system(size: glyphSize * 0.7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
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

            Group {
                if items.isEmpty {
                    Text("No readiness runs yet")
                        .font(.system(size: 11))
                        .foregroundStyle(QWTheme.popoverInkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, row in
                            if index > 0 {
                                Rectangle()
                                    .fill(QWTheme.popoverHairline)
                                    .frame(height: 1)
                            }
                            ActivityRow(row: row)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(QWTheme.cardFill.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(QWTheme.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
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

            HStack(spacing: 0) {
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
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
    }
}
