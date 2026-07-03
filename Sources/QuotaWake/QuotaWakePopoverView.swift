import AppKit
import QuotaWakeCore
import SwiftUI

struct QuotaWakePopoverView: View {
    @ObservedObject var model: QuotaWakeAppModel
    @ObservedObject var presentation: PopoverPresentationState
    let openSettings: () -> Void
    var toggleReadinessPaused: () -> Void = {}
    let quit: () -> Void

    var body: some View {
        let state = model.popoverState

        ZStack {
            VStack(alignment: .leading, spacing: 11) {
                PopoverHeader(state: state)

                NextResetHero(state: state)

                VStack(spacing: 8) {
                    ForEach(state.providerStates, id: \.tool) { provider in
                        ProviderQuotaCard(
                            provider: provider,
                            isNextDue: provider.displayNameMatchesHero(state)
                        )
                    }
                }
                .layoutPriority(1)

                if let message = model.statusMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(QWTheme.popoverInkSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                RecentActivitySection(items: state.recentActivity, openLogs: openSettings)

                Spacer(minLength: 0)

                Text(activityNote(state))
                    .font(.system(size: 10.5))
                    .foregroundStyle(QWTheme.popoverInkTertiary)

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
        .frame(width: 306, height: 580)
        .background(.ultraThinMaterial)
        .background(QWTheme.glassSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(QWTheme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .light)
    }

    /// One global gate note above the footer, driven by the active-use gate.
    private func activityNote(_ state: PopoverUIState) -> String {
        state.activityText.hasSuffix("on")
            ? "Sends only while your Mac is active"
            : "Sends in the background"
    }
}

private extension ProviderReadinessUIState {
    /// Whether this provider owns the hero countdown (drives card emphasis).
    func displayNameMatchesHero(_ state: PopoverUIState) -> Bool {
        state.nextResetProviderText?.hasPrefix(displayName) == true
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

struct PopoverHeader: View {
    let state: PopoverUIState

    var body: some View {
        HStack(spacing: 8) {
            Text("QuotaWake")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QWTheme.popoverInkSecondary)
            Spacer(minLength: 8)
            StatusPill(
                title: state.statusTone == .success ? "Watching" : state.statusTitle,
                tone: state.statusTone
            )
        }
    }
}

/// The popover's signature answer: how long until the next observed reset candidate.
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
                    Text(countdown)
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(QWTheme.popoverInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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

/// Header readiness pill: tinted capsule with a leading dot (v2 "Watching").
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
