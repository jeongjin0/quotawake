import AppKit
import QuotaWakeCore
import SwiftUI

/// Top-level popover tab: the overview or a single provider's detail.
enum PopoverTab: Equatable {
    case overview
    case provider(ToolKind)
}

/// Popover footprint: the width is fixed, the height grows to fit content (the
/// window resizes to `onContentHeightChange`). `size.height` is only the initial
/// fallback / QA canvas used before the first measurement.
enum PopoverMetrics {
    static let size = NSSize(width: 306, height: 500)
}

/// SwiftUI → AppKit channel for the popover's intrinsic content height so the
/// host window can resize to it (different tabs/states differ in height, and the
/// tallest ones used to clip the footer against a fixed frame).
struct PopoverContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct QuotaWakePopoverView: View {
    @ObservedObject var model: QuotaWakeAppModel
    @ObservedObject var presentation: PopoverPresentationState
    let openSettings: () -> Void
    var toggleReadinessPaused: () -> Void = {}
    let quit: () -> Void
    var initialTab: PopoverTab = .overview
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var selectedTab: PopoverTab?

    var body: some View {
        let state = model.popoverState
        let tab = effectiveTab(state)

        ZStack {
            VStack(alignment: .leading, spacing: 11) {
                PopoverTabBar(
                    providers: state.providerStates,
                    selection: Binding(
                        get: { tab },
                        set: { selectedTab = $0 }
                    )
                )

                switch tab {
                case .overview:
                    PopoverOverviewTab(
                        state: state,
                        openLogs: openSettings,
                        selectProvider: { selectedTab = .provider($0) }
                    )
                case .provider(let tool):
                    if let provider = state.providerStates.first(where: { $0.tool == tool }) {
                        ProviderDetailTab(
                            provider: provider,
                            activity: state.recentActivity.filter { $0.toolText == provider.displayName },
                            openLogs: openSettings
                        )
                    }
                }

                // Transient status messages replace the gate note down here instead
                // of joining the main flow, so tab content never changes height.
                HStack(alignment: .center, spacing: 8) {
                    Text(model.statusMessage ?? activityNote(state))
                        .font(.system(size: 10.5))
                        .foregroundStyle(QWTheme.popoverInkTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    StatusPill(
                        title: state.statusTone == .success ? "Watching" : state.statusTitle,
                        tone: state.statusTone
                    )
                }

                PopoverMenuFooter(
                    reload: model.observeLastResult,
                    pauseTitle: model.settings.readiness.paused ? "Resume" : "Pause",
                    pauseSystemImage: model.settings.readiness.paused ? "play.circle" : "pause.circle",
                    togglePause: toggleReadinessPaused,
                    openSettings: openSettings,
                    quit: quit
                )
            }
            .opacity(presentation.isClosing ? 0.22 : 1)

            if presentation.isClosing {
                QWTheme.popoverExitGradient
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .padding(14)
        // Fixed width, intrinsic height: the content sizes to whatever the tab
        // needs and the host window matches it (see onContentHeightChange), so no
        // state can clip the footer the way a fixed height did.
        .frame(width: PopoverMetrics.size.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PopoverContentHeightKey.self, value: geo.size.height)
            }
        )
        .background(.ultraThinMaterial)
        .background(QWTheme.glassSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(QWTheme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .light)
        .onPreferenceChange(PopoverContentHeightKey.self) { height in
            onContentHeightChange(height)
        }
    }

    /// The requested tab, falling back to the overview when the provider is not runnable.
    private func effectiveTab(_ state: PopoverUIState) -> PopoverTab {
        let requested = selectedTab ?? initialTab
        if case .provider(let tool) = requested,
           !state.providerStates.contains(where: { $0.tool == tool }) {
            return .overview
        }
        return requested
    }

    /// One global gate note in the bottom status line, driven by the active-use gate.
    /// Kept short so it never collides with the readiness pill beside it.
    private func activityNote(_ state: PopoverUIState) -> String {
        state.activityText.hasSuffix("on")
            ? "Sends while Mac is active"
            : "Sends in the background"
    }
}

final class PopoverPresentationState: ObservableObject {
    @Published private(set) var isClosing = false

    func startClosing() {
        withAnimation(.easeOut(duration: 0.12)) {
            isClosing = true
        }
    }

    func reset() {
        isClosing = false
    }
}

/// The overview's signature answer: how long until the next observed reset candidate.
struct NextResetHero: View {
    let state: PopoverUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NEXT RESET")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(QWTheme.popoverInkTertiary)

            if let countdown = state.nextResetCountdownText {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Fixed size: the countdown must render identically across
                    // states; when space runs out the subline truncates instead.
                    Text(countdown)
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(QWTheme.popoverInk)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    subline
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for a quota signal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(QWTheme.popoverInkSecondary)
                    Text("Reload to check now")
                        .font(.system(size: 10.5))
                        .foregroundStyle(QWTheme.popoverInkTertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// "Claude · 5h window · at 18:04" rendered as one quiet two-tone line.
    /// The clock is dropped for "Due now": a wall-clock time in the past only confuses.
    private var subline: some View {
        (
            Text(state.nextResetProviderText ?? "")
                .fontWeight(.semibold)
                .foregroundColor(QWTheme.popoverInkSecondary)
            + Text(sublineClockText.map { " · at \($0)" } ?? "")
                .foregroundColor(QWTheme.popoverInkTertiary)
        )
        .font(.system(size: 11))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var sublineClockText: String? {
        state.nextResetCountdownText == "Due now" ? nil : state.nextResetClockText
    }

    private var accessibilityText: String {
        guard let countdown = state.nextResetCountdownText else {
            return "Next reset: waiting for a local quota signal"
        }
        let detail = [state.nextResetProviderText, sublineClockText.map { "at \($0)" }]
            .compactMap { $0 }
            .joined(separator: ", ")
        return countdown == "Due now"
            ? "Next reset due now, \(detail)"
            : "Next reset in \(countdown), \(detail)"
    }
}

/// Readiness pill in the bottom status line: tinted capsule with a leading dot ("Watching").
struct StatusPill: View {
    let title: String
    let tone: UIStatusTone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.qwPillColor)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tone.qwPillColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone.qwPillColor.opacity(0.10)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(title)")
    }
}
