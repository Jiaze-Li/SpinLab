import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var appState: SpinLabAppState
    @State private var selectedProject: String = "All"
    @State private var selectedSample: String = "All"
    @State private var selectedBatch: String = "All"
    @State private var selectedMeasurementType: String = "All"
    @State private var selectedDateRange: DateFilter = .anyTime

    var body: some View {
        HSplitView {
            libraryBrowserColumn
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)

            libraryDetailColumn
                .frame(minWidth: 360, idealWidth: 700, maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedRecord: SpinLabDomain.ArchivedRecord? {
        filteredRecords.first(where: { $0.id == appState.selectedArchivedRecordID }) ?? filteredRecords.first
    }

    private var filteredRecords: [SpinLabDomain.ArchivedRecord] {
        appState.archivedRecords.filter { record in
            matches(selectedProject, value: record.project?.name)
            && matches(selectedSample, value: record.sample.name)
            && matches(selectedBatch, value: record.batch?.name)
            && matches(selectedMeasurementType, value: record.measurement.measurementType.rawValue)
            && selectedDateRange.matches(record.archivedAt)
        }
    }

    private var uniqueProjects: [String] {
        uniqueValues(from: appState.archivedRecords.compactMap { $0.project?.name })
    }

    private var uniqueSamples: [String] {
        uniqueValues(from: appState.archivedRecords.map { $0.sample.name })
    }

    private var uniqueBatches: [String] {
        uniqueValues(from: appState.archivedRecords.compactMap { $0.batch?.name })
    }

    private var uniqueMeasurementTypes: [String] {
        uniqueValues(from: appState.archivedRecords.map { $0.measurement.measurementType.rawValue })
    }

    private func uniqueValues(from values: [String]) -> [String] {
        ["All"] + Array(Set(values)).sorted()
    }

    private func matches(_ selected: String, value: String?) -> Bool {
        selected == "All" || selected == value
    }

    private var libraryBrowserColumn: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Library")
                    .font(.title2.bold())

                GroupBox("Filters") {
                    VStack(alignment: .leading, spacing: 10) {
                        filterPicker("Project", selection: $selectedProject, values: uniqueProjects)
                        filterPicker("Sample", selection: $selectedSample, values: uniqueSamples)
                        filterPicker("Batch", selection: $selectedBatch, values: uniqueBatches)
                        filterPicker("measurement_type", selection: $selectedMeasurementType, values: uniqueMeasurementTypes)

                        Picker("Date", selection: $selectedDateRange) {
                            ForEach(DateFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Archived Measurements") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredRecords) { record in
                            Button {
                                appState.selectedArchivedRecordID = record.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.measurement.name)
                                        .font(.headline)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                    Text("\(record.sample.name) • \(record.measurement.measurementType.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                    Text("Archived \(record.archivedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(appState.selectedArchivedRecordID == record.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if filteredRecords.isEmpty {
                            Text("No archived measurements match the current filters.")
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var libraryDetailColumn: some View {
        ScrollView([.vertical, .horizontal]) {
            Group {
                if let record = selectedRecord {
                    LibraryRecordDetailView(record: record)
                } else {
                    ContentUnavailableView(
                        "No Archived Record",
                        systemImage: "books.vertical",
                        description: Text("Archived AMR/PHE measurements will appear here.")
                    )
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func filterPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(value).tag(value)
            }
        }
    }
}

private struct LibraryRecordDetailView: View {
    let record: SpinLabDomain.ArchivedRecord
    @EnvironmentObject private var appState: SpinLabAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(record.measurement.name)
                .font(.title2.bold())
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            MetadataValueRow(label: "Project", value: record.project?.name ?? "Unlinked")
            MetadataValueRow(label: "Sample", value: record.sample.name)
            MetadataValueRow(label: "Batch", value: record.batch?.name ?? "None")
            MetadataValueRow(label: "Device", value: record.device?.name ?? "None")
            MetadataValueRow(label: "measurement_type", value: record.measurement.measurementType.rawValue)
            MetadataValueRow(label: "Archived", value: record.archivedAt.formatted())
            MetadataValueRow(label: "Dataset Source", value: record.dataset.sourceFilePath, monospaced: true)
            MetadataValueRow(label: "Dataset Columns", value: record.dataset.columns.joined(separator: ", "))

            Divider()

            Text("Result Summary")
                .font(.headline)
            Text(record.latestResult?.summary ?? "No result saved yet.")
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text("Rating exists on Result, but it is intentionally not a primary V1 library filter.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Open In Workbench") {
                appState.openArchivedRecordInWorkbench(record.id)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum DateFilter: String, CaseIterable, Identifiable {
    case anyTime = "Any time"
    case last30Days = "Last 30 days"
    case last365Days = "Last 365 days"

    var id: String { rawValue }

    func matches(_ date: Date) -> Bool {
        switch self {
        case .anyTime:
            return true
        case .last30Days:
            return date >= Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        case .last365Days:
            return date >= Calendar.current.date(byAdding: .day, value: -365, to: .now) ?? .distantPast
        }
    }
}
