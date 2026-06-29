import AppKit
import QuotaWakeCore
import SwiftUI

struct QuotaWakePopoverView: View {
    @ObservedObject var model: QuotaWakeAppModel
    let openSettings: () -> Void
    let quit: () -> Void
    var showAbout: () -> Void = {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        let state = model.popoverState

        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(state: state)

            VStack(spacing: 8) {
                ForEach(state.providerStates, id: \.tool) { provider in
                    ProviderQuotaCard(provider: provider)
                }
            }
            .layoutPriority(1)

            if let message = model.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(QWTheme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    model.runNow()
                } label: {
                    Label(state.runNowTitle == "Sending..." ? state.runNowTitle : "Send readiness now", systemImage: "paperplane")
                }
                .disabled(!state.canRunNow)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(QWCommandButtonStyle())

                Button {
                    model.observeLastResult()
                } label: {
                    Label("Refresh quota", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(QWCommandButtonStyle())

                Spacer()
            }

            PopoverMenuFooter(
                openSettings: openSettings,
                showAbout: showAbout,
                quit: quit
            )
        }
        .padding(14)
        .frame(width: 360, height: 580)
        .background(.regularMaterial)
        .background(QWTheme.glassSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(QWTheme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(QWTheme.primaryText)
        .environment(\.colorScheme, .light)
    }
}

struct PopoverHeader: View {
    let state: PopoverUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("QuotaWake")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Label(state.statusTitle, systemImage: state.statusTone.qwStatusImage)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.statusTone.qwStatusColor)
                    .lineLimit(1)
            }

            Text(state.statusDetail)
                .font(.system(size: 12))
                .foregroundStyle(QWTheme.secondaryText)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Text(state.readinessSummaryText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(QWTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

}
