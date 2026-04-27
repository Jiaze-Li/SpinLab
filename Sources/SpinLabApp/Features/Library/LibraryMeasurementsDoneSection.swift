import SwiftUI

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
    var onShowConditionDetail: ((AppliedMeasurement) -> Void)? = nil

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
                .font(AppFontScale.sectionHeader)
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
                    .font(.callout)
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
        if onShowConditionDetail != nil {
            Divider()
            Button("Edit Conditions\u{2026}") {
                onShowConditionDetail?(measurement)
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
