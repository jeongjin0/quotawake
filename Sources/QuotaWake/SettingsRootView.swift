import QuotaWakeCore
import SwiftUI

extension SettingsPaneID {
    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .tools:
            return "terminal"
        case .readiness:
            return "clock.badge.checkmark"
        case .prompt:
            return "text.bubble"
        case .logs:
            return "list.bullet.rectangle"
        }
    }
}

struct QuotaWakeSettingsView: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        HStack(spacing: 0) {
            List(selection: selectionBinding) {
                ForEach(SettingsPaneID.allCases, id: \.self) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 215)

            Divider()

            detail(for: model.selectedPane ?? .general)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, idealWidth: 980, minHeight: 520, idealHeight: 680)
    }

    // Selection stays non-nil so keyboard deselection can't blank the detail pane.
    private var selectionBinding: Binding<SettingsPaneID?> {
        Binding(
            get: { model.selectedPane ?? .general },
            set: { model.selectedPane = $0 ?? model.selectedPane ?? .general }
        )
    }

    @ViewBuilder
    private func detail(for pane: SettingsPaneID) -> some View {
        switch pane {
        case .general:
            SettingsGeneralPane(model: model)
        case .tools:
            SettingsProvidersPane(model: model)
        case .readiness:
            SettingsReadinessPane(model: model)
        case .prompt:
            SettingsPromptPane(model: model)
        case .logs:
            SettingsLogsPane(model: model)
        }
    }
}
