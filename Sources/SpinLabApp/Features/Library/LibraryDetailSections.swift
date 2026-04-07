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
    @State private var hoverTask: Task<Void, Never>?
    @State private var hoveredMeasurementID: String?
    @State private var isHoveringPreviewPanel = false
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
    @State private var expandedWorkflows: Set<String> = []
    @State private var expandedSets: Set<String> = []
    @State private var expandedUncategorized: Set<String> = []

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
            (workflowID: wfID,
             displayName: resolvedDisplayName(forWorkflow: wfID),
             measurements: sortByConditions(grouped[wfID] ?? []))
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

    private func sortByConditions(_ items: [AppliedMeasurement]) -> [AppliedMeasurement] {
        items.sorted { lhs, rhs in
            conditionSortKey(lhs).localizedStandardCompare(conditionSortKey(rhs)) == .orderedAscending
        }
    }

    private func conditionSortKey(_ m: AppliedMeasurement) -> String {
        m.conditions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
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

    private func measurementsInSet(_ set: MeasurementSet, from workflowMeasurements: [AppliedMeasurement]) -> [AppliedMeasurement] {
        let memberSet = Set(set.memberFileNames)
        let matched = workflowMeasurements.filter { memberSet.contains($0.sourceFileName) }
        return sortByConditions(matched)
    }

    /// All chart references, used as fallback when no measurement rows exist.
    private var allRefs: [WorkbenchResultReference] {
        workbenchResults?.references ?? []
    }

    // MARK: - Body

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if measurements.isEmpty {
                if allRefs.isEmpty {
                    Text("No measurements applied yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    MeasurementPlotPreviewPanel(
                        references: allRefs,
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
            hoverTask?.cancel()
            hoverTask = nil
            hoveredMeasurementID = nil
            isHoveringPreviewPanel = false
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
        let members = measurementsInSet(set, from: workflowMeasurements)
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

    /// Returns `WorkbenchResultReference` objects linked to this measurement via the plot index.
    private func plotRefs(for measurement: AppliedMeasurement) -> [WorkbenchResultReference] {
        guard let plotIndex = measurementPlotIndex,
              let results = workbenchResults else { return [] }
        let keys = plotIndex.entries[measurement.sourceFileName] ?? []
        let refsByKey = Dictionary(uniqueKeysWithValues: results.references.map { ($0.chartIdentityKey, $0) })
        return keys.compactMap { refsByKey[$0] }
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
                onDelete: onDeleteChart,
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

    private func schedulePopover(for measurementID: String) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            hoveredMeasurementID = measurementID
        }
    }

    private func cancelPopover(for measurementID: String) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard !isHoveringPreviewPanel else { return }
            if hoveredMeasurementID == measurementID { hoveredMeasurementID = nil }
        }
    }

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
        let title = URL(fileURLWithPath: ref.chartImagePath)
            .deletingPathExtension()
            .lastPathComponent

        ZStack(alignment: .topLeading) {
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

            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if onDelete != nil {
                    Button {
                        pendingDeleteChart = ref
                        isShowingDeleteChartConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this chart and its files")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
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
