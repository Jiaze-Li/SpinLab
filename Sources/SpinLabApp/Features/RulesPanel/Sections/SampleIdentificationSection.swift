import SwiftUI

struct SampleIdentificationSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: SampleIdentificationFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""
    @State private var expandedSubstrateTagRuleIndex: Int? = nil

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
                sharedSubstrateGroup(d)
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
                                match: .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: []),
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
                            if isExpanded {
                                expandedSubstrateTagRuleIndex = nil
                            } else {
                                expandedSubstrateTagRuleIndex = ruleIdx
                            }
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

    @ViewBuilder
    private func sharedSubstrateGroup(_ d: SampleIdentificationFileDraft) -> some View {
        GroupBox("Shared Substrate") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let shared = d.substrate.shared {
                    sharedSubstrateEditor(shared: shared, d: d)
                } else {
                    Text("No shared substrate config")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Add Shared Config") {
                        var updated = d
                        updated.substrate.shared = .init(
                            tokenSeparators: "_",
                            originStandaloneTokens: [],
                            originContainsTokens: [],
                            treatmentKeywords: [:],
                            materialTokens: [],
                            materialAliases: nil,
                            materialDisplayNames: nil,
                            orientationTokens: nil,
                            orientationAliases: nil,
                            orientationPattern: ""
                        )
                        apply(updated)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func sharedSubstrateEditor(
        shared: SampleIdentificationFileDraft.SubstrateConfig.SharedSubstrate,
        d: SampleIdentificationFileDraft
    ) -> some View {
        LabeledContent("Token Separators") {
            TextField(
                "e.g. _-",
                text: Binding(
                    get: { shared.tokenSeparators },
                    set: { newValue in
                        var updated = d
                        updated.substrate.shared?.tokenSeparators = newValue
                        apply(updated)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
            .font(.body.monospaced())
        }

        stringListEditor(
            title: "Material Tokens",
            subtitle: "Canonical substrate token set",
            items: shared.materialTokens,
            onChange: { values in
                var updated = d
                updated.substrate.shared?.materialTokens = values
                apply(updated)
            }
        )

        keyValueEditor(
            title: "Material Aliases",
            subtitle: "alias → canonical token",
            items: shared.materialAliases ?? [:],
            onChange: { values in
                var updated = d
                updated.substrate.shared?.materialAliases = values.isEmpty ? nil : values
                apply(updated)
            }
        )

        keyValueEditor(
            title: "Material Display Names",
            subtitle: "token → display name",
            items: shared.materialDisplayNames ?? [:],
            onChange: { values in
                var updated = d
                updated.substrate.shared?.materialDisplayNames = values.isEmpty ? nil : values
                apply(updated)
            }
        )

        orientationTokensEditor(shared: shared, d: d)

        keyValueEditor(
            title: "Orientation Aliases",
            subtitle: "alias → canonical orientation token",
            items: shared.orientationAliases ?? [:],
            onChange: { values in
                var updated = d
                updated.substrate.shared?.orientationAliases = values.isEmpty ? nil : values
                apply(updated)
            }
        )

        LabeledContent("Orientation Pattern") {
            RegexField(
                title: "orientation regex",
                text: Binding(
                    get: { shared.orientationPattern },
                    set: { newValue in
                        var updated = d
                        updated.substrate.shared?.orientationPattern = newValue
                        apply(updated)
                    }
                )
            )
        }
    }

    @ViewBuilder
    private func orientationTokensEditor(
        shared: SampleIdentificationFileDraft.SubstrateConfig.SharedSubstrate,
        d: SampleIdentificationFileDraft
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Orientation Tokens")
                    .font(AppFontScale.groupHeader)
                Spacer()
                Button("Add") {
                    var updated = d
                    let values = updated.substrate.shared?.orientationTokens ?? []
                    updated.substrate.shared?.orientationTokens = values + [""]
                    apply(updated)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let values = shared.orientationTokens ?? []
            if values.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values.indices, id: \.self) { idx in
                    HStack(spacing: AppSpacing.sm) {
                        TextField(
                            "token",
                            text: Binding(
                                get: { shared.orientationTokens?[idx] ?? "" },
                                set: { newValue in
                                    var updated = d
                                    var current = updated.substrate.shared?.orientationTokens ?? []
                                    guard current.indices.contains(idx) else { return }
                                    current[idx] = newValue
                                    updated.substrate.shared?.orientationTokens = current
                                    apply(updated)
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())

                        Button(role: .destructive) {
                            var updated = d
                            var current = updated.substrate.shared?.orientationTokens ?? []
                            guard current.indices.contains(idx) else { return }
                            current.remove(at: idx)
                            updated.substrate.shared?.orientationTokens = current.isEmpty ? nil : current
                            apply(updated)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove token")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stringListEditor(
        title: String,
        subtitle: String,
        items: [String],
        onChange: @escaping ([String]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(AppFontScale.groupHeader)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add") {
                    var updated = items
                    updated.append("")
                    onChange(updated)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: AppSpacing.sm) {
                    TextField(
                        "value",
                        text: Binding(
                            get: { items[idx] },
                            set: { newValue in
                                var updated = items
                                updated[idx] = newValue
                                onChange(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                    Button(role: .destructive) {
                        var updated = items
                        updated.remove(at: idx)
                        onChange(updated)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove row")
                }
            }
        }
    }

    @ViewBuilder
    private func keyValueEditor(
        title: String,
        subtitle: String,
        items: [String: String],
        onChange: @escaping ([String: String]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(AppFontScale.groupHeader)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Row") {
                    var updated = items
                    var key = "new_key"
                    var n = 2
                    while updated.keys.contains(key) {
                        key = "new_key_\(n)"
                        n += 1
                    }
                    updated[key] = ""
                    onChange(updated)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(items.keys.sorted(), id: \.self) { key in
                HStack(spacing: AppSpacing.sm) {
                    Text(key)
                        .font(.body.monospaced())
                        .frame(minWidth: 120, alignment: .leading)
                    Text("→")
                        .foregroundStyle(.secondary)
                    TextField(
                        "value",
                        text: Binding(
                            get: { items[key] ?? "" },
                            set: { newValue in
                                var updated = items
                                updated[key] = newValue
                                onChange(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        var updated = items
                        updated.removeValue(forKey: key)
                        onChange(updated)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove row")
                }
            }
        }
    }

    private func substrateTagRuleBinding(ruleIdx: Int) -> Binding<MapRule> {
        Binding(
            get: {
                guard let d = draft,
                      d.substrate.substrateTagRules.indices.contains(ruleIdx) else {
                    return MapRule(match: .init(scope: "tokens", type: "equals", value: nil, values: nil), value: "")
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
        case .saved:
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
