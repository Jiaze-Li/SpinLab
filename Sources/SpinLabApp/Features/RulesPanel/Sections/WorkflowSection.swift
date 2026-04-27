import SwiftUI

struct WorkflowSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: WorkflowFileDraft?

    @State private var expandedWorkflowID: String? = nil
    @State private var expandedWorkflowRuleIndexByID: [String: Int] = [:]
    @State private var expandedMeasurementTagRuleIndex: Int? = nil

    @State private var pendingDeleteWorkflowID: String? = nil
    @State private var showDeleteWorkflowConfirm = false

    @State private var showAddWorkflowSheet = false
    @State private var newWorkflowIDInput: String = ""
    @State private var addWorkflowError: String? = nil

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        RulesSectionShell(
            section: .workflow,
            isDraftAvailable: draft != nil,
            versionLabel: draft.map { "Schema version \($0.version)" },
            onSync: syncFromStore
        ) { saveErrors in
            if let d = draft {
                scrollContent(d, saveErrors: saveErrors)
            }
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
    private func scrollContent(
        _ d: WorkflowFileDraft,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                workflowsGroup(d, saveErrors: saveErrors.wrappedValue)
                measurementTagRulesGroup(d, saveErrors: saveErrors.wrappedValue)
                    .errorHighlight(saveErrors.wrappedValue.hasGroup("measurementTagRules"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    @ViewBuilder
    private func workflowsGroup(
        _ d: WorkflowFileDraft,
        saveErrors: [RulesPanelFieldError]
    ) -> some View {
        GroupBox("Workflows") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.workflows.indices, id: \.self) { idx in
                    workflowRow(d: d, idx: idx, saveErrors: saveErrors)
                    Divider()
                }

                Button("+ Add Workflow") {
                    newWorkflowIDInput = ""
                    addWorkflowError = nil
                    showAddWorkflowSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showAddWorkflowSheet) {
            addWorkflowSheet(d: d)
        }
    }

    @ViewBuilder
    private func addWorkflowSheet(d: WorkflowFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("New Workflow")
                .font(AppFontScale.sectionHeader)
            Text("Enter a unique ID. This cannot be changed after creation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("workflow id", text: $newWorkflowIDInput)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit { confirmAddWorkflow(d: d) }

            if let err = addWorkflowError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showAddWorkflowSheet = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    confirmAddWorkflow(d: d)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppSpacing.xl)
        .frame(minWidth: 360)
    }

    private func confirmAddWorkflow(d: WorkflowFileDraft) {
        let trimmed = newWorkflowIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            addWorkflowError = "ID cannot be empty."
            return
        }
        if d.workflows.contains(where: { $0.id == trimmed }) {
            addWorkflowError = "ID already exists."
            return
        }
        var updated = d
        updated.workflows.append(
            .init(
                id: trimmed,
                displayName: "",
                matchRules: [],
                conditionFieldIDs: []
            )
        )
        apply(updated)
        expandedWorkflowID = trimmed
        showAddWorkflowSheet = false
    }

    @ViewBuilder
    private func workflowRow(
        d: WorkflowFileDraft,
        idx: Int,
        saveErrors: [RulesPanelFieldError]
    ) -> some View {
        let entry = d.workflows[idx]
        let isExpanded = expandedWorkflowID == entry.id
        let rowHasError = saveErrors.hasRow(group: "workflows", key: entry.id)

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
                            .foregroundStyle(rowHasError ? Color.red : .primary)
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
                .padding(.horizontal, AppSpacing.xs)
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.accentColor.opacity(0.08) : .clear)
            .cornerRadius(AppSpacing.xs)
            .errorHighlight(rowHasError, cornerRadius: AppSpacing.xs)

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

            LabeledContent("ID") {
                Text(entry.id)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
                        .init(scope: "tokens", type: "equalsOrContainsAny", matchValues: [])
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
                                    .font(.subheadline.weight(.medium))
                                Text("\(entry.matchRules[ruleIdx].scope) · \(entry.matchRules[ruleIdx].type)")
                                    .font(.caption2)
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
                        UnifiedMatchRuleEditor(
                            type: workflowMatchRuleTypeBinding(workflowIdx: idx, ruleIdx: ruleIdx),
                            matchValues: workflowMatchRuleValuesBinding(workflowIdx: idx, ruleIdx: ruleIdx)
                        )
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
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 200), spacing: AppSpacing.sm, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: AppSpacing.xxs
                ) {
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
    }

    @ViewBuilder
    private func measurementTagRulesGroup(
        _ d: WorkflowFileDraft,
        saveErrors: [RulesPanelFieldError]
    ) -> some View {
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
                                match: .init(scope: "tokens", type: "equalsOrContainsAny", matchValues: []),
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
                                    Text(d.measurementTagRules[idx].match.type)
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
                            UnifiedMatchRuleEditor(
                                type: measurementTagRuleTypeBinding(idx: idx),
                                matchValues: measurementTagRuleValuesBinding(idx: idx),
                                outputBinding: measurementTagRuleOutputBinding(idx: idx)
                            )
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
        rule.matchValues.isEmpty ? "(empty)" : rule.matchValues.joined(separator: ", ")
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

    private func workflowMatchRuleTypeBinding(workflowIdx: Int, ruleIdx: Int) -> Binding<String> {
        Binding(
            get: {
                guard let d = draft,
                      d.workflows.indices.contains(workflowIdx),
                      d.workflows[workflowIdx].matchRules.indices.contains(ruleIdx) else {
                    return "equals"
                }
                return d.workflows[workflowIdx].matchRules[ruleIdx].type
            },
            set: { newValue in
                guard var d = draft,
                      d.workflows.indices.contains(workflowIdx),
                      d.workflows[workflowIdx].matchRules.indices.contains(ruleIdx) else { return }
                d.workflows[workflowIdx].matchRules[ruleIdx].type = newValue
                apply(d)
            }
        )
    }

    private func workflowMatchRuleValuesBinding(workflowIdx: Int, ruleIdx: Int) -> Binding<[String]> {
        Binding(
            get: {
                guard let d = draft,
                      d.workflows.indices.contains(workflowIdx),
                      d.workflows[workflowIdx].matchRules.indices.contains(ruleIdx) else {
                    return []
                }
                return d.workflows[workflowIdx].matchRules[ruleIdx].matchValues
            },
            set: { newValue in
                guard var d = draft,
                      d.workflows.indices.contains(workflowIdx),
                      d.workflows[workflowIdx].matchRules.indices.contains(ruleIdx) else { return }
                d.workflows[workflowIdx].matchRules[ruleIdx].matchValues = newValue
                apply(d)
            }
        )
    }

    private func measurementTagRuleTypeBinding(idx: Int) -> Binding<String> {
        Binding(
            get: {
                guard let d = draft,
                      d.measurementTagRules.indices.contains(idx) else {
                    return "equals"
                }
                return d.measurementTagRules[idx].match.type
            },
            set: { newValue in
                guard var d = draft,
                      d.measurementTagRules.indices.contains(idx) else { return }
                d.measurementTagRules[idx].match.type = newValue
                apply(d)
            }
        )
    }

    private func measurementTagRuleValuesBinding(idx: Int) -> Binding<[String]> {
        Binding(
            get: {
                guard let d = draft,
                      d.measurementTagRules.indices.contains(idx) else {
                    return []
                }
                return d.measurementTagRules[idx].match.matchValues
            },
            set: { newValue in
                guard var d = draft,
                      d.measurementTagRules.indices.contains(idx) else { return }
                d.measurementTagRules[idx].match.matchValues = newValue
                apply(d)
            }
        )
    }

    private func measurementTagRuleOutputBinding(idx: Int) -> Binding<String> {
        Binding(
            get: {
                guard let d = draft,
                      d.measurementTagRules.indices.contains(idx) else {
                    return ""
                }
                return d.measurementTagRules[idx].value
            },
            set: { newValue in
                guard var d = draft,
                      d.measurementTagRules.indices.contains(idx) else { return }
                d.measurementTagRules[idx].value = newValue
                apply(d)
            }
        )
    }

    private func apply(_ updated: WorkflowFileDraft) {
        draft = updated
        store.updateWorkflow(updated)
    }

    private func syncFromStore() {
        if let current = store.workflowDraft {
            draft = current
        }
    }
}
