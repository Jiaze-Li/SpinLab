import SwiftUI

struct LibraryRegistrySection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: LibraryRegistryFileDraft?

    private var store: RulesManagementStore { appState.rulesPanel }

    @State private var repairError: String?
    @State private var showRepairConfirm = false

    private var loadState: LibraryRegistryLoadState { store.libraryRegistryLoadState }

    var body: some View {
        RulesSectionShell(
            section: .libraryRegistry,
            isDraftAvailable: draft != nil,
            versionLabel: draft.map { "Schema version \($0.version)" },
            onSync: syncFromStore,
            onCreateFromDefaults: loadState == .corrupt ? { showRepairConfirm = true } : nil,
            createFromDefaultsLabel: "Repair from legacy defaults",
            emptyStateTitle: loadState == .corrupt
                ? "Registry import rules are damaged"
                : "Registry import rules are missing",
            emptyStateMessage: loadState == .corrupt
                ? "The file exists but could not be read. Repair it to restore the previous default aliases."
                : "Restart the app or reconfigure the Rules Book to seed defaults automatically."
        ) { $saveErrors in
            if let d = draft {
                scrollContent(d, saveErrors: $saveErrors)
            }
        }
        .confirmationDialog("Repair from legacy defaults?",
                            isPresented: $showRepairConfirm,
                            titleVisibility: .visible) {
            Button("Repair", role: .destructive) { performRepair() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The existing file will be backed up and replaced with the pre-5.4.1 default aliases.")
        }
        .alert("Repair failed", isPresented: Binding(
            get: { repairError != nil },
            set: { if !$0 { repairError = nil } }
        )) {
            Button("OK", role: .cancel) { repairError = nil }
        } message: {
            Text(repairError ?? "")
        }
    }

    private func performRepair() {
        switch store.repairLibraryRegistryFromLegacyDefaults() {
        case .success:
            syncFromStore()
        case .failure(let error):
            repairError = error.localizedDescription
        }
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(_ d: LibraryRegistryFileDraft, saveErrors: Binding<[RulesPanelFieldError]>) -> some View {
        // Import Parsing group
        aliasListEditor(
            title: "Sample Header Aliases",
            subtitle: "Column headers that identify the sample ID in registry spreadsheets",
            field: "registry.sampleHeaderAliases",
            items: d.registry.sampleHeaderAliases,
            saveErrors: saveErrors.wrappedValue,
            onChange: { v in patch(d) { $0.registry.sampleHeaderAliases = v } }
        )

        aliasListEditor(
            title: "Batch Header Aliases",
            subtitle: "Column headers that identify the batch in registry spreadsheets",
            field: "registry.batchHeaderAliases",
            items: d.registry.batchHeaderAliases,
            saveErrors: saveErrors.wrappedValue,
            onChange: { v in patch(d) { $0.registry.batchHeaderAliases = v } }
        )

        aliasListEditor(
            title: "Substrate Header Aliases",
            subtitle: "Column headers that identify the substrate column",
            field: "registry.substrateHeaderAliases",
            items: d.registry.substrateHeaderAliases,
            saveErrors: saveErrors.wrappedValue,
            onChange: { v in patch(d) { $0.registry.substrateHeaderAliases = v } }
        )

        aliasListEditor(
            title: "Excluded Sheet Names",
            subtitle: "Sheets with these exact names are skipped during registry parsing",
            field: "registry.excludedSheetNames",
            items: d.registry.excludedSheetNames,
            saveErrors: saveErrors.wrappedValue,
            onChange: { v in patch(d) { $0.registry.excludedSheetNames = v } }
        )

        separatorsEditor(
            value: d.registry.sampleCellSeparators,
            onChange: { v in patch(d) { $0.registry.sampleCellSeparators = v } }
        )

        numericKeyAliasesEditor(
            aliases: d.registry.numericKeyAliases,
            saveErrors: saveErrors.wrappedValue,
            onChange: { v in patch(d) { $0.registry.numericKeyAliases = v } }
        )

        metadataLookupAliasesEditor(
            aliases: d.registry.metadataLookupAliases,
            saveErrors: saveErrors.wrappedValue,
            onChange: { v in patch(d) { $0.registry.metadataLookupAliases = v } }
        )
    }

    // MARK: - Alias list editor ([String])

    @ViewBuilder
    private func aliasListEditor(
        title: String,
        subtitle: String,
        field: String,
        items: [String],
        saveErrors: [RulesPanelFieldError],
        onChange: @escaping ([String]) -> Void
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Spacer()
                    Button("Add") { onChange(items + [""]) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                ForEach(items.indices, id: \.self) { idx in
                    HStack(spacing: AppSpacing.sm) {
                        TextField("alias", text: Binding(
                            get: { items[idx] },
                            set: { v in var u = items; u[idx] = v; onChange(u) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        Button(role: .destructive) {
                            var u = items; u.remove(at: idx); onChange(u)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove")
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(AppFontScale.groupHeader)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .errorHighlight(saveErrors.hasGroup(field))
    }

    // MARK: - Separators editor (String)

    @ViewBuilder
    private func separatorsEditor(value: String, onChange: @escaping (String) -> Void) -> some View {
        GroupBox {
            TextField("e.g. /,;|", text: Binding(get: { value }, set: onChange))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sample Cell Separators").font(AppFontScale.groupHeader)
                Text("Characters that split multiple sample IDs within one cell")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Numeric key aliases editor ([String: [String]])

    @ViewBuilder
    private func numericKeyAliasesEditor(
        aliases: [String: [String]],
        saveErrors: [RulesPanelFieldError],
        onChange: @escaping ([String: [String]]) -> Void
    ) -> some View {
        let sortedKeys = aliases.keys.sorted()
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Spacer()
                    Button("Add Key") {
                        var u = aliases; u[""] = []; onChange(u)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ForEach(sortedKeys, id: \.self) { key in
                    numericKeyRow(
                        key: key,
                        aliases: aliases[key] ?? [],
                        saveErrors: saveErrors,
                        onKeyChange: { newKey in
                            var u = aliases
                            let vals = u.removeValue(forKey: key) ?? []
                            u[newKey] = vals
                            onChange(u)
                        },
                        onAliasesChange: { vals in
                            var u = aliases; u[key] = vals; onChange(u)
                        },
                        onRemove: {
                            var u = aliases; u.removeValue(forKey: key); onChange(u)
                        }
                    )
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Numeric Key Aliases").font(AppFontScale.groupHeader)
                Text("Maps spreadsheet column header variants to a canonical numeric key")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .errorHighlight(saveErrors.hasGroup("registry.numericKeyAliases"))
    }

    @ViewBuilder
    private func numericKeyRow(
        key: String,
        aliases: [String],
        saveErrors: [RulesPanelFieldError],
        onKeyChange: @escaping (String) -> Void,
        onAliasesChange: @escaping ([String]) -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                TextField("key", text: Binding(get: { key }, set: onKeyChange))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(maxWidth: 120)
                Text("→")
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove key")
            }
            HStack(spacing: AppSpacing.sm) {
                Spacer().frame(width: AppSpacing.lg)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(aliases.indices, id: \.self) { idx in
                        HStack(spacing: AppSpacing.sm) {
                            TextField("alias", text: Binding(
                                get: { aliases[idx] },
                                set: { v in var u = aliases; u[idx] = v; onAliasesChange(u) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            Button(role: .destructive) {
                                var u = aliases; u.remove(at: idx); onAliasesChange(u)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove alias")
                        }
                    }
                    Button("Add Alias") { onAliasesChange(aliases + [""]) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .errorHighlight(saveErrors.hasRow(group: "registry.numericKeyAliases", key: key))
    }

    // MARK: - Metadata lookup aliases editor ([String: [String]])

    @ViewBuilder
    private func metadataLookupAliasesEditor(
        aliases: [String: [String]],
        saveErrors: [RulesPanelFieldError],
        onChange: @escaping ([String: [String]]) -> Void
    ) -> some View {
        let sortedKeys = aliases.keys.sorted()
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(sortedKeys, id: \.self) { field in
                    metadataFieldRow(
                        field: field,
                        aliases: aliases[field] ?? [],
                        saveErrors: saveErrors,
                        onChange: { vals in
                            var u = aliases; u[field] = vals; onChange(u)
                        }
                    )
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Metadata Lookup Aliases").font(AppFontScale.groupHeader)
                Text("Column headers used to look up metadata fields (batch, sample, etc.) in registry spreadsheets")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .errorHighlight(saveErrors.hasGroup("registry.metadataLookupAliases"))
    }

    @ViewBuilder
    private func metadataFieldRow(
        field: String,
        aliases: [String],
        saveErrors: [RulesPanelFieldError],
        onChange: @escaping ([String]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(field)
                    .font(AppFontScale.groupHeader)
                    .frame(minWidth: 80, alignment: .leading)
                Spacer()
                Button("Add") { onChange(aliases + [""]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(aliases.indices, id: \.self) { idx in
                HStack(spacing: AppSpacing.sm) {
                    Spacer().frame(width: AppSpacing.lg)
                    TextField("alias", text: Binding(
                        get: { aliases[idx] },
                        set: { v in var u = aliases; u[idx] = v; onChange(u) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    Button(role: .destructive) {
                        var u = aliases; u.remove(at: idx); onChange(u)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove alias")
                }
            }
        }
        .errorHighlight(saveErrors.hasRow(group: "registry.metadataLookupAliases", key: field))
    }

    // MARK: - Patch helper

    private func patch(_ d: LibraryRegistryFileDraft, _ update: (inout LibraryRegistryFileDraft) -> Void) {
        var updated = d
        update(&updated)
        draft = updated
        store.updateLibraryRegistry(updated)
    }

    // MARK: - Sync

    private func syncFromStore() {
        if let current = store.libraryRegistryDraft { draft = current }
    }
}
