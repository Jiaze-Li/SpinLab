import SwiftUI

struct MeasuringConditionSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: MeasuringConditionFileDraft?
    @State private var selectedConditionID: String? = nil
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteID: String? = nil

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
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(
        _ d: MeasuringConditionFileDraft,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                conditionDefinitionsGroup(d, saveErrors: saveErrors)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Condition Definitions

    @ViewBuilder
    private func conditionDefinitionsGroup(
        _ d: MeasuringConditionFileDraft,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        GroupBox("Conditions") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.conditionDefinitions.indices, id: \.self) { idx in
                    let def = d.conditionDefinitions[idx]
                    conditionRow(def: def, d: d, idx: idx, saveErrors: saveErrors)
                    Divider()
                }
                HStack(spacing: AppSpacing.md) {
                    Button("+ New Condition") {
                        addCondition(to: d)
                    }
                    .buttonStyle(.bordered)
                }
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
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedConditionID = isSelected ? nil : def.id
                }
            }) {
                HStack(spacing: AppSpacing.md) {
                    Text(def.id)
                        .font(.callout.weight(.semibold).monospaced())
                        .foregroundStyle(rowHasError ? Color.red : .primary)
                    Spacer()
                    Button(role: .destructive) {
                        requestDelete(id: def.id, d: d)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete condition")
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, AppSpacing.xs)
                .padding(.horizontal, AppSpacing.xs)
            }
            .buttonStyle(.plain)
            .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
            .cornerRadius(AppSpacing.xs)
            .errorHighlight(rowHasError, cornerRadius: AppSpacing.xs)

            if isSelected {
                conditionDetail(idx: idx, d: d)
                    .padding(AppSpacing.md)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(AppSpacing.md)
            }
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
            LabeledContent("Kind") {
                Picker("", selection: Binding(
                    get: { def.kind },
                    set: { newKind in
                        var u = d
                        u.conditionDefinitions[idx].kind = newKind
                        if newKind == "unit_suffix" && u.conditionDefinitions[idx].unitPattern == nil {
                            u.conditionDefinitions[idx].unitPattern = ""
                        } else if newKind == "token_map" && u.conditionDefinitions[idx].tokenMap == nil {
                            u.conditionDefinitions[idx].tokenMap = []
                        }
                        apply(u)
                    }
                )) {
                    Text("unit_suffix").tag("unit_suffix")
                    Text("token_map").tag("token_map")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .labelsHidden()
            }

            if def.kind == "unit_suffix" {
                MatchRulesEditor(
                    rules: unitSuffixSpecsBinding(condIdx: idx),
                    allowedOps: [.unitSuffix, .equals, .contains],
                    defaultOp: .unitSuffix
                )
            } else {
                MatchMapRulesEditor(
                    rules: tokenMapRulesBinding(condIdx: idx),
                    allowedOps: [.equals, .contains],
                    defaultOp: .equals,
                    outputTitle: "Mapped to"
                )
            }
        }
    }

    // MARK: - Bindings (unit_suffix ↔ [FilenameRuleSet.MatchSpec], token_map ↔ [MapRule])

    private func unitSuffixSpecsBinding(condIdx: Int) -> Binding<[FilenameRuleSet.MatchSpec]> {
        Binding(
            get: {
                guard let d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return [] }
                let def = d.conditionDefinitions[condIdx]
                if let tokenMap = def.tokenMap {
                    return tokenMap.compactMap {
                        guard let op = FilenameRuleSet.Operation(rawValue: $0.match.type) else { return nil }
                        return FilenameRuleSet.MatchSpec(type: op, value: $0.match.value)
                    }
                }
                // legacy: unitPattern fallback
                return unitsFromUnitPattern(def.unitPattern)
                    .map { FilenameRuleSet.MatchSpec(type: .unitSuffix, value: $0) }
            },
            set: { specs in
                guard var d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return }
                d.conditionDefinitions[condIdx].tokenMap = specs.map {
                    MapRule(match: .init(type: $0.type.rawValue, value: $0.value), value: "$MATCH")
                }
                d.conditionDefinitions[condIdx].unitPattern = nil
                apply(d)
            }
        )
    }

    private func tokenMapRulesBinding(condIdx: Int) -> Binding<[MapRule]> {
        Binding(
            get: {
                guard let d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return [] }
                // Exclude unit-suffix rules from token_map view — they're incompatible with
                // token_map's allowed ops and would cause Picker auto-snap data corruption.
                // They remain in storage and reappear when switching back to unit_suffix.
                return (d.conditionDefinitions[condIdx].tokenMap ?? []).filter {
                    $0.match.type != "unit-suffix"
                }
            },
            set: { newRules in
                guard var d = draft, d.conditionDefinitions.indices.contains(condIdx) else { return }
                // Preserve any hidden unit-suffix rules alongside the new token_map rules.
                let preserved = (d.conditionDefinitions[condIdx].tokenMap ?? []).filter {
                    $0.match.type == "unit-suffix"
                }
                d.conditionDefinitions[condIdx].tokenMap = preserved + newRules
                apply(d)
            }
        )
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
        u.conditionDefinitions.append(.init(
            id: newID,
            displayName: nil,
            kind: "unit_suffix",
            unitPattern: nil,
            tokenMap: []
        ))
        apply(u)
        selectedConditionID = newID
    }

    // MARK: - Bindings

    private func tokenMapRuleBinding(condIdx: Int, ruleIdx: Int) -> Binding<MapRule> {
        Binding(
            get: {
                guard let d = self.draft,
                      d.conditionDefinitions.indices.contains(condIdx),
                      let rules = d.conditionDefinitions[condIdx].tokenMap,
                      rules.indices.contains(ruleIdx) else {
                    return MapRule(match: .init(type: "equals", value: ""), value: "")
                }
                return rules[ruleIdx]
            },
            set: { newValue in
                guard var d = self.draft,
                      d.conditionDefinitions.indices.contains(condIdx),
                      var rules = d.conditionDefinitions[condIdx].tokenMap,
                      rules.indices.contains(ruleIdx) else { return }
                rules[ruleIdx] = newValue
                d.conditionDefinitions[condIdx].tokenMap = rules
                self.apply(d)
            }
        )
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
