import QuotaWakeCore
import SwiftUI

struct SettingsReadinessPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        Form {
            Section("Session Readiness") {
                LabeledContent("Summary") {
                    Text(model.settingsState.readinessSummary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .truncationMode(.middle)
                }
                LabeledContent("Next reset") {
                    Text(model.settingsState.nextResetText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .truncationMode(.middle)
                }
                LabeledContent("Confidence") {
                    Text(model.settingsState.confidenceText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                DetailToggleRow(
                    title: "Background readiness",
                    subtitle: "Automatic readiness pauses while this is off.",
                    isOn: Binding(
                        get: { !model.settings.readiness.paused },
                        set: { model.setReadinessPaused(!$0) }
                    )
                )
            }

            Section {
                Picker(
                    "Reset estimation",
                    selection: Binding(
                        get: { model.settings.readiness.resetEstimationMode },
                        set: { model.setResetEstimationMode($0) }
                    )
                ) {
                    Text("Local signals only").tag(ResetEstimationMode.localSignalsOnly)
                    Text("Allow estimated candidate").tag(ResetEstimationMode.allowFiveHourEstimate)
                }
                .pickerStyle(.segmented)
                DetailToggleRow(
                    title: "Require active use",
                    subtitle: "Send only when this Mac appears active.",
                    isOn: Binding(
                        get: { model.settings.readiness.activeOnly },
                        set: { model.setActiveOnly($0) }
                    )
                )
                LabeledContent("Idle threshold") {
                    Stepper(
                        "\(model.settings.readiness.idleThresholdSeconds) seconds",
                        value: Binding(
                            get: { model.settings.readiness.idleThresholdSeconds },
                            set: { model.setIdleThresholdSeconds($0) }
                        ),
                        in: 30...3_600,
                        step: 30
                    )
                    .fixedSize()
                }
                LabeledContent("Minimum cooldown") {
                    Stepper(
                        "\(model.settings.readiness.minimumSendCooldownMinutes) minutes",
                        value: Binding(
                            get: { model.settings.readiness.minimumSendCooldownMinutes },
                            set: { model.setMinimumSendCooldownMinutes($0) }
                        ),
                        in: 0...360,
                        step: 5
                    )
                    .fixedSize()
                }
            } header: {
                Text("Usage Window Scheduling")
            } footer: {
                Text("How quota window wake candidates are selected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Provider Status") {
                ForEach(model.settingsState.providerStates, id: \.tool) { provider in
                    SettingsProviderStatusRow(provider: provider)
                }
            }

            Section {
                LabeledContent("Manual actions") {
                    Button {
                        model.runNow()
                    } label: {
                        Label("Send Readiness Now", systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.popoverState.canRunNow)
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Run readiness now without waiting for the next schedule.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
