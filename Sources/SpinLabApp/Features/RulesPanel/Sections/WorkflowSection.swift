import SwiftUI

struct WorkflowSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: WorkflowFileDraft?

    @State private var expandedWorkflowID: String? = nil

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
        workflowsGroup(d, saveErrors: saveErrors.wrappedValue)
        measurementTagRulesGroup(d, saveErrors: saveErrors.wrappedValue)
            .errorHighlight(saveErrors.wrappedValue.hasGroup("measurementTagRules"))
    }

    @ViewBuilder
    private func workflowsGroup(
        _ d: WorkflowFileDraft,
        saveErrors: [RulesPanelFieldError]
    ) -> some View {
        GroupBox("Workflows") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Workflow order defines routing priority. First matching workflow wins.")
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(d.workflows) { entry in
                        workflowRow(d: d, entry: entry, saveErrors: saveErrors)
                    }
                }

                Button("+ Add Workflow") {
                    newWorkflowIDInput = ""
                    addWorkflowError = nil
                    showAddWorkflowSheet = true
                }
                .buttonStyle(.bordered)
                .padding(.top, AppSpacing.md)
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
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("workflow id", text: $newWorkflowIDInput)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit { confirmAddWorkflow(d: d) }

            if let err = addWorkflowError {
                Text(err)
                    .font(.callout)
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
        entry: WorkflowFileDraft.WorkflowEntry,
        saveErrors: [RulesPanelFieldError]
    ) -> some View {
        if let idx = workflowIndex(for: entry.id, in: d) {
            let isExpanded = expandedWorkflowID == entry.id
            let rowHasError = saveErrors.hasRow(group: "workflows", key: entry.id)
            let count = entry.matchRules.count

            RuleExpandableRow(
                title: entry.id,
                subtitle: "\(count) rule\(count == 1 ? "" : "s")",
                isExpanded: isExpanded,
                rowHasError: rowHasError,
                deleteAccessibilityLabel: "Delete workflow",
                onMoveUp: idx > 0 ? { moveWorkflow(id: entry.id, offset: -1) } : nil,
                onMoveDown: idx < d.workflows.count - 1 ? { moveWorkflow(id: entry.id, offset: 1) } : nil,
                onToggle: {
                    expandedWorkflowID = isExpanded ? nil : entry.id
                },
                onDelete: { requestDeleteWorkflow(id: entry.id) }
            ) {
                workflowDetail(d: d, workflowID: entry.id)
            }
        }
    }

    @ViewBuilder
    private func workflowDetail(d: WorkflowFileDraft, workflowID: String) -> some View {
        if let idx = workflowIndex(for: workflowID, in: d) {
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

                workflowMatchRulesEditor(d: d, idx: idx)
                conditionFieldIDsEditor(d: d, idx: idx)
            }
        }
    }

    @ViewBuilder
    private func workflowMatchRulesEditor(d: WorkflowFileDraft, idx: Int) -> some View {
        MatchRulesEditor(
            specs: workflowMatchSpecsBinding(d: d, workflowIdx: idx),
            allowedOps: [.equals, .contains],
            defaultOp: .equals
        )
    }

    private func workflowMatchSpecsBinding(d: WorkflowFileDraft, workflowIdx: Int) -> Binding<[FilenameRuleSet.MatchSpec]> {
        Binding(
            get: {
                guard let current = draft,
                      current.workflows.indices.contains(workflowIdx) else { return [] }
                return current.workflows[workflowIdx].matchRules.map {
                    FilenameRuleSet.MatchSpec(
                        type: FilenameRuleSet.Operation(rawValue: $0.type) ?? .equals,
                        value: $0.value
                    )
                }
            },
            set: { specs in
                guard var updated = draft,
                      updated.workflows.indices.contains(workflowIdx) else { return }
                updated.workflows[workflowIdx].matchRules = specs.map {
                    WorkflowFileDraft.WorkflowMatchSpec(type: $0.type.rawValue, value: $0.value)
                }
                apply(updated)
            }
        )
    }

    @ViewBuilder
    private func conditionFieldIDsEditor(d: WorkflowFileDraft, idx: Int) -> some View {
        let entry = d.workflows[idx]

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Condition Field IDs")
                .font(AppFontScale.groupHeader)

            if store.availableConditionFieldIDs.isEmpty {
                Text("No available condition field IDs")
                    .font(.callout)
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
            MatchRulesEditor(
                rules: Binding(
                    get: { draft?.measurementTagRules ?? [] },
                    set: { newRules in
                        guard var updated = draft else { return }
                        updated.measurementTagRules = newRules
                        apply(updated)
                    }
                ),
                allowedOps: [.equals, .contains],
                defaultOp: .equals,
                outputBehavior: .editable(title: "Tag")
            )
        }
        .errorHighlight(saveErrors.hasGroup("measurementTagRules"))
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
        pendingDeleteWorkflowID = nil
    }

    private func moveWorkflow(id: String, offset: Int) {
        guard var updated = draft,
              let currentIndex = updated.workflows.firstIndex(where: { $0.id == id }) else {
            return
        }
        let nextIndex = currentIndex + offset
        guard updated.workflows.indices.contains(nextIndex) else { return }
        updated.workflows.swapAt(currentIndex, nextIndex)
        apply(updated)
    }

    private func workflowIndex(for id: String, in draft: WorkflowFileDraft) -> Int? {
        draft.workflows.firstIndex(where: { $0.id == id })
    }

    private func deleteConfirmTitle() -> String {
        guard let id = pendingDeleteWorkflowID else { return "Delete Workflow" }
        return "Delete workflow '\(id)'?"
    }

    private func deleteConfirmMessage() -> String {
        "This removes workflow ID, display name, match rules, and condition field mappings."
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
