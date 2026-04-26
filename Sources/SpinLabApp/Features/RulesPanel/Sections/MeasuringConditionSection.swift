import SwiftUI

struct MeasuringConditionSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: MeasuringConditionFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""
    @State private var selectedConditionID: String? = nil
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteID: String? = nil
    @State private var expandedTokenMapKey: String? = nil
    @State private var expandedTokenMapRuleIndices: [String: Int] = [:]

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        VStack(spacing: 0) {
            saveBar()
            Divider()
            Group {
                if let d = draft {
                    scrollContent(d)
                } else {
                    ContentUnavailableView("No measuring condition rules loaded", systemImage: "doc.questionmark")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { syncFromStore() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: .measuringCondition)
                syncFromStore()
            }
            Button("Override With My Edits", role: .destructive) {
                handleOutcome(store.overrideWithCurrentDraft(section: .measuringCondition))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was modified externally (checksum: \(pendingConflictChecksum.prefix(8))). Choose how to resolve.")
        }
        .confirmationDialog(deleteConfirmTitle(), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteConfirmMessage())
        }
    }

    // MARK: - Save bar

    @ViewBuilder
    private func saveBar() -> some View {
        HStack(spacing: AppSpacing.md) {
            if !saveErrors.isEmpty {
                Text("\(saveErrors.count) validation error\(saveErrors.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Spacer()
            if let d = draft {
                Text("Schema version \(d.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Discard") { discardEdits() }
                .buttonStyle(.bordered)
                .disabled(!store.dirtySections.contains(.measuringCondition))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(_ d: MeasuringConditionFileDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                batchGroup(d)
                conditionDefinitionsGroup(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Batch

    @ViewBuilder
    private func batchGroup(_ d: MeasuringConditionFileDraft) -> some View {
        GroupBox("Batch Identification") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Toggle("Prefer Sample ID", isOn: Binding(
                    get: { d.batch.preferSampleId },
                    set: { v in var u = d; u.batch.preferSampleId = v; apply(u) }
                ))
                Divider()
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text("Fallback Patterns").font(AppFontScale.groupHeader)
                        Spacer()
                        Button("Add") {
                            var u = d; u.batch.fallbackPatterns.append(""); apply(u)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ForEach(d.batch.fallbackPatterns.indices, id: \.self) { idx in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                RegexField(title: "regex pattern", text: Binding(
                                    get: { d.batch.fallbackPatterns[idx] },
                                    set: { v in var u = d; u.batch.fallbackPatterns[idx] = v; apply(u) }
                                ))
                            }
                            Button(role: .destructive) {
                                var u = d; u.batch.fallbackPatterns.remove(at: idx); apply(u)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove pattern")
                            .padding(.top, AppSpacing.xs)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Condition Definitions

    @ViewBuilder
    private func conditionDefinitionsGroup(_ d: MeasuringConditionFileDraft) -> some View {
        GroupBox("Conditions") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.conditionDefinitions.indices, id: \.self) { idx in
                    let def = d.conditionDefinitions[idx]
                    conditionRow(def: def, d: d, idx: idx)
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
    }

    @ViewBuilder
    private func conditionRow(
        def: MeasuringConditionFileDraft.ConditionDefinition,
        d: MeasuringConditionFileDraft,
        idx: Int
    ) -> some View {
        let isSelected = selectedConditionID == def.id
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                selectedConditionID = isSelected ? nil : def.id
            }) {
                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(def.id).font(.callout.weight(.semibold).monospaced())
                        HStack(spacing: AppSpacing.xs) {
                            Text(def.kind).font(.caption).foregroundStyle(.secondary)
                            if let label = def.label, !label.isEmpty {
                                Text("· \(label)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
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
            }
            .buttonStyle(.plain)
            .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
            .cornerRadius(AppSpacing.xs)

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
            LabeledContent("ID") {
                Text(def.id)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Label") {
                TextField("display label (optional)", text: Binding(
                    get: { def.label ?? "" },
                    set: { v in
                        var u = d
                        u.conditionDefinitions[idx].label = v.isEmpty ? nil : v
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
                        u.conditionDefinitions[idx].binding = canonicalBinding(kind: newKind, id: def.id)
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
                unitSuffixEditor(id: def.id, d: d, idx: idx)
            } else {
                tokenMapEditor(id: def.id, d: d, idx: idx)
            }
        }
    }

    @ViewBuilder
    private func unitSuffixEditor(id: String, d: MeasuringConditionFileDraft, idx: Int) -> some View {
        LabeledContent("Regex Pattern") {
            RegexField(title: "unit_suffix regex", text: Binding(
                get: { d.conditions.extraConditions[id] ?? "" },
                set: { v in
                    var u = d
                    u.conditions.extraConditions[id] = v
                    apply(u)
                }
            ))
        }
    }

    @ViewBuilder
    private func tokenMapEditor(id: String, d: MeasuringConditionFileDraft, idx: Int) -> some View {
        let rules = d.conditions.tokenMapRules[id] ?? []
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Match Rules").font(AppFontScale.groupHeader)
                Spacer()
                Button("Add Rule") {
                    var u = d
                    var updated = u.conditions.tokenMapRules[id] ?? []
                    updated.append(MapRule(match: .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: []), value: ""))
                    u.conditions.tokenMapRules[id] = updated
                    apply(u)
                    expandedTokenMapRuleIndices[id] = updated.count - 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(rules.indices, id: \.self) { ruleIdx in
                let isRuleSelected = expandedTokenMapRuleIndices[id] == ruleIdx
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button(action: {
                        if isRuleSelected {
                            expandedTokenMapRuleIndices.removeValue(forKey: id)
                        } else {
                            expandedTokenMapRuleIndices[id] = ruleIdx
                        }
                    }) {
                        HStack(spacing: AppSpacing.md) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text("→ \(rules[ruleIdx].value)").font(.callout.weight(.semibold))
                                Text("\(rules[ruleIdx].match.scope) · \(rules[ruleIdx].match.type)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                var u = d
                                var updated = u.conditions.tokenMapRules[id] ?? []
                                updated.remove(at: ruleIdx)
                                u.conditions.tokenMapRules[id] = updated
                                apply(u)
                                expandedTokenMapRuleIndices.removeValue(forKey: id)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            Image(systemName: isRuleSelected ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isRuleSelected {
                        MatchRuleEditor(rule: tokenMapRuleBinding(id: id, ruleIdx: ruleIdx, d: d))
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(AppSpacing.sm)
                    }
                }
            }
        }
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
        d.conditions.extraConditions.removeValue(forKey: id)
        d.conditions.tokenMapRules.removeValue(forKey: id)
        apply(d)
        if selectedConditionID == id { selectedConditionID = nil }
        expandedTokenMapRuleIndices.removeValue(forKey: id)
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
            label: nil,
            kind: "unit_suffix",
            binding: canonicalBinding(kind: "unit_suffix", id: newID)
        ))
        u.conditions.extraConditions[newID] = ""
        apply(u)
        selectedConditionID = newID
    }

    private func canonicalBinding(kind: String, id: String) -> String {
        switch kind {
        case "unit_suffix": return "conditions.extraConditions.\(id)"
        case "token_map":   return "conditions.tokenMapRules.\(id)"
        default:            return ""
        }
    }

    // MARK: - Bindings

    private func tokenMapRuleBinding(
        id: String,
        ruleIdx: Int,
        d: MeasuringConditionFileDraft
    ) -> Binding<MapRule> {
        Binding(
            get: {
                guard let d = self.draft,
                      let rules = d.conditions.tokenMapRules[id],
                      rules.indices.contains(ruleIdx) else {
                    return MapRule(match: .init(scope: "tokens", type: "equals", value: nil, values: nil), value: "")
                }
                return rules[ruleIdx]
            },
            set: { newValue in
                guard var d = self.draft,
                      var rules = d.conditions.tokenMapRules[id],
                      rules.indices.contains(ruleIdx) else { return }
                rules[ruleIdx] = newValue
                d.conditions.tokenMapRules[id] = rules
                self.apply(d)
            }
        )
    }

    // MARK: - Actions

    private func apply(_ d: MeasuringConditionFileDraft) {
        draft = d
        store.updateMeasuringCondition(d)
    }

    private func saveEdits() {
        store.selectSection(.measuringCondition)
        handleOutcome(store.saveCurrent())
    }

    private func discardEdits() {
        store.discardCurrent()
        syncFromStore()
        saveErrors = []
    }

    private func syncFromStore() {
        if let current = store.measuringConditionDraft { draft = current }
    }

    private func handleOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved, .savedWithMirrorWarning:
            saveErrors = []
        case .validationFailed(let errors):
            saveErrors = errors
        case .externalConflict(let checksum):
            pendingConflictChecksum = checksum
            showConflictAlert = true
        case .ioError(let error):
            saveErrors = [RulesPanelFieldError(field: "save", message: error.localizedDescription)]
        }
    }
}
