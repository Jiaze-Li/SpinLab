import SwiftUI

struct MeasuringConditionSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: MeasuringConditionFileDraft?
    @State private var selectedConditionID: String? = nil
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteID: String? = nil
    @State private var showInvalidStandardUnitAlert = false

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        RulesSectionShell(
            section: .measuringCondition,
            isDraftAvailable: draft != nil,
            versionLabel: draft.map { "Schema version \($0.version)" },
            onSync: syncFromStore
        ) { $saveErrors in
            if let d = draft {
                scrollContent(d, saveErrors: $saveErrors)
            }
        }
        .confirmationDialog(deleteConfirmTitle(), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteConfirmMessage())
        }
        .alert("Standard unit no longer exists", isPresented: $showInvalidStandardUnitAlert) {
            Button("Choose Unit") { showInvalidStandardUnitAlert = false }
        } message: {
            Text("Choose a standard unit from the current unit rows before saving.")
        }
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(
        _ d: MeasuringConditionFileDraft,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        conditionDefinitionsGroup(d, saveErrors: saveErrors)
    }

    // MARK: - Condition Definitions

    @ViewBuilder
    private func conditionDefinitionsGroup(
        _ d: MeasuringConditionFileDraft,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        GroupBox("Conditions") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(d.conditionDefinitions.indices, id: \.self) { idx in
                    let def = d.conditionDefinitions[idx]
                    conditionRow(def: def, d: d, idx: idx, saveErrors: saveErrors)
                }
                HStack(spacing: AppSpacing.md) {
                    Button("+ New Condition") {
                        addCondition(to: d)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, AppSpacing.md)
            }
        }
        .errorHighlight(saveErrors.wrappedValue.hasGroup("conditionDefinitions"))
    }

    @ViewBuilder
    private func conditionRow(
        def: MeasuringConditionFileDraft.ConditionDefinition,
        d: MeasuringConditionFileDraft,
        idx: Int,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        let isSelected = selectedConditionID == def.id
        let rowHasError = saveErrors.wrappedValue.hasRow(group: "conditionDefinitions", key: def.id)

        RuleExpandableRow(
            title: def.id,
            isExpanded: isSelected,
            rowHasError: rowHasError,
            deleteAccessibilityLabel: "Delete condition",
            onToggle: { selectedConditionID = isSelected ? nil : def.id },
            onDelete: { requestDelete(id: def.id, d: d) }
        ) {
            conditionDetail(idx: idx, d: d)
        }
    }

    @ViewBuilder
    private func conditionDetail(idx: Int, d: MeasuringConditionFileDraft) -> some View {
        let def = d.conditionDefinitions[idx]
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("Display Name") {
                TextField("display name (optional)", text: Binding(
                    get: { def.displayName ?? "" },
                    set: { v in
                        var u = d
                        u.conditionDefinitions[idx].displayName = v.isEmpty ? nil : v
                        apply(u)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            MatchRulesEditor(
                rules: rulesBinding(condIdx: idx),
                allowedOps: [.equals, .contains, .unitSuffix, .regex],
                defaultOp: .equals,
                outputBehavior: .conditionTransform(
                    title: "Mapped to",
                    standardUnit: standardUnitBinding(condIdx: idx),
                    precision: precisionBinding(condIdx: idx),
                    onInvalidStandardUnit: { showInvalidStandardUnitAlert = true }
                )
            )
        }
    }

    // MARK: - Bindings

    private func rulesBinding(condIdx: Int) -> Binding<[MapRule]> {
        Binding(
            get: {
                guard let d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return [] }
                return d.conditionDefinitions[condIdx].matches
            },
            set: { newRules in
                guard var d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return }
                let standardUnit = d.conditionDefinitions[condIdx].standardization.standardUnit
                let normalized = newRules.map { normalizeConditionRuleForUI($0, standardUnit: standardUnit) }
                d.conditionDefinitions[condIdx].matches = normalized
                // Check if current standardUnit is still available
                if let su = standardUnit {
                    let available = normalized.filter {
                        let op = FilenameRuleSet.Operation(rawValue: $0.match.type)
                        return op == .unitSuffix || op == .regex
                    }.map { $0.match.value.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if !available.contains(where: { $0.lowercased() == su.lowercased() }) {
                        showInvalidStandardUnitAlert = true
                    }
                }
                apply(d)
            }
        )
    }

    private func standardUnitBinding(condIdx: Int) -> Binding<String?> {
        Binding(
            get: {
                guard let d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return nil }
                return d.conditionDefinitions[condIdx].standardization.standardUnit
            },
            set: { newVal in
                guard var d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return }
                d.conditionDefinitions[condIdx].standardization.standardUnit = newVal
                apply(d)
            }
        )
    }

    private func precisionBinding(condIdx: Int) -> Binding<String> {
        Binding(
            get: {
                guard let d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return "" }
                return d.conditionDefinitions[condIdx].standardization.precision ?? ""
            },
            set: { newVal in
                guard var d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return }
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                d.conditionDefinitions[condIdx].standardization.precision = trimmed.isEmpty ? nil : trimmed
                apply(d)
            }
        )
    }

    private func normalizeConditionRuleForUI(_ rule: MapRule, standardUnit: String?) -> MapRule {
        let op = FilenameRuleSet.Operation(rawValue: rule.match.type)
        guard op == .unitSuffix || op == .regex else {
            var r = rule
            r.transform = nil
            return r
        }
        var normalized = rule
        normalized.value = "$MATCH"
        // Clear transform if this row IS the standard unit (identity row)
        if let su = standardUnit,
           rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == su.lowercased() {
            normalized.transform = nil
        }
        return normalized
    }

    // MARK: - Delete confirmation

    private func requestDelete(id: String, d: MeasuringConditionFileDraft) {
        pendingDeleteID = id
        let referencingWorkflows = referencingWorkflowNames(for: id)
        if referencingWorkflows.isEmpty {
            performDelete()
        } else {
            showDeleteConfirm = true
        }
    }

    private func performDelete() {
        guard let id = pendingDeleteID, var d = draft else { return }
        d.conditionDefinitions.removeAll { $0.id == id }
        apply(d)
        if selectedConditionID == id { selectedConditionID = nil }
        pendingDeleteID = nil
    }

    private func referencingWorkflowNames(for conditionID: String) -> [String] {
        guard let wf = store.workflowDraft else { return [] }
        return wf.workflows
            .filter { $0.conditionFieldIDs.contains(conditionID) }
            .map { $0.displayName.isEmpty ? $0.id : $0.displayName }
    }

    private func deleteConfirmTitle() -> String {
        guard let id = pendingDeleteID else { return "Delete Condition" }
        return "Delete condition '\(id)'?"
    }

    private func deleteConfirmMessage() -> String {
        guard let id = pendingDeleteID else { return "" }
        let names = referencingWorkflowNames(for: id)
        if names.isEmpty { return "This condition is not referenced by any workflow." }
        let list = names.prefix(5).joined(separator: ", ")
        let suffix = names.count > 5 ? " and \(names.count - 5) more" : ""
        return "\(names.count) workflow\(names.count == 1 ? "" : "s") reference this condition: \(list)\(suffix). Saving those workflows will fail until references are removed."
    }

    // MARK: - Add condition

    private func addCondition(to d: MeasuringConditionFileDraft) {
        var newID = "new_condition"
        let existingIDs = Set(d.conditionDefinitions.map(\.id))
        var n = 2
        while existingIDs.contains(newID) { newID = "new_condition_\(n)"; n += 1 }
        var u = d
        u.conditionDefinitions.append(.init(id: newID, displayName: nil, matches: []))
        apply(u)
        selectedConditionID = newID
    }

    // MARK: - Actions

    private func apply(_ d: MeasuringConditionFileDraft) {
        draft = d
        store.updateMeasuringCondition(d)
    }

    private func syncFromStore() {
        if let current = store.measuringConditionDraft { draft = current }
    }
}
