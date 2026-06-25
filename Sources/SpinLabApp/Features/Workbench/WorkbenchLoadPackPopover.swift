import SwiftUI

private struct WorkbenchVaultRow<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState

    let pack: AnalysisPack
    @Binding var editingPackID: UUID?
    let store: Store
    var onLoad: ((AnalysisPack.ID) -> Void)? = nil

    @State private var editingLabel = ""

    private var isEditing: Bool { editingPackID == pack.id }

    var body: some View {
        let vault = appState.workbench.analysisVault
        let isActive = store.activePackID == pack.id

        HStack(spacing: AppSpacing.sm) {
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
            }

            if isEditing {
                TextField("Label", text: $editingLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit { commitRename(vault: vault) }
            } else {
                Text(pack.label)
                    .font(.body)
                    .lineLimit(1)
            }

            Spacer()

            if !isEditing {
                Button {
                    editingLabel = pack.label
                    editingPackID = pack.id
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .accessibilityLabel("Rename pack")

                Button {
                    vault.remove(id: pack.id)
                    if store.activePackID == pack.id {
                        store.activePackID = nil
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityLabel("Delete pack")
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.sm)
        .background(isActive ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            onLoad?(pack.id)
        }
    }

    private func commitRename(vault: AnalysisVault) {
        let trimmed = editingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, var updated = vault.get(id: pack.id) {
            updated.label = trimmed
            vault.update(updated)
        }
        editingPackID = nil
    }
}

struct WorkbenchLoadPackPopover<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: String
    let store: Store

    @State private var showPopover = false
    @State private var showUnsavedAlert = false
    @State private var pendingLoadID: UUID?
    @State private var editingPackID: UUID?
    @State private var filterText = ""

    var body: some View {
        let vault = appState.workbench.analysisVault
        let allPacks = vault.packs(forWorkflow: workflowID)
        let packs = filterText.isEmpty ? allPacks : allPacks.filter {
            $0.label.localizedCaseInsensitiveContains(filterText)
        }

        Button("Load") {
            showPopover.toggle()
        }
        .buttonStyle(.bordered)
        .disabled(allPacks.isEmpty)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Saved Analyses")
                    .font(.body.bold())
                    .foregroundStyle(.secondary)

                if allPacks.count > 3 {
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                }

                if packs.isEmpty {
                    Text(filterText.isEmpty ? "No saved analyses." : "No match.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(packs) { pack in
                                WorkbenchVaultRow(
                                    pack: pack,
                                    editingPackID: $editingPackID,
                                    store: store,
                                    onLoad: { id in
                                        if store.hasUnsavedAnalysis {
                                            pendingLoadID = id
                                            showPopover = false
                                            showUnsavedAlert = true
                                        } else {
                                            load(id)
                                            showPopover = false
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            .padding(AppSpacing.lg)
            .frame(width: 300)
            .onTapGesture { editingPackID = nil }
        }
        .alert("Unsaved Analysis", isPresented: $showUnsavedAlert) {
            Button("Discard & Load", role: .destructive) {
                if let id = pendingLoadID {
                    load(id)
                }
                pendingLoadID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLoadID = nil
            }
        } message: {
            Text("Current analysis has unsaved changes. Loading will replace it.")
        }
        .onChange(of: showPopover) { _, isOpen in
            if !isOpen {
                editingPackID = nil
                filterText = ""
            }
        }
    }

    private func load(_ id: AnalysisPack.ID) {
        // WorkflowKey used here only to key into workspace UI search state (not persisted as workflow identity).
        let wfID: WorkflowKey? = WorkflowKey(rawValue: workflowID)
        store.loadPack(
            id: id,
            restoreSearchState: { results, queryText in
                guard let wfID else { return }
                appState.workbench.restoreSearchState(results: results, queryText: queryText, for: wfID)
            },
            seedSelection: { ids, hits in
                guard let wfID else { return }
                appState.workbench.seedSelection(ids, hits: hits, for: wfID)
            }
        )
        if let plotDefaultsStore = store as? any WorkbenchGlobalPlotDefaultsProviding {
            appState.workbench.globalPlotDefaults = plotDefaultsStore.globalPlotDefaults
        }
    }
}
