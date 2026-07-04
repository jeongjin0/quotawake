import QuotaWakeCore
import SwiftUI

struct SettingsPromptPane: View {
    @ObservedObject var model: QuotaWakeAppModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        Form {
            Section {
                TextEditor(
                    text: Binding(
                        get: { model.settings.prompt },
                        set: { model.setPrompt($0) }
                    )
                )
                .font(QWDesign.bodyFont)
                .scrollContentBackground(.hidden)
                .padding(QWDesign.space2)
                .frame(minHeight: 168)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    promptFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: promptFocused ? 2 : 1
                                )
                        )
                )
                .focused($promptFocused)
                .accessibilityLabel("Readiness prompt")
            } header: {
                Text("Readiness Prompt")
            } footer: {
                Text("Used for readiness prompts sent through enabled providers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(
                    model.settingsState.promptPreview.isEmpty
                        ? "No prompt preview"
                        : model.settingsState.promptPreview
                )
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Preview")
            } footer: {
                Text("Compact surfaces use the same middle-truncated preview.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
