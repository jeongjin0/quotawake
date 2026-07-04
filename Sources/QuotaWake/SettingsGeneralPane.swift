import QuotaWakeCore
import SwiftUI

struct SettingsGeneralPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        Form {
            Section("Status") {
                SettingsStatusRow(
                    title: model.popoverState.statusTitle,
                    detail: model.popoverState.statusDetail,
                    tone: model.popoverState.statusTone
                ) {
                    Button {
                        model.runNow()
                    } label: {
                        Label(model.popoverState.runNowTitle, systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.popoverState.canRunNow)
                }
            }

            Section("Application") {
                LabeledContent("App", value: model.settingsState.appVersionText)
                DetailToggleRow(
                    title: "Launch at Login",
                    subtitle: "Start session readiness after you sign in.",
                    isOn: Binding(
                        get: { model.settings.background.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
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
                LabeledContent("Manual updates") {
                    Button {
                        model.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(updateIsChecking)
                }
                if case let .available(version, _) = model.updateCheckState {
                    LabeledContent("Available download") {
                        Button {
                            model.openAvailableUpdate()
                        } label: {
                            Label("Download QuotaWake \(version)", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                VStack(alignment: .leading, spacing: QWDesign.space1) {
                    Text(updateStatusText)
                    if let message = model.statusMessage {
                        Text(message)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var updateIsChecking: Bool {
        if case .checking = model.updateCheckState {
            return true
        }
        return false
    }

    private var updateStatusText: String {
        switch model.updateCheckState {
        case .idle:
            return "Checks the release page for a signed DMG."
        case .checking:
            return "Checking for updates…"
        case let .upToDate(message):
            return message
        case let .available(version, _):
            return "QuotaWake \(version) available."
        case let .failed(message):
            return message
        }
    }
}
