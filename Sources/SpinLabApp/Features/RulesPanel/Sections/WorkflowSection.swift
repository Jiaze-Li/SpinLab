import SwiftUI

struct WorkflowSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: WorkflowFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""

    @State private var expandedWorkflowID: String? = nil
    @State private var expandedWorkflowRuleIndexByID: [String: Int] = [:]
    @State private var expandedMeasurementTagRuleIndex: Int? = nil

    @State private var pendingDeleteWorkflowID: String? = nil
    @State private var showDeleteWorkflowConfirm = false

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        VStack(spacing: 0) {
            saveBar()
            Divider()
            Group {
                if let d = draft {
                    scrollContent(d)
                } else {
                    ContentUnavailableView("No workflow rules loaded", systemImage: "doc.questionmark")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { syncFromStore() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: .workflow)
                syncFromStore()
            }
            Button("Override With My Edits", role: .destructive) {
                handleOutcome(store.overrideWithCurrentDraft(section: .workflow))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was modified externally (checksum: \(pendingConflictChecksum.prefix(8))). Choose how to resolve.")
        }
        .confirmationDialog(
            deleteConfirmTitle(),
            isPresented: $showDeleteWorkflowConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDeleteWorkflow() }
            Button("Cancel", role: .cancel) { pendingDeleteWorkflowID = nil }
        } message: {
            Text(deleteConfirmMessage())
        }
    }

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
                .disabled(!store.dirtySections.contains(.workflow))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    @ViewBuilder
    private func scrollContent(_ d: WorkflowFileDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                workflowsGroup(d)
                measurementTagRulesGroup(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    @ViewBuilder
    private func workflowsGroup(_ d: WorkflowFileDraft) -> some View {
        GroupBox("Workflows") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.workflows.indices, id: \.self) { idx in
                    workflowRow(d: d, idx: idx)
                    Divider()
                }

                Button("+ Add Workflow") {
                    addWorkflow(to: d)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func workflowRow(d: WorkflowFileDraft, idx: Int) -> some View {
        let entry = d.workflows[idx]
        let isExpanded = expandedWorkflowID == entry.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    expandedWorkflowID = nil
                } else {
                    expandedWorkflowID = entry.id
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(entry.id)
                            .font(.callout.weight(.semibold).monospaced())
                        if !entry.displayName.isEmpty {
                            Text(entry.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(entry.matchRules.count) rule\(entry.matchRules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        requestDeleteWorkflow(id: entry.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete workflow")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, AppSpacing.xs)
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.accentColor.opacity(0.08) : .clear)
            .cornerRadius(AppSpacing.xs)

            if isExpanded {
                workflowDetail(d: d, idx: idx)
                    .padding(AppSpacing.md)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(AppSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func workflowDetail(d: WorkflowFileDraft, idx: Int) -> some View {
        let entry = d.workflows[idx]

        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("ID") {
                TextField(
                    "workflow id",
                    text: Binding(
                        get: { entry.id },
                        set: { newValue in
                            var updated = d
                            let oldID = updated.workflows[idx].id
                            updated.workflows[idx].id = newValue
                            apply(updated)
                            if expandedWorkflowID == oldID {
                                expandedWorkflowID = newValue
                            }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }

            LabeledContent("Display Name") {
                TextField(
                    "display name",
                    text: Binding(
                        get: { entry.displayName },
                        set: { newValue in
                            var updated = d
                            updated.workflows[idx].displayName = newValue
                            apply(updated)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

            workflowMatchRulesEditor(d: d, idx: idx)
            conditionFieldIDsEditor(d: d, idx: idx)
        }
    }

    @ViewBuilder
    private func workflowMatchRulesEditor(d: WorkflowFileDraft, idx: Int) -> some View {
        let entry = d.workflows[idx]
        let workflowID = entry.id

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Match Rules")
                    .font(AppFontScale.groupHeader)
                Spacer()
                Button("Add Rule") {
                    var updated = d
                    updated.workflows[idx].matchRules.append(
                        .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: [])
                    )
                    apply(updated)
                    expandedWorkflowRuleIndexByID[workflowID] = updated.workflows[idx].matchRules.count - 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(entry.matchRules.indices, id: \.self) { ruleIdx in
                let isRuleExpanded = expandedWorkflowRuleIndexByID[workflowID] == ruleIdx

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button {
                        if isRuleExpanded {
                            expandedWorkflowRuleIndexByID.removeValue(forKey: workflowID)
                        } else {
                            expandedWorkflowRuleIndexByID[workflowID] = ruleIdx
                        }
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(ruleHeadline(entry.matchRules[ruleIdx]))
                                    .font(.callout.weight(.semibold))
                                Text("\(entry.matchRules[ruleIdx].scope) · \(entry.matchRules[ruleIdx].type)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                var updated = d
                                updated.workflows[idx].matchRules.remove(at: ruleIdx)
                                apply(updated)
                                expandedWorkflowRuleIndexByID.removeValue(forKey: workflowID)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove rule")
                            Image(systemName: isRuleExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isRuleExpanded {
                        WorkflowMatchRuleEditor(spec: workflowMatchRuleBinding(workflowIdx: idx, ruleIdx: ruleIdx))
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(AppSpacing.sm)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conditionFieldIDsEditor(d: WorkflowFileDraft, idx: Int) -> some View {
        let entry = d.workflows[idx]

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Condition Field IDs")
                .font(AppFontScale.groupHeader)

            if store.availableConditionFieldIDs.isEmpty {
                Text("No available condition field IDs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.availableConditionFieldIDs, id: \.self) { conditionID in
                    Toggle(
                        conditionID,
                        isOn: Binding(
                            get: { entry.conditionFieldIDs.contains(conditionID) },
                            set: { isOn in
                                var updated = d
                                var ids = updated.workflows[idx].conditionFieldIDs
                                if isOn {
                                    if !ids.contains(conditionID) {
                                        ids.append(conditionID)
                                    }
                                } else {
                                    ids.removeAll { $0 == conditionID }
                                }
                                updated.workflows[idx].conditionFieldIDs = ids
                                apply(updated)
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    @ViewBuilder
    private func measurementTagRulesGroup(_ d: WorkflowFileDraft) -> some View {
        GroupBox("Measurement Tag Rules") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("Map Rules")
                        .font(AppFontScale.groupHeader)
                    Spacer()
                    Button("Add Rule") {
                        var updated = d
                        updated.measurementTagRules.append(
                            MapRule(
                                match: .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: []),
                                value: ""
                            )
                        )
                        apply(updated)
                        expandedMeasurementTagRuleIndex = updated.measurementTagRules.count - 1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(d.measurementTagRules.indices, id: \.self) { idx in
                    let isExpanded = expandedMeasurementTagRuleIndex == idx

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Button {
                            if isExpanded {
                                expandedMeasurementTagRuleIndex = nil
                            } else {
                                expandedMeasurementTagRuleIndex = idx
                            }
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text("→ \(d.measurementTagRules[idx].value)")
                                        .font(.callout.weight(.semibold))
                                    Text("\(d.measurementTagRules[idx].match.scope) · \(d.measurementTagRules[idx].match.type)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    var updated = d
                                    updated.measurementTagRules.remove(at: idx)
                                    apply(updated)
                                    if expandedMeasurementTagRuleIndex == idx {
                                        expandedMeasurementTagRuleIndex = nil
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove rule")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            MatchRuleEditor(rule: measurementTagRuleBinding(idx: idx))
                                .padding(AppSpacing.md)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .cornerRadius(AppSpacing.sm)
                        }
                    }
                }
            }
        }
    }

    private func ruleHeadline(_ rule: WorkflowFileDraft.WorkflowMatchSpec) -> String {
        if let value = rule.value, !value.isEmpty {
            return value
        }
        if let values = rule.values, !values.isEmpty {
            return values.joined(separator: ", ")
        }
        return "(empty)"
    }

    private func addWorkflow(to d: WorkflowFileDraft) {
        var newID = "workflow"
        let existing = Set(d.workflows.map(\.id))
        var n = 2
        while existing.contains(newID) {
            newID = "workflow_\(n)"
            n += 1
        }

        var updated = d
        updated.workflows.append(
            .init(
                id: newID,
                displayName: "",
                matchRules: [],
                conditionFieldIDs: []
            )
        )
        apply(updated)
        expandedWorkflowID = newID
    }

    private func requestDeleteWorkflow(id: String) {
        pendingDeleteWorkflowID = id
        showDeleteWorkflowConfirm = true
    }

    private func performDeleteWorkflow() {
        guard let id = pendingDeleteWorkflowID, var d = draft else { return }
        d.workflows.removeAll { $0.id == id }
        apply(d)
        if expandedWorkflowID == id {
            expandedWorkflowID = nil
        }
        expandedWorkflowRuleIndexByID.removeValue(forKey: id)
        pendingDeleteWorkflowID = nil
    }

    private func deleteConfirmTitle() -> String {
        guard let id = pendingDeleteWorkflowID else { return "Delete Workflow" }
        return "Delete workflow '\(id)'?"
    }

    private func deleteConfirmMessage() -> String {
        "This removes workflow ID, display name, match rules, and condition field mappings."
    }

    private func workflowMatchRuleBinding(workflowIdx: Int, ruleIdx: Int) -> Binding<WorkflowFileDraft.WorkflowMatchSpec> {
        Binding(
            get: {
                guard let d = draft,
                      d.workflows.indices.contains(workflowIdx),
                      d.workflows[workflowIdx].matchRules.indices.contains(ruleIdx) else {
                    return .init(scope: "tokens", type: "equals", value: nil, values: nil)
                }
                return d.workflows[workflowIdx].matchRules[ruleIdx]
            },
            set: { newValue in
                guard var d = draft,
                      d.workflows.indices.contains(workflowIdx),
                      d.workflows[workflowIdx].matchRules.indices.contains(ruleIdx) else { return }
                d.workflows[workflowIdx].matchRules[ruleIdx] = newValue
                apply(d)
            }
        )
    }

    private func measurementTagRuleBinding(idx: Int) -> Binding<MapRule> {
        Binding(
            get: {
                guard let d = draft,
                      d.measurementTagRules.indices.contains(idx) else {
                    return MapRule(match: .init(scope: "tokens", type: "equals", value: nil, values: nil), value: "")
                }
                return d.measurementTagRules[idx]
            },
            set: { newValue in
                guard var d = draft,
                      d.measurementTagRules.indices.contains(idx) else { return }
                d.measurementTagRules[idx] = newValue
                apply(d)
            }
        )
    }

    private func apply(_ updated: WorkflowFileDraft) {
        draft = updated
        store.updateWorkflow(updated)
    }

    private func saveEdits() {
        store.selectSection(.workflow)
        handleOutcome(store.saveCurrent())
    }

    private func discardEdits() {
        store.discardCurrent()
        syncFromStore()
        saveErrors = []
    }

    private func syncFromStore() {
        if let current = store.workflowDraft {
            draft = current
        }
    }

    private func handleOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved:
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
