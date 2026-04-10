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
    let measurementSets: [MeasurementSet]
    let workflowDisplayNameByID: [String: String]
    let workflowConditionOrderByID: [String: [String]]
    var onDelete: ((AppliedMeasurement) -> Void)? = nil
    // v4.1.2.17 — plot preview props
    var workbenchResults: WorkbenchResultsIndex? = nil
    var measurementPlotIndex: MeasurementPlotIndex? = nil
    var libraryRootURL: URL? = nil
    var onDeleteChart: ((WorkbenchResultReference) -> Void)? = nil
    // v4.1.5 — measurement set callbacks
    var onCreateSet: ((_ name: String, _ workflow: String, _ initialMember: String?) -> Void)? = nil
    var onAddToSet: ((_ setID: String, _ fileName: String) -> Void)? = nil
    var onRemoveFromSet: ((_ setID: String, _ fileName: String) -> Void)? = nil
    var onRenameSet: ((_ setID: String, _ newName: String) -> Void)? = nil
    var onDeleteSet: ((_ setID: String) -> Void)? = nil

    @State private var isExpanded = true
    @State private var hoveredMeasurementID: String?
    // Alert state for "New Set..." / "Rename Set..."
    @State private var newSetAlertShown = false
    @State private var newSetName = ""
    @State private var newSetWorkflow = ""
    @State private var newSetInitialMember: String? = nil
    @State private var renameSetAlertShown = false
    @State private var renameSetName = ""
    @State private var renameSetID = ""
    // v4.1.5.2 — delete measurement confirmation
    @State private var pendingDeleteMeasurement: AppliedMeasurement? = nil
    @State private var isShowingDeleteMeasurementConfirm = false
    // Expansion state for dynamic DisclosureGroups (keyed by workflowID / setID)
    // Owned by LibraryView, passed as Binding for persistence across area switches.
    @Binding var expandedWorkflows: Set<String>
    @Binding var expandedSets: Set<String>
    @Binding var expandedUncategorized: Set<String>

    // MARK: - Grouping helpers

    /// Distinct workflow IDs from measurements, sorted by display name.
    private var workflowGroups: [(workflowID: String, displayName: String, measurements: [AppliedMeasurement])] {
        let grouped = Dictionary(grouping: measurements) {
            $0.workflow.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return grouped.keys.sorted { lhs, rhs in
            resolvedDisplayName(forWorkflow: lhs)
                .localizedCaseInsensitiveCompare(resolvedDisplayName(forWorkflow: rhs)) == .orderedAscending
        }.map { wfID in
            let condOrder = resolvedConditionOrder(forWorkflow: wfID)
            return (workflowID: wfID,
                    displayName: resolvedDisplayName(forWorkflow: wfID),
                    measurements: sortByConditions(grouped[wfID] ?? [], conditionOrder: condOrder))
        }
    }

    private func resolvedDisplayName(forWorkflow wfID: String) -> String {
        if let name = workflowDisplayNameByID[wfID] { return name }
        if let name = workflowDisplayNameByID.first(where: {
            $0.key.caseInsensitiveCompare(wfID) == .orderedSame
        })?.value { return name }
        // Fallback: use the first measurement's display name
        if let m = measurements.first(where: {
            $0.workflow.trimmingCharacters(in: .whitespacesAndNewlines) == wfID
        }) {
            return m.workflowDisplayName.isEmpty ? m.workflow : m.workflowDisplayName
        }
        return wfID
    }

    private func resolvedConditionOrder(forWorkflow wfID: String) -> [String] {
        if let order = workflowConditionOrderByID[wfID] { return order }
        if let order = workflowConditionOrderByID.first(where: {
            $0.key.caseInsensitiveCompare(wfID) == .orderedSame
        })?.value { return order }
        return []
    }

    private func sortByConditions(_ items: [AppliedMeasurement], conditionOrder: [String]) -> [AppliedMeasurement] {
        items.sorted { lhs, rhs in
            conditionSortKey(lhs, conditionOrder: conditionOrder)
                .localizedStandardCompare(conditionSortKey(rhs, conditionOrder: conditionOrder)) == .orderedAscending
        }
    }

    private func conditionSortKey(_ m: AppliedMeasurement, conditionOrder: [String]) -> String {
        let orderSet = Set(conditionOrder)
        let ordered = conditionOrder.compactMap { key in
            m.conditions[key].map { (key, $0) }
        }
        let remaining = m.conditions
            .filter { !orderSet.contains($0.key) }
            .sorted { $0.key < $1.key }
        return (ordered + remaining).map { "\($0.0)=\($0.1)" }.joined(separator: ",")
    }

    private func setsForWorkflow(_ workflowID: String) -> [MeasurementSet] {
        measurementSets.filter {
            $0.workflow.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(workflowID) == .orderedSame
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private func uncategorizedMeasurements(
        in workflowMeasurements: [AppliedMeasurement],
        sets: [MeasurementSet]
    ) -> [AppliedMeasurement] {
        let allSetMembers = Set(sets.flatMap(\.memberFileNames))
        return workflowMeasurements.filter { !allSetMembers.contains($0.sourceFileName) }
    }

    private func measurementsInSet(_ set: MeasurementSet, from workflowMeasurements: [AppliedMeasurement], workflowID: String) -> [AppliedMeasurement] {
        let memberSet = Set(set.memberFileNames)
        let matched = workflowMeasurements.filter { memberSet.contains($0.sourceFileName) }
        return sortByConditions(matched, conditionOrder: resolvedConditionOrder(forWorkflow: workflowID))
    }

    /// All chart references, sorted by tab rank → generatedAt → original index.
    private var sortedAllRefs: [WorkbenchResultReference] {
        WorkbenchResultReference.sortedByTabRank(workbenchResults?.references ?? [])
    }

    // MARK: - Body

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if measurements.isEmpty {
                if sortedAllRefs.isEmpty {
                    Text("No measurements applied yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    MeasurementPlotPreviewPanel(
                        references: sortedAllRefs,
                        libraryRootURL: libraryRootURL,
                        onDelete: onDeleteChart,
                        onHoverChanged: nil
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workflowGroups, id: \.workflowID) { group in
                        workflowSection(group)
                    }
                }
                .padding(.leading, 12)
            }
        } label: {
            Text("Measurements Done")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
        .onDisappear {
            hoveredMeasurementID = nil
        }
        .alert("New Measurement Set", isPresented: $newSetAlertShown) {
            TextField("Set name", text: $newSetName)
            Button("Create") {
                let name = newSetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                onCreateSet?(name, newSetWorkflow, newSetInitialMember)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Set", isPresented: $renameSetAlertShown) {
            TextField("New name", text: $renameSetName)
            Button("Rename") {
                let name = renameSetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                onRenameSet?(renameSetID, name)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete Measurement?",
            isPresented: $isShowingDeleteMeasurementConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Measurement", role: .destructive) {
                if let m = pendingDeleteMeasurement {
                    onDelete?(m)
                }
                pendingDeleteMeasurement = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteMeasurement = nil
            }
        } message: {
            Text("This will permanently delete the measurement data file, metadata, and all associated charts. This cannot be undone.")
        }
    }

    // MARK: - Level 1: Workflow section

    @ViewBuilder
    private func workflowSection(_ group: (workflowID: String, displayName: String, measurements: [AppliedMeasurement])) -> some View {
        let sets = setsForWorkflow(group.workflowID)
        DisclosureGroup(isExpanded: toggleBinding(for: group.workflowID, in: $expandedWorkflows)) {
            if sets.isEmpty {
                // No sets — flat measurement list (two-level)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.measurements) { m in
                        measurementRow(m, workflowID: group.workflowID, setID: nil)
                    }
                }
                .padding(.leading, 12)
            } else {
                // Has sets — show sets + uncategorized (three-level)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sets) { set in
                        setSection(set, workflowMeasurements: group.measurements, workflowID: group.workflowID)
                    }
                    let uncategorized = uncategorizedMeasurements(in: group.measurements, sets: sets)
                    if !uncategorized.isEmpty {
                        DisclosureGroup(isExpanded: toggleBinding(for: group.workflowID, in: $expandedUncategorized)) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(uncategorized) { m in
                                    measurementRow(m, workflowID: group.workflowID, setID: nil)
                                }
                            }
                            .padding(.leading, 12)
                        } label: {
                            disclosureLabel("Uncategorized", count: uncategorized.count, style: .secondary) {
                                if expandedUncategorized.contains(group.workflowID) {
                                    expandedUncategorized.remove(group.workflowID)
                                } else {
                                    expandedUncategorized.insert(group.workflowID)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 12)
            }
        } label: {
            disclosureLabel(group.displayName, count: group.measurements.count, style: .primary) {
                if expandedWorkflows.contains(group.workflowID) {
                    expandedWorkflows.remove(group.workflowID)
                } else {
                    expandedWorkflows.insert(group.workflowID)
                }
            }
        }
    }

    // MARK: - Level 2: Set section

    @ViewBuilder
    private func setSection(_ set: MeasurementSet, workflowMeasurements: [AppliedMeasurement], workflowID: String) -> some View {
        let members = measurementsInSet(set, from: workflowMeasurements, workflowID: workflowID)
        DisclosureGroup(isExpanded: toggleBinding(for: set.id, in: $expandedSets)) {
            if members.isEmpty {
                Text("No measurements in this set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                    .padding(.leading, 12)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(members) { m in
                        measurementRow(m, workflowID: workflowID, setID: set.id)
                    }
                }
                .padding(.leading, 12)
            }
        } label: {
            disclosureLabel(set.name, count: members.count, style: .primary) {
                if expandedSets.contains(set.id) {
                    expandedSets.remove(set.id)
                } else {
                    expandedSets.insert(set.id)
                }
            }
        }
        .contextMenu {
            Button("Rename Set...") {
                renameSetID = set.id
                renameSetName = set.name
                renameSetAlertShown = true
            }
            Divider()
            Button("Delete Set", role: .destructive) {
                onDeleteSet?(set.id)
            }
        }
    }

    // MARK: - Level 3: Measurement row

    /// Returns `WorkbenchResultReference` objects linked to this measurement via the plot index,
    /// sorted by tab order (ThreeOmegaWorkbenchTab.allCases), then generatedAt, then original index.
    private func plotRefs(for measurement: AppliedMeasurement) -> [WorkbenchResultReference] {
        guard let plotIndex = measurementPlotIndex,
              let results = workbenchResults else { return [] }
        let keys = plotIndex.entries[measurement.sourceFileName] ?? []
        let refsByKey = Dictionary(uniqueKeysWithValues: results.references.map { ($0.chartIdentityKey, $0) })
        let unsorted = keys.compactMap { refsByKey[$0] }
        return WorkbenchResultReference.sortedByTabRank(unsorted)
    }

    @ViewBuilder
    private func measurementRow(_ measurement: AppliedMeasurement, workflowID: String, setID: String?) -> some View {
        let conditionOrder = workflowConditionOrderByID[workflowID]
            ?? workflowConditionOrderByID.first(where: {
                $0.key.caseInsensitiveCompare(workflowID) == .orderedSame
            })?.value
            ?? []
        let orderedConditionPairs = orderedConditions(
            measurement.conditions,
            preferredOrder: conditionOrder
        )
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
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
        .textSelection(.enabled)
        .contextMenu {
            measurementContextMenu(measurement, workflowID: workflowID, setID: setID)
        }
        .hoverPopover(
            arrowEdge: .leading,
            isEnabled: !plotRefs(for: measurement).isEmpty,
            onPresentedChanged: { presented in
                hoveredMeasurementID = presented ? measurement.id : nil
            }
        ) { onHoverChanged, onDialogActiveChanged in
            MeasurementPlotPreviewPanel(
                references: plotRefs(for: measurement),
                libraryRootURL: libraryRootURL,
                onDelete: onDeleteChart,
                onHoverChanged: onHoverChanged,
                onDialogActiveChanged: onDialogActiveChanged
            )
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func measurementContextMenu(_ measurement: AppliedMeasurement, workflowID: String, setID: String?) -> some View {
        let sets = setsForWorkflow(workflowID)
        ForEach(sets) { set in
            Button("Add to: \(set.name)") {
                onAddToSet?(set.id, measurement.sourceFileName)
            }
        }
        Button("New Set...") {
            newSetWorkflow = workflowID
            newSetInitialMember = measurement.sourceFileName
            newSetName = ""
            newSetAlertShown = true
        }
        if let setID {
            Divider()
            Button("Remove from Set") {
                onRemoveFromSet?(setID, measurement.sourceFileName)
            }
        }
        if onDelete != nil {
            Divider()
            Button("Delete Measurement\u{2026}", role: .destructive) {
                pendingDeleteMeasurement = measurement
                isShowingDeleteMeasurementConfirm = true
            }
        }
    }

    // MARK: - Helpers

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

    // Hover popover timing is now managed by HoverPopoverModifier.

    // MARK: - Disclosure helpers

    private enum LabelStyle { case primary, secondary }

    /// Full-width clickable label for DisclosureGroup headers.
    /// `onTap` manually toggles the bound `isExpanded` state, since macOS
    /// DisclosureGroup only responds to clicks on the chevron by default.
    @ViewBuilder
    private func disclosureLabel(_ title: String, count: Int, style: LabelStyle, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.callout.weight(style == .primary ? .semibold : .medium))
                .foregroundStyle(style == .primary ? .primary : .secondary)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    /// Creates a Binding<Bool> that toggles membership of `key` in a `Set<String>`.
    private func toggleBinding(for key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding<Bool>(
            get: { set.wrappedValue.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    set.wrappedValue.insert(key)
                } else {
                    set.wrappedValue.remove(key)
                }
            }
        )
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
    var onDelete: ((WorkbenchResultReference) -> Void)? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onDialogActiveChanged: ((Bool) -> Void)? = nil

    @State private var loadedImages: [String: NSImage] = [:]
    // v4.1.5.2 — delete chart confirmation
    @State private var pendingDeleteChart: WorkbenchResultReference? = nil
    @State private var isShowingDeleteChartConfirm = false

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
        .onChange(of: isShowingDeleteChartConfirm) { _, active in
            onDialogActiveChanged?(active)
        }
        .confirmationDialog(
            "Delete Chart?",
            isPresented: $isShowingDeleteChartConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Chart", role: .destructive) {
                if let ref = pendingDeleteChart {
                    onDelete?(ref)
                }
                pendingDeleteChart = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteChart = nil
            }
        } message: {
            Text("This will permanently delete the chart image and its manifest. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func plotThumbnail(for ref: WorkbenchResultReference) -> some View {
        ZStack(alignment: .topTrailing) {
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

            if onDelete != nil {
                Button {
                    pendingDeleteChart = ref
                    isShowingDeleteChartConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Delete this chart and its files")
            }
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

// MARK: - Measurement Data Section (V3.4.3)

/// Latest metric values for this Library sample, displayed in an adaptive 1/2-column
/// grid that mirrors the Numeric Tags layout. Collapses by default.
///
/// - `availableWidth`: the width of the enclosing detail column (used for column count).
struct MeasurementDataSectionView: View {
    let measurementData: WorkbenchMeasurementDataStore?
    let conditionAliasBook: ConditionAliasBook?
    let availableWidth: CGFloat
    var onDeleteMetric: ((String) -> Void)? = nil  // identity key
    @State private var isExpanded = false
    @State private var pendingDeleteKeys: Set<String> = []

    // A range column within a method card.
    private struct RangeColumn: Identifiable {
        var id: String   // range string or "default"
        var range: String
        var entries: [(metric: String, value: String, identityKey: String)]
    }

    // A card grouped by (workflow, method). Contains 1+ range columns.
    private struct MethodCard: Identifiable {
        var id: String
        var method: String       // e.g. "HFE", "" for AHE
        var columns: [RangeColumn]
    }

    private struct ResolvedRecord {
        var identityKey: String
        var workflowID: String
        var metric: String
        var value: Double
        var unit: String
        var method: String
        var range: String
        var device: String
    }

    // Top-level: workflow + device. e.g. "3W · 0deg"
    private struct DeviceGroup: Identifiable {
        var id: String
        var workflowID: String
        var device: String      // "" for workflows without device
        var cards: [MethodCard]

        var displayHeader: String {
            if device.isEmpty { return workflowID.uppercased() }
            return "\(workflowID.uppercased()) · \(device)"
        }
    }

    private var deviceGroups: [DeviceGroup] {
        guard let store = measurementData, !store.latestIndex.isEmpty else { return [] }
        let recordsByID = Dictionary(uniqueKeysWithValues: store.records.map { ($0.recordID, $0) })

        var resolved: [ResolvedRecord] = []
        for (key, pointer) in store.latestIndex {
            guard let record = recordsByID[pointer.recordID] else { continue }
            resolved.append(ResolvedRecord(
                identityKey: key,
                workflowID: record.workflowID,
                metric: record.metric,
                value: pointer.value,
                unit: pointer.canonicalUnit,
                method: record.conditions["v3method"] ?? "",
                range: record.conditions["range"] ?? "",
                device: record.conditions["device"] ?? ""
            ))
        }

        // Group: workflowID → device → method → range
        let byWfDevice = Dictionary(grouping: resolved, by: { "\($0.workflowID)|\($0.device)" })
        var groups: [DeviceGroup] = []

        for wfDeviceKey in byWfDevice.keys.sorted() {
            let records = byWfDevice[wfDeviceKey]!
            let wfID = records.first?.workflowID ?? ""
            let device = records.first?.device ?? ""

            let byMethod = Dictionary(grouping: records, by: { $0.method })
            var cards: [MethodCard] = []

            for method in byMethod.keys.sorted() {
                let methodRecords = byMethod[method]!

                // Collect unit legend for header: metric → unit (skip empty units)
                var unitMap: [(metric: String, unit: String)] = []
                var seenMetrics = Set<String>()
                for r in methodRecords.sorted(by: { $0.metric < $1.metric }) {
                    if !r.unit.isEmpty && seenMetrics.insert(r.metric).inserted {
                        let displayMetric = r.metric == "r_squared" ? "r²" : r.metric
                        unitMap.append((metric: displayMetric, unit: r.unit))
                    }
                }

                let byRange = Dictionary(grouping: methodRecords, by: { $0.range })
                var columns: [RangeColumn] = []

                for range in byRange.keys.sorted() {
                    let rangeRecords = byRange[range]!
                    let entries = rangeRecords
                        .sorted(by: { $0.metric < $1.metric })
                        .map { r in
                            // Value only, no unit (unit is in header)
                            let formatted = String(format: "%g", r.value)
                            return (metric: r.metric, value: formatted, identityKey: r.identityKey)
                        }
                    columns.append(RangeColumn(
                        id: range.isEmpty ? "default" : range,
                        range: range,
                        entries: entries
                    ))
                }

                var cardMethod = method
                if !unitMap.isEmpty {
                    let unitStr = unitMap.map { "\($0.metric): \($0.unit)" }.joined(separator: ", ")
                    cardMethod = method.isEmpty ? "(\(unitStr))" : "\(method) (\(unitStr))"
                }

                cards.append(MethodCard(
                    id: "\(wfID)|\(device)|\(method)",
                    method: cardMethod,
                    columns: columns
                ))
            }
            groups.append(DeviceGroup(
                id: wfDeviceKey,
                workflowID: wfID,
                device: device,
                cards: cards
            ))
        }
        return groups
    }

    private var useTwoColumns: Bool { availableWidth >= 320 }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let groups = deviceGroups
            if groups.isEmpty {
                Text("No measurement data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.displayHeader)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            ForEach(group.cards) { card in
                                methodCardView(card)
                            }
                        }
                    }
                }
            }
        } label: {
            Text("Measurement Data")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
    }

    @ViewBuilder
    private func methodCardView(_ card: MethodCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !card.method.isEmpty {
                Text(card.method)
                    .font(.callout.weight(.semibold))
            }

            if useTwoColumns && card.columns.count >= 2 {
                // Side-by-side: same method, different ranges
                let pairs = stride(from: 0, to: card.columns.count, by: 2).map { i in
                    (card.columns[i], i + 1 < card.columns.count ? card.columns[i + 1] : nil)
                }
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 8) {
                        rangeColumnView(pair.0)
                        if let second = pair.1 {
                            rangeColumnView(second)
                        }
                    }
                }
            } else {
                ForEach(card.columns) { col in
                    rangeColumnView(col)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .contextMenu {
            Button("Copy All") {
                let text = card.columns.map { col in
                    let header = col.range.isEmpty ? "" : "\(col.range)\n"
                    let body = col.entries.map { e in
                        let name = e.metric == "r_squared" ? "r²" : e.metric
                        return "  \(name) = \(e.value)"
                    }.joined(separator: "\n")
                    return header + body
                }.joined(separator: "\n\n")
                let full = card.method.isEmpty ? text : "\(card.method)\n\(text)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(full, forType: .string)
            }
            if onDeleteMetric != nil {
                Divider()
                // Delete entire range group (e.g. "Delete HFE (5K–80K)")
                ForEach(card.columns) { col in
                    let label = [card.method, col.range].filter { !$0.isEmpty }.joined(separator: " ")
                    Button("Delete \(label.isEmpty ? "all" : label)", role: .destructive) {
                        for entry in col.entries {
                            onDeleteMetric?(entry.identityKey)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rangeColumnView(_ col: RangeColumn) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !col.range.isEmpty {
                Text(col.range)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
                ForEach(col.entries, id: \.identityKey) { entry in
                    GridRow {
                        Text(entry.metric == "r_squared" ? "r²" : entry.metric)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(entry.value)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
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
