import SwiftUI

struct WorkflowRegistryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var isConfigurationExpanded = true

    var body: some View {
        @Bindable var workbench = appState.workbench

        VStack(alignment: .leading, spacing: 12) {
            if let message = workbench.workflowRegistryMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            CollapsibleSectionHeader(title: "Workflow Configuration", isExpanded: $isConfigurationExpanded)

            if isConfigurationExpanded {
                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Workflow Registry") {
                        VStack(alignment: .leading, spacing: 12) {
                            List(
                                selection: Binding<String?>(
                                    get: { workbench.selectedWorkflowID },
                                    set: { workbench.currentRoute = .registry(selectedID: $0) }
                                )
                            ) {
                                ForEach(workbench.workflowDefinitions) { definition in
                                    Text(definition.displayName.isEmpty ? definition.id : definition.displayName)
                                    .tag(Optional(definition.id))
                                }
                            }
                            .frame(minHeight: 220)

                            HStack {
                                Button("Add Workflow") {
                                    workbench.addWorkflow()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Remove") {
                                    workbench.removeSelectedWorkflow()
                                }
                                .buttonStyle(.bordered)
                                .disabled(workbench.selectedWorkflowDefinition == nil)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(minWidth: 260)

                    GroupBox("Workflow Detail") {
                        if let definition = workbench.selectedWorkflowDefinition {
                            WorkflowDefinitionEditor(definition: definition)
                        } else {
                            ContentUnavailableView(
                                "No Workflow Selected",
                                systemImage: "list.bullet.rectangle",
                                description: Text("Add a workflow or select one from the list.")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

private struct WorkflowDefinitionEditor: View {
    @Environment(SpinLabAppState.self) private var appState

    let definition: WorkflowDefinition

    var body: some View {
        @Bindable var workbench = appState.workbench

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "Display Name",
                    text: binding(
                        initial: definition.displayName,
                        update: { value in
                            workbench.updateSelectedWorkflow(
                                id: definition.id,
                                displayName: value,
                                parentID: definition.parentID
                            )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Parent Workflow ID (optional)",
                    text: binding(
                        initial: definition.parentID ?? "",
                        update: { value in
                            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            workbench.updateSelectedWorkflow(
                                id: definition.id,
                                displayName: definition.displayName,
                                parentID: normalized.isEmpty ? nil : normalized
                            )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Match Rules")
                        .font(.headline)
                    Text("Global parser rules for this workflow. Inbox matches files against these rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if workbench.selectedWorkflowMatchRules.isEmpty {
                        Text("No match rules for this workflow.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workbench.selectedWorkflowMatchRules) { rule in
                            HStack(alignment: .center, spacing: 8) {
                                Picker(
                                    "Scope",
                                    selection: Binding(
                                        get: { rule.scope },
                                        set: { workbench.updateMatchRuleScope(rule.id, scope: $0) }
                                    )
                                ) {
                                    Text("tokens").tag(FilenameRuleSet.MatchScope.tokens)
                                    Text("joined").tag(FilenameRuleSet.MatchScope.joined)
                                }
                                .labelsHidden()
                                .frame(width: 90)

                                Picker(
                                    "Type",
                                    selection: Binding(
                                        get: { rule.type },
                                        set: { workbench.updateMatchRuleType(rule.id, type: $0) }
                                    )
                                ) {
                                    ForEach(matchTypeOptions(for: rule.type), id: \.self) { option in
                                        Text(matchTypeLabel(option))
                                            .tag(option)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 170)

                                TextField(
                                    "match tokens (comma-separated for *Any)",
                                    text: Binding(
                                        get: { workbench.matchRuleValuesCSV(rule.id) },
                                        set: { workbench.updateMatchRuleValuesCSV(rule.id, csv: $0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    workbench.commitMatchRuleValuesCSV(rule.id)
                                }

                                Button(role: .destructive) {
                                    workbench.removeMatchRule(rule.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete rule")
                            }
                        }
                    }

                    Button {
                        workbench.addMatchRuleToSelectedWorkflow()
                    } label: {
                        Label("Add Match Rule", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 8) {
                        Button("Discard") {
                            workbench.discardWorkflowMatchRulesEdits()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!workbench.hasUnsavedWorkflowMatchRules)

                        Button("Confirm Save") {
                            workbench.confirmWorkflowMatchRulesSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!workbench.hasUnsavedWorkflowMatchRules)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Conditions")
                        .font(.headline)

                    if definition.conditionFields.isEmpty {
                        Text("No conditions selected.")
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(Array(definition.conditionFields.enumerated()), id: \.offset) { index, field in
                                ConditionChip(
                                    title: workbench.conditionLabel(for: field.definitionID),
                                    canMoveUp: index > 0,
                                    canMoveDown: index < definition.conditionFields.count - 1,
                                    onMoveUp: {
                                        guard appState.workbench.selectedWorkflowDefinition?.id == definition.id else { return }
                                        workbench.moveConditionFieldOnSelectedWorkflow(from: index, to: index - 1)
                                    },
                                    onMoveDown: {
                                        guard appState.workbench.selectedWorkflowDefinition?.id == definition.id else { return }
                                        workbench.moveConditionFieldOnSelectedWorkflow(from: index, to: index + 1)
                                    },
                                    onRemove: {
                                        guard appState.workbench.selectedWorkflowDefinition?.id == definition.id else { return }
                                        workbench.removeConditionFieldFromSelectedWorkflow(at: index)
                                    }
                                )
                            }
                        }
                    }

                    let selectedIDs = Set(definition.conditionFields.map(\.definitionID))
                    let availableOptions = workbench.conditionDefinitionOptions.filter { !selectedIDs.contains($0.id) }

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(availableOptions) { option in
                                Button(option.label) {
                                    guard appState.workbench.selectedWorkflowDefinition?.id == definition.id else { return }
                                    workbench.addConditionFieldToSelectedWorkflow(definitionID: option.id)
                                }
                            }
                        } label: {
                            Label("Add Condition", systemImage: "plus.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(availableOptions.isEmpty)

                        if availableOptions.isEmpty {
                            Text("All conditions are already selected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func binding(initial: String, update: @escaping (String) -> Void) -> Binding<String> {
        Binding(
            get: { initial },
            set: { update($0) }
        )
    }

    private func matchTypeOptions(for current: FilenameRuleSet.MatchType) -> [FilenameRuleSet.MatchType] {
        let preferred: [FilenameRuleSet.MatchType] = [.equals, .contains, .regex]
        if preferred.contains(current) {
            return preferred
        }
        return preferred + [current]
    }

    private func matchTypeLabel(_ type: FilenameRuleSet.MatchType) -> String {
        switch type {
        case .equals:
            return "equals"
        case .contains:
            return "contains"
        case .regex:
            return "regex"
        case .equalsAny:
            return "equalsAny (legacy)"
        case .containsAny:
            return "containsAny (legacy)"
        case .equalsOrContainsAny:
            return "equalsOrContainsAny (legacy)"
        }
    }
}

private struct ConditionChip: View {
    let title: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

