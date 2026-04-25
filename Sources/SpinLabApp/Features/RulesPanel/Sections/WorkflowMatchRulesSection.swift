import SwiftUI

struct WorkflowMatchRulesSection: View {
    let store: RulesManagementStore

    @State private var draft = WorkflowMatchRulesFileDraft(version: 1, rules: [])
    @State private var selectedRuleID: UUID?
    @State private var saveErrors: [RulesPanelFieldError] = []

    private let scopeOptions = ["tokens", "joined"]
    private let typeOptions = ["equals", "equalsAny", "contains", "containsAny", "equalsOrContainsAny", "regex"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            saveButton

            Text(RulesPanelSection.workflowMatch.displayName)
                .font(AppFontScale.sectionHeader)

            HStack(alignment: .top, spacing: AppSpacing.xl) {
                masterList
                    .frame(minWidth: 280, maxWidth: 340)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if !saveErrors.isEmpty {
                validationErrorBlock
            }

            saveButton
        }
        .onAppear {
            if let existing = store.workflowMatchDraft {
                draft = existing
                selectedRuleID = existing.rules.first?.id
            }
        }
    }

    private var saveButton: some View {
        Button("Save") {
            pushDraftUpdate()
            handleSaveOutcome(store.saveCurrent())
        }
        .disabled(!saveErrors.isEmpty)
    }

    private var masterList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Button("Add Rule") {
                    let rule = WorkflowMatchRulesFileDraft.WorkflowMatchRule()
                    draft.rules.append(rule)
                    selectedRuleID = rule.id
                    pushDraftUpdate()
                }
                .buttonStyle(.bordered)

                Button("Delete") {
                    deleteSelectedRule()
                }
                .buttonStyle(.bordered)
                .disabled(currentRule == nil)
            }

            List(selection: $selectedRuleID) {
                ForEach(draft.rules) { rule in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(rule.workflowID.isEmpty ? "(empty workflowID)" : rule.workflowID)
                        Text("\(rule.scope) / \(rule.type)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(rule.id)
                }
            }
            .frame(minHeight: 260)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let rule = currentRule {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Picker("Workflow ID", selection: bindingForRule(rule.id, keyPath: \.workflowID)) {
                    if rule.workflowID.isEmpty {
                        Text("(empty)").tag("")
                    }
                    ForEach(store.availableWorkflowIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }

                if !rule.workflowID.isEmpty && !store.availableWorkflowIDs.contains(rule.workflowID) {
                    Text("Current workflowID is not in available workflow list.")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Picker("Scope", selection: bindingForRule(rule.id, keyPath: \.scope)) {
                    ForEach(scopeOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }

                Picker("Type", selection: bindingForRule(rule.id, keyPath: \.type)) {
                    ForEach(typeOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }

                matchValuesEditor(for: rule.id)
            }
        } else {
            Text("Select a rule to edit.")
                .foregroundStyle(.secondary)
        }
    }

    private var currentRule: WorkflowMatchRulesFileDraft.WorkflowMatchRule? {
        guard let selectedRuleID else { return nil }
        return draft.rules.first(where: { $0.id == selectedRuleID })
    }

    private var validationErrorBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Validation Errors")
                .font(AppFontScale.groupHeader)
                .foregroundStyle(.red)
            ForEach(saveErrors) { error in
                Text("• [\(error.field)] \(error.message)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func bindingForRule(
        _ id: UUID,
        keyPath: WritableKeyPath<WorkflowMatchRulesFileDraft.WorkflowMatchRule, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let idx = draft.rules.firstIndex(where: { $0.id == id }) else { return "" }
                return draft.rules[idx][keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = draft.rules.firstIndex(where: { $0.id == id }) else { return }
                draft.rules[idx][keyPath: keyPath] = newValue
                pushDraftUpdate()
            }
        )
    }

    private func matchValuesEditor(for id: UUID) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Match Values")
                .font(AppFontScale.groupHeader)

            ForEach(Array(matchValues(for: id).enumerated()), id: \.offset) { index, _ in
                HStack(spacing: AppSpacing.sm) {
                    TextField("Value", text: bindingForMatchValue(ruleID: id, valueIndex: index))
                        .textFieldStyle(.roundedBorder)
                    Button("-") { removeMatchValue(ruleID: id, valueIndex: index) }
                        .buttonStyle(.bordered)
                }
            }

            Button("Add Value") {
                appendMatchValue(ruleID: id)
            }
            .buttonStyle(.bordered)
        }
    }

    private func matchValues(for id: UUID) -> [String] {
        guard let idx = draft.rules.firstIndex(where: { $0.id == id }) else { return [] }
        return draft.rules[idx].matchValues
    }

    private func bindingForMatchValue(ruleID: UUID, valueIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard
                    let ruleIndex = draft.rules.firstIndex(where: { $0.id == ruleID }),
                    draft.rules[ruleIndex].matchValues.indices.contains(valueIndex)
                else { return "" }
                return draft.rules[ruleIndex].matchValues[valueIndex]
            },
            set: { newValue in
                guard
                    let ruleIndex = draft.rules.firstIndex(where: { $0.id == ruleID }),
                    draft.rules[ruleIndex].matchValues.indices.contains(valueIndex)
                else { return }
                draft.rules[ruleIndex].matchValues[valueIndex] = newValue
                pushDraftUpdate()
            }
        )
    }

    private func appendMatchValue(ruleID: UUID) {
        guard let ruleIndex = draft.rules.firstIndex(where: { $0.id == ruleID }) else { return }
        draft.rules[ruleIndex].matchValues.append("")
        pushDraftUpdate()
    }

    private func removeMatchValue(ruleID: UUID, valueIndex: Int) {
        guard
            let ruleIndex = draft.rules.firstIndex(where: { $0.id == ruleID }),
            draft.rules[ruleIndex].matchValues.indices.contains(valueIndex)
        else { return }

        draft.rules[ruleIndex].matchValues.remove(at: valueIndex)
        pushDraftUpdate()
    }

    private func deleteSelectedRule() {
        guard let selectedRuleID, let index = draft.rules.firstIndex(where: { $0.id == selectedRuleID }) else { return }
        draft.rules.remove(at: index)
        self.selectedRuleID = draft.rules.first?.id
        pushDraftUpdate()
    }

    private func pushDraftUpdate() {
        store.updateWorkflowMatch(draft)
        saveErrors = []
    }

    private func handleSaveOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved:
            saveErrors = []
        case .validationFailed(let errors):
            saveErrors = errors
        case .externalConflict(let checksum):
            saveErrors = [RulesPanelFieldError(field: "externalConflict", message: "External change detected (\(checksum)). Reload and retry.")]
        case .ioError(let error):
            saveErrors = [RulesPanelFieldError(field: "ioError", message: error.localizedDescription)]
        }
    }
}
