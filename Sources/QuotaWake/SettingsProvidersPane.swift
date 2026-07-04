import QuotaWakeCore
import SwiftUI

struct SettingsProvidersPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        Form {
            ForEach(model.settingsState.toolStates, id: \.tool) { state in
                Section {
                    DetailToggleRow(
                        title: "Use \(state.displayName)",
                        subtitle: "Send readiness prompts through this CLI.",
                        isOn: Binding(
                            get: { model.settings.tools[state.tool].enabled },
                            set: { model.setToolEnabled(state.tool, enabled: $0) }
                        )
                    )
                    LabeledContent("Status") {
                        Text(state.statusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Detected path") {
                        Text(state.pathText)
                            .font(QWDesign.monoCaptionFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(state.pathText)
                    }
                    LabeledContent("Manual path") {
                        TextField(
                            "Manual path",
                            text: Binding(
                                get: { model.settings.tools[state.tool].manualPath ?? "" },
                                set: { model.setManualPath(state.tool, path: $0) }
                            ),
                            prompt: Text("Optional override")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    }
                    LabeledContent("Readiness test") {
                        Button {
                            model.runNow()
                        } label: {
                            Label("Test", systemImage: "checkmark.circle")
                        }
                        .disabled(!state.canTest)
                    }
                } header: {
                    Text(state.displayName)
                } footer: {
                    Text(state.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
