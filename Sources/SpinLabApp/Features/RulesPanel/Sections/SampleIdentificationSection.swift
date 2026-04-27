import SwiftUI

struct SampleIdentificationSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: SampleIdentificationFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""
    @State private var expandedSubstrateTagRuleIndex: Int? = nil
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
                sampleIdPatternsGroup(d)
                substrateTagRulesGroup(d)
                substrateRowsGroup(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    @ViewBuilder
    private func sampleIdPatternsGroup(_ d: SampleIdentificationFileDraft) -> some View {
        GroupBox("Sample ID Patterns") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("Regex Patterns")
                        .font(AppFontScale.groupHeader)
                    Spacer()
                    Button("Add") {
                        var updated = d
                        updated.sampleId.patterns.append("")
                        apply(updated)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(d.sampleId.patterns.indices, id: \.self) { idx in
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        RegexField(
                            title: "sample id regex",
                            text: Binding(
                                get: { d.sampleId.patterns[idx] },
                                set: { newValue in
                                    var updated = d
                                    updated.sampleId.patterns[idx] = newValue
                                    apply(updated)
                                }
                            )
                        )
                        Button(role: .destructive) {
                            var updated = d
                            updated.sampleId.patterns.remove(at: idx)
                            apply(updated)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove pattern")
                        .padding(.top, AppSpacing.xs)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func substrateTagRulesGroup(_ d: SampleIdentificationFileDraft) -> some View {
        GroupBox("Substrate Tag Rules") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("Map Rules")
                        .font(AppFontScale.groupHeader)
                    Spacer()
                    Button("Add Rule") {
                        var updated = d
                        updated.substrate.substrateTagRules.append(
                            MapRule(
                                match: .init(scope: "tokens", type: "equalsOrContainsAny", matchValues: []),
                                value: ""
                            )
                        )
                        apply(updated)
                        expandedSubstrateTagRuleIndex = updated.substrate.substrateTagRules.count - 1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(d.substrate.substrateTagRules.indices, id: \.self) { ruleIdx in
                    let isExpanded = expandedSubstrateTagRuleIndex == ruleIdx
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Button {
                            expandedSubstrateTagRuleIndex = isExpanded ? nil : ruleIdx
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text("→ \(d.substrate.substrateTagRules[ruleIdx].value)")
                                        .font(.callout.weight(.semibold))
                                    Text("\(d.substrate.substrateTagRules[ruleIdx].match.scope) · \(d.substrate.substrateTagRules[ruleIdx].match.type)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    var updated = d
                                    updated.substrate.substrateTagRules.remove(at: ruleIdx)
                                    apply(updated)
                                    if expandedSubstrateTagRuleIndex == ruleIdx {
                                        expandedSubstrateTagRuleIndex = nil
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
                            MatchRuleEditor(rule: substrateTagRuleBinding(ruleIdx: ruleIdx))
                                .padding(AppSpacing.md)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .cornerRadius(AppSpacing.sm)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row-oriented substrate editors

    @ViewBuilder
    private func substrateRowsGroup(_ d: SampleIdentificationFileDraft) -> some View {
        GroupBox("Substrate Configuration") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                materialsEditor(d)
                Divider()
                treatmentsEditor(d)
                Divider()
                orientationsEditor(d)
            }
        }
    }

    // MARK: - Materials editor

    @ViewBuilder
    private func materialsEditor(_ d: SampleIdentificationFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Materials").font(AppFontScale.groupHeader)
                Spacer()
                Button("Add") {
                    var u = d
                    u.substrate.materials.append(.init(id: "NEW", tokens: [], aliases: [], displayName: ""))
                    apply(u)
                    expandedMaterialIndex = u.substrate.materials.count - 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(d.substrate.materials.indices, id: \.self) { idx in
                let mat = d.substrate.materials[idx]
                let isExpanded = expandedMaterialIndex == idx
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button { expandedMaterialIndex = isExpanded ? nil : idx } label: {
                        HStack(spacing: AppSpacing.md) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(mat.id).font(.callout.weight(.semibold).monospaced())
                                Text(mat.displayName.isEmpty ? "—" : mat.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                var u = d; u.substrate.materials.remove(at: idx); apply(u)
                                if expandedMaterialIndex == idx { expandedMaterialIndex = nil }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        materialRowDetail(idx: idx, d: d)
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func materialRowDetail(idx: Int, d: SampleIdentificationFileDraft) -> some View {
        let mat = d.substrate.materials[idx]
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("ID") {
                TextField("material id", text: Binding(
                    get: { mat.id },
                    set: { v in var u = d; u.substrate.materials[idx].id = v; apply(u) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            LabeledContent("Display Name") {
                TextField("display name", text: Binding(
                    get: { mat.displayName },
                    set: { v in var u = d; u.substrate.materials[idx].displayName = v; apply(u) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            stringListField(
                title: "Tokens",
                items: mat.tokens,
                onChange: { v in var u = d; u.substrate.materials[idx].tokens = v; apply(u) }
            )
            stringListField(
                title: "Aliases",
                items: mat.aliases,
                onChange: { v in var u = d; u.substrate.materials[idx].aliases = v; apply(u) }
            )
        }
    }

    // MARK: - Treatments editor

    @ViewBuilder
    private func treatmentsEditor(_ d: SampleIdentificationFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Treatments").font(AppFontScale.groupHeader)
                Spacer()
                Button("Add") {
                    var u = d
                    u.substrate.treatments.append(.init(id: "new", displayName: "", keywords: [], standaloneTokens: [], containsTokens: []))
                    apply(u)
                    expandedTreatmentIndex = u.substrate.treatments.count - 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(d.substrate.treatments.indices, id: \.self) { idx in
                let t = d.substrate.treatments[idx]
                let isExpanded = expandedTreatmentIndex == idx
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button { expandedTreatmentIndex = isExpanded ? nil : idx } label: {
                        HStack(spacing: AppSpacing.md) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(t.id).font(.callout.weight(.semibold).monospaced())
                                Text(t.displayName.isEmpty ? "—" : t.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                var u = d; u.substrate.treatments.remove(at: idx); apply(u)
                                if expandedTreatmentIndex == idx { expandedTreatmentIndex = nil }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        treatmentRowDetail(idx: idx, d: d)
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func treatmentRowDetail(idx: Int, d: SampleIdentificationFileDraft) -> some View {
        let t = d.substrate.treatments[idx]
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("ID") {
                TextField("treatment id", text: Binding(
                    get: { t.id },
                    set: { v in var u = d; u.substrate.treatments[idx].id = v; apply(u) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            LabeledContent("Display Name") {
                TextField("display name", text: Binding(
                    get: { t.displayName },
                    set: { v in var u = d; u.substrate.treatments[idx].displayName = v; apply(u) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            stringListField(
                title: "Keywords",
                items: t.keywords,
                onChange: { v in var u = d; u.substrate.treatments[idx].keywords = v; apply(u) }
            )
            stringListField(
                title: "Standalone Tokens",
                items: t.standaloneTokens,
                onChange: { v in var u = d; u.substrate.treatments[idx].standaloneTokens = v; apply(u) }
            )
            stringListField(
                title: "Contains Tokens",
                items: t.containsTokens,
                onChange: { v in var u = d; u.substrate.treatments[idx].containsTokens = v; apply(u) }
            )
        }
    }

    // MARK: - Orientations editor

    @ViewBuilder
    private func orientationsEditor(_ d: SampleIdentificationFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Orientations").font(AppFontScale.groupHeader)
            LabeledContent("Pattern") {
                RegexField(title: "orientation regex", text: Binding(
                    get: { d.substrate.orientations.pattern },
                    set: { v in var u = d; u.substrate.orientations.pattern = v; apply(u) }
                ))
            }
            HStack {
                Text("Rows").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    var u = d
                    u.substrate.orientations.rows.append(.init(id: "000", tokens: [], aliases: []))
                    apply(u)
                    expandedOrientationIndex = u.substrate.orientations.rows.count - 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(d.substrate.orientations.rows.indices, id: \.self) { idx in
                let row = d.substrate.orientations.rows[idx]
                let isExpanded = expandedOrientationIndex == idx
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button { expandedOrientationIndex = isExpanded ? nil : idx } label: {
                        HStack(spacing: AppSpacing.md) {
                            Text(row.id).font(.callout.weight(.semibold).monospaced())
                            Spacer()
                            Button(role: .destructive) {
                                var u = d; u.substrate.orientations.rows.remove(at: idx); apply(u)
                                if expandedOrientationIndex == idx { expandedOrientationIndex = nil }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        orientationRowDetail(idx: idx, d: d)
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func orientationRowDetail(idx: Int, d: SampleIdentificationFileDraft) -> some View {
        let row = d.substrate.orientations.rows[idx]
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("ID") {
                TextField("orientation id", text: Binding(
                    get: { row.id },
                    set: { v in var u = d; u.substrate.orientations.rows[idx].id = v; apply(u) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            stringListField(
                title: "Tokens",
                items: row.tokens,
                onChange: { v in var u = d; u.substrate.orientations.rows[idx].tokens = v; apply(u) }
            )
            stringListField(
                title: "Aliases",
                items: row.aliases,
                onChange: { v in var u = d; u.substrate.orientations.rows[idx].aliases = v; apply(u) }
            )
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
                Button("Add") {
                    onChange(items + [""])
                }
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

    private func substrateTagRuleBinding(ruleIdx: Int) -> Binding<MapRule> {
        Binding(
            get: {
                guard let d = draft,
                      d.substrate.substrateTagRules.indices.contains(ruleIdx) else {
                    return MapRule(match: .init(scope: "tokens", type: "equals", matchValues: []), value: "")
                }
                return d.substrate.substrateTagRules[ruleIdx]
            },
            set: { newValue in
                guard var d = draft,
                      d.substrate.substrateTagRules.indices.contains(ruleIdx) else { return }
                d.substrate.substrateTagRules[ruleIdx] = newValue
                apply(d)
            }
        )
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
