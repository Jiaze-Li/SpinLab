import SwiftUI

struct SampleIdentificationSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: SampleIdentificationFileDraft?
    @State private var expandedMaterialIndex: Int? = nil
    @State private var expandedTreatmentIndex: Int? = nil
    @State private var expandedOrientationIndex: Int? = nil

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        RulesSectionShell(
            section: .sampleIdentification,
            isDraftAvailable: draft != nil,
            versionLabel: draft.map { "Schema version \($0.version)" },
            onSync: syncFromStore
        ) { saveErrors in
            if let d = draft {
                scrollContent(d, saveErrors: saveErrors)
            }
        }
    }

    @ViewBuilder
    private func scrollContent(
        _ d: SampleIdentificationFileDraft,
        saveErrors: Binding<[RulesPanelFieldError]>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                batchPrefixesGroup(d)
                substrateConfigGroup(d, saveErrors: saveErrors.wrappedValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Batch Prefixes

    @ViewBuilder
    private func batchPrefixesGroup(_ d: SampleIdentificationFileDraft) -> some View {
        GroupBox("Batch ID Prefixes") {
            stringListField(
                title: "Prefixes",
                items: d.sampleId.batchPrefixes,
                onChange: { v in var u = d; u.sampleId.batchPrefixes = v; apply(u) }
            )
        }
    }

    // MARK: - Substrate Configuration

    @ViewBuilder
    private func substrateConfigGroup(
        _ d: SampleIdentificationFileDraft,
        saveErrors: [RulesPanelFieldError]
    ) -> some View {
        GroupBox("Substrate Configuration") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                substrateEntriesEditor(
                    title: "Materials",
                    groupKey: "substrate.materials",
                    entries: d.substrate.materials,
                    saveErrors: saveErrors,
                    expandedIndex: $expandedMaterialIndex,
                    onAdd: {
                        var u = d
                        u.substrate.materials.append(.init(displayName: "", matches: []))
                        apply(u)
                        expandedMaterialIndex = u.substrate.materials.count - 1
                    },
                    onRemove: { idx in
                        var u = d; u.substrate.materials.remove(at: idx); apply(u)
                        if expandedMaterialIndex == idx { expandedMaterialIndex = nil }
                    }
                ) { idx in
                    entryDetail(idx: idx, entries: d.substrate.materials) { v in
                        var u = d; u.substrate.materials = v; apply(u)
                    }
                }
                Divider()
                substrateEntriesEditor(
                    title: "Treatments",
                    groupKey: "substrate.treatments",
                    entries: d.substrate.treatments,
                    saveErrors: saveErrors,
                    expandedIndex: $expandedTreatmentIndex,
                    onAdd: {
                        var u = d
                        u.substrate.treatments.append(.init(displayName: "", matches: []))
                        apply(u)
                        expandedTreatmentIndex = u.substrate.treatments.count - 1
                    },
                    onRemove: { idx in
                        var u = d; u.substrate.treatments.remove(at: idx); apply(u)
                        if expandedTreatmentIndex == idx { expandedTreatmentIndex = nil }
                    }
                ) { idx in
                    entryDetail(idx: idx, entries: d.substrate.treatments) { v in
                        var u = d; u.substrate.treatments = v; apply(u)
                    }
                }
                Divider()
                substrateEntriesEditor(
                    title: "Orientations",
                    groupKey: "substrate.orientations",
                    entries: d.substrate.orientations,
                    saveErrors: saveErrors,
                    expandedIndex: $expandedOrientationIndex,
                    onAdd: {
                        var u = d
                        u.substrate.orientations.append(.init(displayName: "", matches: []))
                        apply(u)
                        expandedOrientationIndex = u.substrate.orientations.count - 1
                    },
                    onRemove: { idx in
                        var u = d; u.substrate.orientations.remove(at: idx); apply(u)
                        if expandedOrientationIndex == idx { expandedOrientationIndex = nil }
                    }
                ) { idx in
                    entryDetail(idx: idx, entries: d.substrate.orientations) { v in
                        var u = d; u.substrate.orientations = v; apply(u)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func substrateEntriesEditor<Detail: View>(
        title: String,
        groupKey: String,
        entries: [SampleIdentificationFileDraft.SubstrateEntry],
        saveErrors: [RulesPanelFieldError],
        expandedIndex: Binding<Int?>,
        onAdd: @escaping () -> Void,
        onRemove: @escaping (Int) -> Void,
        @ViewBuilder detail: @escaping (Int) -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(title).font(AppFontScale.groupHeader)
                if saveErrors.hasGroup(groupKey) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Spacer()
                Button("Add") { onAdd() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(entries.indices, id: \.self) { idx in
                let entry = entries[idx]
                let isExpanded = expandedIndex.wrappedValue == idx
                let rowHasError = saveErrors.hasRow(group: groupKey, key: entry.displayName)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button { expandedIndex.wrappedValue = isExpanded ? nil : idx } label: {
                        HStack(spacing: AppSpacing.md) {
                            Text(entry.displayName.isEmpty ? "—" : entry.displayName)
                                .font(.callout.weight(.semibold).monospaced())
                                .foregroundStyle(rowHasError ? Color.red : .primary)
                            Text("\(entry.matches.count) match\(entry.matches.count == 1 ? "" : "es")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) { onRemove(idx) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .errorHighlight(rowHasError, cornerRadius: 6)

                    if isExpanded {
                        detail(idx)
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryDetail(
        idx: Int,
        entries: [SampleIdentificationFileDraft.SubstrateEntry],
        onChange: @escaping ([SampleIdentificationFileDraft.SubstrateEntry]) -> Void
    ) -> some View {
        let entry = entries[idx]
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("Display Name") {
                TextField("display name", text: Binding(
                    get: { entry.displayName },
                    set: { v in var updated = entries; updated[idx].displayName = v; onChange(updated) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            matchesEditor(entryIdx: idx, entries: entries, onChange: onChange)
        }
    }

    @ViewBuilder
    private func matchesEditor(
        entryIdx: Int,
        entries: [SampleIdentificationFileDraft.SubstrateEntry],
        onChange: @escaping ([SampleIdentificationFileDraft.SubstrateEntry]) -> Void
    ) -> some View {
        let matches = entries[entryIdx].matches
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Matches").font(.subheadline)
                Spacer()
                Button("Add") {
                    var updated = entries
                    updated[entryIdx].matches.append(.init(type: "equals", value: ""))
                    onChange(updated)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(matches.indices, id: \.self) { mIdx in
                HStack(spacing: AppSpacing.sm) {
                    Picker("", selection: Binding(
                        get: { matches[mIdx].type },
                        set: { v in var updated = entries; updated[entryIdx].matches[mIdx].type = v; onChange(updated) }
                    )) {
                        Text("equals").tag("equals")
                        Text("contains").tag("contains")
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("value", text: Binding(
                        get: { matches[mIdx].value },
                        set: { v in var updated = entries; updated[entryIdx].matches[mIdx].value = v; onChange(updated) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    Button(role: .destructive) {
                        var updated = entries
                        updated[entryIdx].matches.remove(at: mIdx)
                        onChange(updated)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func stringListField(
        title: String,
        items: [String],
        onChange: @escaping ([String]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(title).font(AppFontScale.groupHeader)
                Spacer()
                Button("Add") { onChange(items + [""]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: AppSpacing.sm) {
                    TextField("value", text: Binding(
                        get: { items[idx] },
                        set: { v in var updated = items; updated[idx] = v; onChange(updated) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    Button(role: .destructive) {
                        var updated = items; updated.remove(at: idx); onChange(updated)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
                }
            }
        }
    }

    private func apply(_ updated: SampleIdentificationFileDraft) {
        draft = updated
        store.updateSampleIdentification(updated)
    }

    private func syncFromStore() {
        if let current = store.sampleIdentificationDraft {
            draft = current
        }
    }
}
