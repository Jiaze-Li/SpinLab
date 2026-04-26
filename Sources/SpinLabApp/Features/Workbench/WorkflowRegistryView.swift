import SwiftUI

struct WorkflowRegistryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var workbench = appState.workbench

        HStack(alignment: .top, spacing: 0) {
            workflowList(workbench: workbench)
                .frame(width: 220)

            Divider()

            workflowSummary(workbench: workbench)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func workflowList(workbench: WorkbenchFeatureStore) -> some View {
        List(
            workbench.workflowDefinitions,
            id: \.id,
            selection: Binding<String?>(
                get: { workbench.selectedWorkflowID },
                set: { id in
                    if let id {
                        workbench.selectWorkflow(id)
                    }
                }
            )
        ) { definition in
            Text(definition.displayName.isEmpty ? definition.id : definition.displayName)
                .tag(Optional(definition.id))
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func workflowSummary(workbench: WorkbenchFeatureStore) -> some View {
        if let definition = workbench.selectedWorkflowDefinition,
           let entry = appState.rulesPanel.workflowDraft?.workflows.first(where: {
               $0.id.caseInsensitiveCompare(definition.id) == .orderedSame
           }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryField("ID", value: definition.id)
                    summaryField("Display Name", value: definition.displayName)
                    conditionFieldsSection(definition: definition, workbench: workbench)
                    matchRulesSection(entry: entry)
                    editButton
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Workflow Selected",
                systemImage: "list.bullet.rectangle",
                description: Text("Select a workflow from the list.")
            )
        }
    }

    private func summaryField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
        }
    }

    private func conditionFieldsSection(
        definition: WorkflowDefinition,
        workbench: WorkbenchFeatureStore
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conditions")
                .font(.caption)
                .foregroundStyle(.secondary)
            if definition.conditionFields.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(definition.conditionFields, id: \.definitionID) { field in
                    Text(workbench.conditionLabel(for: field.definitionID))
                        .font(.body)
                }
            }
        }
    }

    private func matchRulesSection(entry: WorkflowFileDraft.WorkflowEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Match Rules")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.matchRules.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.matchRules.enumerated()), id: \.offset) { _, rule in
                    Text(matchRuleSummary(rule))
                        .font(.body.monospaced())
                }
            }
        }
    }

    private var editButton: some View {
        Button("在规则面板编辑此工作流") {
            appState.rulesPanel.selectSection(.workflow)
            openWindow(id: "spin-rules")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func matchRuleSummary(_ rule: WorkflowFileDraft.WorkflowMatchSpec) -> String {
        let scopePart = rule.scope
        let typePart = rule.type
        if rule.matchValues.count == 1 {
            return "\(scopePart) \(typePart) \"\(rule.matchValues[0])\""
        }
        if !rule.matchValues.isEmpty {
            return "\(scopePart) \(typePart) [\(rule.matchValues.joined(separator: ", "))]"
        }
        return "\(scopePart) \(typePart)"
    }
}
