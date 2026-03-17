import SwiftUI

struct WorkbenchView: View {
    @EnvironmentObject private var appState: SpinLabAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Workbench")
                    .font(.largeTitle.bold())

                Text("Workflow fixed to \(appState.workflow.rawValue)")
                    .foregroundStyle(.secondary)

                if let archived = appState.selectedArchivedRecord {
                    ArchivedWorkbenchDetailView(record: archived)
                } else if let pending = appState.selectedPendingImport {
                    PendingWorkbenchPreview(pending: pending)
                } else {
                    ContentUnavailableView(
                        "No Measurement Selected",
                        systemImage: "waveform.path.ecg.rectangle",
                        description: Text("Select a pending import or archived measurement.")
                    )
                }
            }
            .padding(24)
        }
    }
}

private struct ArchivedWorkbenchDetailView: View {
    let record: SpinLabDomain.ArchivedRecord
    @EnvironmentObject private var appState: SpinLabAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Measurement") {
                VStack(alignment: .leading, spacing: 8) {
                    MetadataValueRow(label: "Measurement", value: record.measurement.name)
                    MetadataValueRow(label: "measurement_type", value: record.measurement.measurementType.rawValue)
                    MetadataValueRow(label: "Sample", value: record.sample.name)
                    MetadataValueRow(label: "Batch", value: record.batch?.name ?? "None")
                    MetadataValueRow(label: "Device", value: record.device?.name ?? "None")
                    MetadataValueRow(label: "Project", value: record.project?.name ?? "Unlinked")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Measurement File Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appState.defaultViewDisplayName)
                        .font(.headline)
                    Text("The earlier Raw AMR/PHE point list was placeholder data from the skeleton. This view now shows file-backed context instead of fake plotted values.")
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    MetadataValueRow(label: "Stored File", value: record.measurement.sourceFilePath, monospaced: true)
                    MetadataValueRow(label: "Original File", value: record.measurement.originalFilePath ?? "Unknown", monospaced: true)
                    MetadataValueRow(label: "Dataset Columns", value: record.dataset.columns.joined(separator: ", "))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Result") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Save creates or updates a Result attached to the active Measurement.")
                        .foregroundStyle(.secondary)

                    TextEditor(text: $appState.workbenchResultDraft)
                        .font(.body)
                        .frame(minHeight: 140)

                    HStack {
                        Button("Save Result Stub") {
                            appState.saveWorkbenchResult()
                        }
                        .buttonStyle(.borderedProminent)

                        if let updatedAt = record.latestResult?.updatedAt {
                            Text("Last updated \(updatedAt.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PendingWorkbenchPreview: View {
    let pending: SpinLabDomain.PendingImport

    var body: some View {
        GroupBox("Pending Preview") {
            VStack(alignment: .leading, spacing: 8) {
                Text("This is a placeholder preview for a pending AMR/PHE import.")
                    .foregroundStyle(.secondary)
                MetadataValueRow(label: "File", value: pending.fileName)
                MetadataValueRow(label: "Parsed Measurement", value: pending.parsedHints.measurementName ?? "Not parsed")
                Text("Archive the item from Inbox to create a persisted Measurement, Dataset, and Result skeleton.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
