import AppKit
import SwiftUI

struct LibraryExistingDrawerSampleSectionView: View {
    let level2HeaderFont: Font
    let level3HeaderFont: Font
    let selectedPrefix: String?
    let selectedBatchId: String?
    let selectedSampleId: String?
    let selectedExistingBatchSamples: [LibrarySample]
    let onSelectSample: (LibrarySample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing Drawer Samples")
                .font(level2HeaderFont)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let selectedPrefix, let selectedBatchId {
                        HStack {
                            Text("Batch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(selectedPrefix)/\(selectedBatchId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedExistingBatchSamples.isEmpty {
                            Text("No samples found in selected drawer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(selectedExistingBatchSamples) { sample in
                                        Button {
                                            onSelectSample(sample)
                                        } label: {
                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                Text(sample.substrateDisplay)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(6)
                                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(selectedSampleId == sample.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(height: 220)
                        }
                    } else {
                        Text("Select a batch in the left Library tree to choose its samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Sample List")
                    .font(level3HeaderFont)
            }
        }
    }
}

struct LibrarySampleDetailHeaderView: View {
    let isEditingSelectedSample: Bool
    let sampleEditIsDirty: Bool
    let sampleEditIsSaving: Bool
    let canEditSelectedLibrarySample: Bool
    let sampleEditError: String?
    let sampleEditMessage: String?

    let onLoadGlobalManualLogs: () -> Void
    let onLoadMetadataSyncLogs: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: () -> Void
    let onBeginEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sample Detail")
                    .font(.title2.bold())
                Spacer()
                Button("Numeric日志") {
                    onLoadGlobalManualLogs()
                }
                Button("Metadata日志") {
                    onLoadMetadataSyncLogs()
                }
                if isEditingSelectedSample {
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    Button("Save") {
                        onSaveEdit()
                    }
                    .disabled(!sampleEditIsDirty || sampleEditIsSaving)
                } else {
                    Button("Edit") {
                        onBeginEdit()
                    }
                    .disabled(!canEditSelectedLibrarySample)
                }
            }

            if let sampleEditError {
                Text(sampleEditError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let sampleEditMessage {
                Text(sampleEditMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LibraryMeasurementsDoneSection: View {
    let measurements: [AppliedMeasurement]
    let workflowDisplayNameByID: [String: String]
    let workflowConditionOrderByID: [String: [String]]
    @State private var isExpanded = true
    @State private var hoverRevealTask: Task<Void, Never>?
    @State private var revealedFileNameMeasurementID: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if measurements.isEmpty {
                Text("No measurements applied yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(measurements) { measurement in
                        measurementRow(measurement)
                    }
                }
            }
        } label: {
            Text("Measurements Done")
                .font(.title3.weight(.semibold))
        }
        .textSelection(.enabled)
        .onDisappear {
            hoverRevealTask?.cancel()
            hoverRevealTask = nil
            revealedFileNameMeasurementID = nil
        }
    }

    @ViewBuilder
    private func measurementRow(_ measurement: AppliedMeasurement) -> some View {
        let normalizedWorkflowID = measurement.workflow.trimmingCharacters(in: .whitespacesAndNewlines)
        let registryDisplayName = workflowDisplayNameByID[normalizedWorkflowID]
            ?? workflowDisplayNameByID.first(where: {
                $0.key.caseInsensitiveCompare(normalizedWorkflowID) == .orderedSame
            })?.value
        let displayWorkflow = registryDisplayName
            ?? (measurement.workflowDisplayName.isEmpty ? measurement.workflow : measurement.workflowDisplayName)
        let conditionOrder = workflowConditionOrderByID[normalizedWorkflowID]
            ?? workflowConditionOrderByID.first(where: {
                $0.key.caseInsensitiveCompare(normalizedWorkflowID) == .orderedSame
            })?.value
            ?? []
        let orderedConditionPairs = orderedConditions(
            measurement.conditions,
            preferredOrder: conditionOrder
        )
        VStack(alignment: .leading, spacing: 3) {
            Text(displayWorkflow)
                .font(.callout.weight(.semibold))
            if !orderedConditionPairs.isEmpty {
                HStack(spacing: 8) {
                ForEach(orderedConditionPairs, id: \.key) { pair in
                    Text(pair.value.isEmpty ? "—" : pair.value)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                }
            }
            if revealedFileNameMeasurementID == measurement.id {
                Text(measurement.sourceFileName)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07)))
        .onHover { isHovering in
            if isHovering {
                scheduleFileNameReveal(for: measurement.id)
            } else {
                cancelFileNameReveal(for: measurement.id)
            }
        }
    }

    private func orderedConditions(
        _ conditions: [String: String],
        preferredOrder: [String]
    ) -> [(key: String, value: String)] {
        guard !conditions.isEmpty else { return [] }
        let indexByKey = Dictionary(
            uniqueKeysWithValues: preferredOrder.enumerated().map { ($0.element.lowercased(), $0.offset) }
        )
        return conditions.sorted { lhs, rhs in
            let leftIndex = indexByKey[lhs.key.lowercased()]
            let rightIndex = indexByKey[rhs.key.lowercased()]
            switch (leftIndex, rightIndex) {
            case let (l?, r?):
                if l != r { return l < r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
    }

    private func scheduleFileNameReveal(for measurementID: String) {
        hoverRevealTask?.cancel()
        hoverRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            revealedFileNameMeasurementID = measurementID
        }
    }

    private func cancelFileNameReveal(for measurementID: String) {
        hoverRevealTask?.cancel()
        hoverRevealTask = nil
        if revealedFileNameMeasurementID == measurementID {
            revealedFileNameMeasurementID = nil
        }
    }
}

// MARK: - Workbench Results Section (V3.4.2)

/// Read-only list of chart artifacts linked to this Library sample.
///
/// Each row shows the chart filename (title_timestamp_hex format).
/// Hovering over a row lazy-loads the chart image and shows it in a popover.
/// Clicking a row opens the PNG in the default viewer via NSWorkspace.
struct WorkbenchResultsSectionView: View {
    let workbenchResults: WorkbenchResultsIndex?
    let libraryRootURL: URL?
    var onDelete: ((WorkbenchResultReference) -> Void)? = nil
    @State private var isExpanded = false
    @State private var loadedImages: [String: NSImage] = [:]
    @State private var hoveredKey: String? = nil
    @State private var hoverTask: Task<Void, Never>? = nil

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let refs = workbenchResults?.references, !refs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(refs.sorted(by: { $0.generatedAt > $1.generatedAt }), id: \.chartIdentityKey) { ref in
                        resultRow(ref)
                    }
                }
            } else {
                Text("No Workbench results yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Workbench Results")
                .font(.title3.weight(.semibold))
        }
        .onDisappear {
            hoverTask?.cancel()
            hoveredKey = nil
        }
    }

    @ViewBuilder
    private func resultRow(_ ref: WorkbenchResultReference) -> some View {
        let displayName = URL(fileURLWithPath: ref.chartImagePath)
            .deletingPathExtension()
            .lastPathComponent

        HStack(spacing: 0) {
            Text(displayName)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if onDelete != nil {
                Button {
                    onDelete?(ref)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Delete this chart")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hoveredKey == ref.chartIdentityKey
                      ? Color.accentColor.opacity(0.10)
                      : Color.secondary.opacity(0.07))
        )
        .onTapGesture { openChart(ref) }
        .onHover { isHovering in
            if isHovering {
                scheduleReveal(for: ref)
            } else {
                scheduleHide(for: ref)
            }
        }
        .popover(
            isPresented: .init(
                get: { hoveredKey == ref.chartIdentityKey },
                set: { if !$0 { hoveredKey = nil } }
            ),
            arrowEdge: .leading
        ) {
            chartPopover(for: ref)
        }
    }

    @ViewBuilder
    private func chartPopover(for ref: WorkbenchResultReference) -> some View {
        if let image = loadedImages[ref.chartIdentityKey] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 440, height: 330)
                .padding(8)
        } else {
            ProgressView("Loading…")
                .frame(width: 200, height: 150)
                .padding()
        }
    }

    // Show popover after a 250 ms settle; start image load immediately on hover.
    private func scheduleReveal(for ref: WorkbenchResultReference) {
        hoverTask?.cancel()
        loadImageIfNeeded(ref)
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            hoveredKey = ref.chartIdentityKey
        }
    }

    // Small hide delay lets mouse travel from row into the popover without blinking.
    private func scheduleHide(for ref: WorkbenchResultReference) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            if hoveredKey == ref.chartIdentityKey { hoveredKey = nil }
        }
    }

    private func loadImageIfNeeded(_ ref: WorkbenchResultReference) {
        guard loadedImages[ref.chartIdentityKey] == nil,
              let rootURL = libraryRootURL else { return }
        let chartPath = ref.chartImagePath
        let key = ref.chartIdentityKey
        Task {
            let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let resolver = LibraryPathResolver(libraryRootURL: rootURL)
                guard let url = try? resolver.absoluteURL(for: chartPath) else { return nil }
                return NSImage(contentsOf: url)
            }.value
            if let image { loadedImages[key] = image }
        }
    }

    private func openChart(_ ref: WorkbenchResultReference) {
        guard let rootURL = libraryRootURL else { return }
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        guard let chartURL = try? resolver.absoluteURL(for: ref.chartImagePath) else { return }
        NSWorkspace.shared.open(chartURL)
    }
}

// MARK: - Measurement Data Section (V3.4.3)

/// Latest metric values for this Library sample, displayed in an adaptive 1/2-column
/// grid that mirrors the Numeric Tags layout. Collapses by default.
///
/// - `availableWidth`: the width of the enclosing detail column (used for column count).
struct MeasurementDataSectionView: View {
    let measurementData: WorkbenchMeasurementDataStore?
    let conditionAliasBook: ConditionAliasBook?
    let availableWidth: CGFloat
    @State private var isExpanded = false

    // One grid item per metric entry. Label = metric (+ condition summary if any),
    // value = formatted number + unit (with * and orange tint for overridden values).
    private struct MetricCell: Identifiable {
        var id: String          // latestIndex identity key
        var label: String       // e.g. "Hc" or "Hc · 80K"
        var value: String       // e.g. "0.05 T" or "0.05 T *"
        var isOverridden: Bool
    }

    private var cells: [MetricCell] {
        guard let store = measurementData, !store.latestIndex.isEmpty else { return [] }
        let recordsByID = Dictionary(uniqueKeysWithValues: store.records.map { ($0.recordID, $0) })
        return store.latestIndex
            .sorted(by: { $0.key < $1.key })
            .compactMap { key, pointer -> MetricCell? in
                guard let record = recordsByID[pointer.recordID] else { return nil }
                let condSummary = record.conditions
                    .sorted(by: { $0.key < $1.key })
                    .map { (k, v) in
                        let displayKey = conditionDisplayLabel(key: k, aliasBook: conditionAliasBook)
                        return "\(displayKey): \(v)"
                    }
                    .joined(separator: " · ")
                let label = condSummary.isEmpty ? record.metric : "\(record.metric)\n\(condSummary)"
                let value = measurementValueText(
                    value: pointer.value,
                    unit: pointer.canonicalUnit,
                    isOverridden: record.overrideInfo != nil
                )
                return MetricCell(
                    id: key,
                    label: label,
                    value: value,
                    isOverridden: record.overrideInfo != nil
                )
            }
    }

    // Switch from 1 to 2 columns when panel is wide enough to hold two ~140 pt cells.
    private var columnCount: Int { availableWidth >= 300 ? 2 : 1 }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if cells.isEmpty {
                Text("No measurement data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let columns = Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columnCount)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(cells) { cell in
                        metricCell(cell)
                    }
                }
            }
        } label: {
            Text("Measurement Data")
                .font(.title3.weight(.semibold))
        }
    }

    @ViewBuilder
    private func metricCell(_ cell: MetricCell) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(cell.value)
                .font(.body)
                .foregroundStyle(cell.isOverridden ? .orange : .primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Formatting helpers (internal for testing)

/// Formats a metric value + unit for display in `MeasurementDataSectionView`.
/// Appends ` *` when the value was manually overridden.
func measurementValueText(value: Double, unit: String, isOverridden: Bool) -> String {
    let formatted = String(format: "%g", value)
    return isOverridden ? "\(formatted) \(unit) *" : "\(formatted) \(unit)"
}

/// Returns the display label for a condition key, using alias book when available.
/// Falls back to the raw key when `aliasBook` is nil.
func conditionDisplayLabel(key: String, aliasBook: ConditionAliasBook?) -> String {
    aliasBook?.displayLabel(for: key) ?? key
}
