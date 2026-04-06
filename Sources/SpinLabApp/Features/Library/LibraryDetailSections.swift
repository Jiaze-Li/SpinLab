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
    var onDelete: ((AppliedMeasurement) -> Void)? = nil
    // v4.1.2.17 — plot preview props
    var workbenchResults: WorkbenchResultsIndex? = nil
    var measurementPlotIndex: MeasurementPlotIndex? = nil
    var libraryRootURL: URL? = nil
    @State private var isExpanded = true
    @State private var hoverTask: Task<Void, Never>?
    @State private var hoveredMeasurementID: String?
    @State private var isHoveringPreviewPanel = false

    private var sortedMeasurements: [AppliedMeasurement] {
        measurements.sorted { lhs, rhs in
            let lName = resolvedDisplayName(lhs)
            let rName = resolvedDisplayName(rhs)
            if lName != rName { return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending }
            return conditionSortKey(lhs).localizedStandardCompare(conditionSortKey(rhs)) == .orderedAscending
        }
    }

    private func resolvedDisplayName(_ m: AppliedMeasurement) -> String {
        let normalized = m.workflow.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = workflowDisplayNameByID[normalized] { return name }
        if let name = workflowDisplayNameByID.first(where: {
            $0.key.caseInsensitiveCompare(normalized) == .orderedSame
        })?.value { return name }
        return m.workflowDisplayName.isEmpty ? m.workflow : m.workflowDisplayName
    }

    private func conditionSortKey(_ m: AppliedMeasurement) -> String {
        m.conditions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if measurements.isEmpty {
                Text("No measurements applied yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sortedMeasurements) { measurement in
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
            hoverTask?.cancel()
            hoverTask = nil
            hoveredMeasurementID = nil
            isHoveringPreviewPanel = false
        }
    }

    /// Returns `WorkbenchResultReference` objects linked to this measurement via the plot index.
    private func plotRefs(for measurement: AppliedMeasurement) -> [WorkbenchResultReference] {
        guard let plotIndex = measurementPlotIndex,
              let results = workbenchResults else { return [] }
        let keys = plotIndex.entries[measurement.sourceFileName] ?? []
        let refsByKey = Dictionary(uniqueKeysWithValues: results.references.map { ($0.chartIdentityKey, $0) })
        return keys.compactMap { refsByKey[$0] }
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
        HStack(alignment: .top, spacing: 0) {
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
                Text(measurement.sourceFileName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if onDelete != nil {
                Button {
                    onDelete?(measurement)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .padding(.top, 2)
                .help("Delete this measurement record")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hoveredMeasurementID == measurement.id
                      ? Color.accentColor.opacity(0.10)
                      : Color.secondary.opacity(0.07))
        )
        .onHover { isHovering in
            if isHovering {
                schedulePopover(for: measurement.id)
            } else {
                cancelPopover(for: measurement.id)
            }
        }
        .popover(
            isPresented: .init(
                get: { hoveredMeasurementID == measurement.id },
                set: { if !$0 { hoveredMeasurementID = nil } }
            ),
            arrowEdge: .leading
        ) {
            MeasurementPlotPreviewPanel(
                references: plotRefs(for: measurement),
                libraryRootURL: libraryRootURL,
                onHoverChanged: { isHovering in
                    isHoveringPreviewPanel = isHovering
                    if isHovering {
                        hoverTask?.cancel()
                    } else {
                        cancelPopover(for: measurement.id)
                    }
                }
            )
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

    private func schedulePopover(for measurementID: String) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            hoveredMeasurementID = measurementID
        }
    }

    // Hide delay lets mouse travel from row into the popover without blinking.
    private func cancelPopover(for measurementID: String) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard !isHoveringPreviewPanel else { return }
            if hoveredMeasurementID == measurementID { hoveredMeasurementID = nil }
        }
    }
}

// MARK: - Measurement Plot Preview Panel (v4.1.2.17)

/// Popover panel shown on hover over a Measurements Done row.
/// Displays thumbnails of all charts that used the hovered measurement file.
///
/// Designed to be extended: add `onTitleEdit`, `onOpenInWorkbench`, etc. as needed.
/// Images are lazy-loaded in the background; empty state is shown when no plots exist.
struct MeasurementPlotPreviewPanel: View {
    let references: [WorkbenchResultReference]
    let libraryRootURL: URL?
    var onHoverChanged: ((Bool) -> Void)? = nil

    @State private var loadedImages: [String: NSImage] = [:]

    var body: some View {
        Group {
            if references.isEmpty {
                Text("No plots yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 200, height: 80)
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(references, id: \.chartIdentityKey) { ref in
                            plotThumbnail(for: ref)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 340, height: min(CGFloat(references.count) * 200 + 16, 420))
            }
        }
        .onAppear {
            for ref in references { loadImageIfNeeded(ref) }
        }
        .onHover { isHovering in
            onHoverChanged?(isHovering)
        }
    }

    @ViewBuilder
    private func plotThumbnail(for ref: WorkbenchResultReference) -> some View {
        let title = URL(fileURLWithPath: ref.chartImagePath)
            .deletingPathExtension()
            .lastPathComponent

        VStack(alignment: .leading, spacing: 4) {
            if let image = loadedImages[ref.chartIdentityKey] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 140)
                    .overlay(ProgressView().scaleEffect(0.7))
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture { openChart(ref) }
        .help("Click to open in viewer")
    }

    private func openChart(_ ref: WorkbenchResultReference) {
        guard let rootURL = libraryRootURL else { return }
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        guard let chartURL = try? resolver.absoluteURL(for: ref.chartImagePath) else { return }
        NSWorkspace.shared.open(chartURL)
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
}

// MARK: - Workbench Results Section (V3.4.2) — REMOVED from UI in v4.1.2.17
// WorkbenchResultsSectionView has been superseded by per-measurement hover previews
// in LibraryMeasurementsDoneSection + MeasurementPlotPreviewPanel.
// Struct retained below for reference only; not used in any view.

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
