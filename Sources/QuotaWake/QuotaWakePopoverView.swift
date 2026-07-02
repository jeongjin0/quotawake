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
            VStack(alignment: .leading, spacing: 13) {
                PopoverHeader(state: state)

                VStack(spacing: 9) {
                    ForEach(state.providerStates, id: \.tool) { provider in
                        ProviderQuotaCard(
                            provider: provider,
                            activityNote: activityNote(state),
                            onObserve: model.observeLastResult
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

    /// The trailing note on each card's 5h summary line, driven by the active-use gate.
    private func activityNote(_ state: PopoverUIState) -> String {
        state.activityText.hasSuffix("on")
            ? "sends only while Mac is active"
            : "sends in the background"
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(QWTheme.popoverInk)
            Spacer(minLength: 8)
            StatusPill(
                title: state.statusTone == .success ? "Watching" : state.statusTitle,
                tone: state.statusTone
            )
        }
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
