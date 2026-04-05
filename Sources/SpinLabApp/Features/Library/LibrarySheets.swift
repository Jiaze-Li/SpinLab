import SwiftUI

// MARK: - Shared helpers

private let logDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private func formattedLogTimestamp(_ timestamp: Date?) -> String {
    guard let timestamp else { return "Unknown time" }
    return logDateTimeFormatter.string(from: timestamp)
}

private func displayValue(_ value: String?) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed?.isEmpty == false) ? trimmed! : "∅"
}

// MARK: - Sample Change Log Sheet

struct SampleChangeLogSheetView: View {
    let sample: LibrarySample?
    let entries: [LibrarySampleChangeLogEntry]
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            if let sample {
                List {
                    if entries.isEmpty {
                        Text("No change log records for this sample.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            Section {
                                ForEach(entry.changes, id: \.self) { change in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.key)
                                            .font(.caption.weight(.semibold))
                                        Text("\(displayValue(change.oldValue)) -> \(displayValue(change.newValue))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } header: {
                                Text("\(logDateTimeFormatter.string(from: entry.changedAt)) · \(entry.source)")
                            }
                        }
                    }
                }
                .navigationTitle("\(sample.batchId) · \(sample.substrateDisplay)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Sample Selected",
                    systemImage: "tray",
                    description: Text("Select a sample to view change log.")
                )
            }
        }
        .frame(minWidth: 540, minHeight: 420)
    }
}

// MARK: - Global Manual Log Sheet

struct GlobalManualLogSheetView: View {
    let logs: [LibraryManualUpdateLogEntry]
    let error: String?
    let message: String?
    @Binding var isPresented: Bool
    let onRefresh: () -> Void
    let onMarkStatus: (Int, LibraryManualLogStatus) -> Void

    var body: some View {
        NavigationStack {
            List {
                if logs.isEmpty {
                    Text("No global manual log records.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { entry in
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.sampleId) · \(entry.fieldType): \(entry.fieldKey)")
                                    .font(.callout.weight(.semibold))
                                Text("\(displayValue(entry.oldValue)) -> \(displayValue(entry.newValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Sheet: \(entry.sheetName) · Row: \(entry.rowNumber)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                statusButton(for: entry, targetStatus: .pending, title: "Pending")
                                statusButton(for: entry, targetStatus: .done, title: "Done")
                                statusButton(for: entry, targetStatus: .ignored, title: "Ignored")
                                Spacer()
                            }
                        } header: {
                            Text("\(entry.batchId) · \(formattedLogTimestamp(entry.timestamp)) · \(entry.status.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Numeric日志")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { onRefresh() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func statusButton(for entry: LibraryManualUpdateLogEntry, targetStatus: LibraryManualLogStatus, title: String) -> some View {
        if targetStatus == entry.status {
            Button(title) { onMarkStatus(entry.rowIndex, targetStatus) }
                .buttonStyle(.borderedProminent)
                .disabled(true)
        } else {
            Button(title) { onMarkStatus(entry.rowIndex, targetStatus) }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Metadata Sync Log Sheet

struct MetadataSyncLogSheetView: View {
    let entries: [LibraryMetadataSyncLogEntry]
    let error: String?
    let message: String?
    @Binding var isPresented: Bool
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No metadata sync log records.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, content: entrySection)
                }
            }
            .navigationTitle("Metadata同步日志")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { onRefresh() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func entrySection(_ entry: LibraryMetadataSyncLogEntry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.sampleId) · \(entry.columnName)")
                    .font(.callout.weight(.semibold))
                Text("\(displayValue(entry.oldValue)) -> \(displayValue(entry.newValue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sheet: \(entry.sheetName) · Row: \(entry.rowNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(resultText(for: entry))
                    .font(.caption2)
                    .foregroundStyle(entry.writeResult.lowercased() == "success" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
            }
        } header: {
            Text("\(entry.batchId) · \(formattedLogTimestamp(entry.timestamp))")
        }
    }

    private func resultText(for entry: LibraryMetadataSyncLogEntry) -> String {
        if let error = entry.errorMessage, !error.isEmpty {
            return "Result: \(entry.writeResult) · \(error)"
        }
        return "Result: \(entry.writeResult)"
    }
}
