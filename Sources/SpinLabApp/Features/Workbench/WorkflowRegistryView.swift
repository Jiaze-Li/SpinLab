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

            Button {
                isConfigurationExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isConfigurationExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Workflow Configuration")
                        .font(.title3.weight(.semibold))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isConfigurationExpanded {
                HStack(spacing: 16) {
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
                                parentID: definition.parentID,
                                aliases: definition.aliases
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
                                parentID: normalized.isEmpty ? nil : normalized,
                                aliases: definition.aliases
                            )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Aliases (comma-separated, optional)",
                    text: binding(
                        initial: definition.aliases.joined(separator: ", "),
                        update: { value in
                            workbench.updateSelectedWorkflowAliasesCSV(value)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)

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

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + lineHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            view.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
