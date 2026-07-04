import AppKit
import QuotaWakeCore
import SwiftUI

// Rows are immutable newest-first snapshots, so the index is a stable identity.
private struct LogTableEntry: Identifiable {
    let id: Int
    let row: LogRowUIState
}

struct SettingsLogsPane: View {
    @ObservedObject var model: QuotaWakeAppModel

    private var entries: [LogTableEntry] {
        model.settingsState.logRows.enumerated().map { LogTableEntry(id: $0.offset, row: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run history")
                    .font(QWDesign.bodyEmphasisFont)
                Text("Latest session readiness runs, newest first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, QWDesign.space5)
            .padding(.top, QWDesign.space4)
            .padding(.bottom, QWDesign.space3)

            Table(entries) {
                TableColumn("Time") { entry in
                    Text(entry.row.timeText)
                        .font(QWDesign.monoCaptionFont)
                }
                .width(min: 64, ideal: 76)

                TableColumn("Provider") { entry in
                    Text(entry.row.toolText)
                }
                .width(min: 48, ideal: 60)

                TableColumn("Status") { entry in
                    HStack(spacing: QWDesign.space1 + 2) {
                        StatusDot(tone: entry.row.tone)
                        Text(entry.row.statusText)
                            .lineLimit(1)
                    }
                    .help(entry.row.statusText)
                }
                .width(min: 96, ideal: 116)

                TableColumn("Duration") { entry in
                    Text(entry.row.durationText)
                        .font(QWDesign.monoCaptionFont)
                }
                .width(min: 56, ideal: 70)

                TableColumn("Exit") { entry in
                    Text(entry.row.exitCodeText)
                        .font(QWDesign.monoCaptionFont)
                }
                .width(min: 40, ideal: 48)

                TableColumn("Summary") { entry in
                    Text(entry.row.summaryText.isEmpty ? "No summary" : entry.row.summaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(entry.row.summaryText)
                }
                .width(min: 160)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: LogTableEntry.ID.self) { ids in
                if let entry = entries.first(where: { ids.contains($0.id) }) {
                    Button("Copy Summary") {
                        copyToPasteboard(entry.row.summaryText)
                    }
                    Button("Copy Row") {
                        copyToPasteboard(rowText(entry.row))
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    LogsEmptyState()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func rowText(_ row: LogRowUIState) -> String {
        [row.timeText, row.toolText, row.statusText, row.durationText, row.exitCodeText, row.summaryText]
            .joined(separator: "\t")
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
