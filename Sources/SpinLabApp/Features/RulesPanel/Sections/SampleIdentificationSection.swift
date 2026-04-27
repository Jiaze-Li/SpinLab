import SwiftUI

struct SampleIdentificationSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: SampleIdentificationFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""
    @State private var expandedMaterialIndex: Int? = nil
    @State private var expandedTreatmentIndex: Int? = nil
    @State private var expandedOrientationIndex: Int? = nil

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        VStack(spacing: 0) {
            saveBar()
            Divider()
            Group {
                if let d = draft {
                    scrollContent(d)
                } else {
                    ContentUnavailableView(
                        "No sample identification rules loaded",
                        systemImage: "doc.questionmark"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { syncFromStore() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: .sampleIdentification)
                syncFromStore()
            }
            Button("Override With My Edits", role: .destructive) {
                handleOutcome(store.overrideWithCurrentDraft(section: .sampleIdentification))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was modified externally (checksum: \(pendingConflictChecksum.prefix(8))). Choose how to resolve.")
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
                .disabled(!store.dirtySections.contains(.sampleIdentification))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    @ViewBuilder
    private func scrollContent(_ d: SampleIdentificationFileDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                batchPrefixesGroup(d)
                substrateConfigGroup(d)
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
    private func substrateConfigGroup(_ d: SampleIdentificationFileDraft) -> some View {
        GroupBox("Substrate Configuration") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                substrateEntriesEditor(
                    title: "Materials",
                    entries: d.substrate.materials,
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
                    entries: d.substrate.treatments,
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
                    entries: d.substrate.orientations,
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
        entries: [SampleIdentificationFileDraft.SubstrateEntry],
        expandedIndex: Binding<Int?>,
        onAdd: @escaping () -> Void,
        onRemove: @escaping (Int) -> Void,
        @ViewBuilder detail: @escaping (Int) -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(title).font(AppFontScale.groupHeader)
                Spacer()
                Button("Add") { onAdd() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(entries.indices, id: \.self) { idx in
                let entry = entries[idx]
                let isExpanded = expandedIndex.wrappedValue == idx
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button { expandedIndex.wrappedValue = isExpanded ? nil : idx } label: {
                        HStack(spacing: AppSpacing.md) {
                            Text(entry.displayName.isEmpty ? "—" : entry.displayName)
                                .font(.callout.weight(.semibold).monospaced())
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

    private func saveEdits() {
        store.selectSection(.sampleIdentification)
        handleOutcome(store.saveCurrent())
    }

    private func discardEdits() {
        store.discardCurrent()
        syncFromStore()
        saveErrors = []
    }

    private func syncFromStore() {
        if let current = store.sampleIdentificationDraft {
            draft = current
        }
    }

    private func handleOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved, .savedWithMirrorWarning:
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
