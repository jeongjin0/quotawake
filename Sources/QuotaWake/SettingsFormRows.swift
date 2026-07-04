import QuotaWakeCore
import SwiftUI

// Reusable rows for the grouped-form settings panes. Native Form supplies
// row backgrounds, separators, and padding; these only arrange content.

struct SettingsStatusRow<Action: View>: View {
    let title: String
    let detail: String
    let tone: UIStatusTone
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .center, spacing: QWDesign.space4) {
            HStack(alignment: .top, spacing: QWDesign.space2) {
                StatusDot(tone: tone)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: QWDesign.space1) {
                    Text(title)
                        .font(QWDesign.bodyEmphasisFont)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: QWDesign.space3)

            action
        }
        .padding(.vertical, QWDesign.space1)
    }
}

struct DetailToggleRow: View {
    let title: String
    var subtitle: String?
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

struct SettingsProviderStatusRow: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        VStack(alignment: .leading, spacing: QWDesign.space2) {
            HStack(spacing: QWDesign.space2) {
                StatusDot(tone: provider.statusTone)
                Text(provider.displayName)
                    .font(QWDesign.bodyEmphasisFont)
                Spacer()
                Text(provider.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            providerDetail(label: "Last readiness", value: provider.lastReadinessText)
            providerDetail(label: "Next reset", value: provider.nextResetText)
            providerDetail(label: "Confidence", value: provider.confidenceText)
            providerDetail(label: "Source", value: provider.sourceText)
            Text(provider.detailText)
                .font(QWDesign.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.vertical, QWDesign.space1)
    }

    private func providerDetail(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .font(.subheadline)
    }
}

struct LogsEmptyState: View {
    var body: some View {
        VStack(spacing: QWDesign.space2) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.tertiary)
            Text("No readiness runs yet")
                .font(QWDesign.bodyEmphasisFont)
            Text("New local run results will appear here after a readiness check.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(QWDesign.space6)
    }
}
