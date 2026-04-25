import SwiftUI

struct SubstrateRulesSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: SubstrateNormalizationRulesFileDraft?
    @State private var selectedTagRuleIndex: Int? = nil
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        VStack(spacing: 0) {
            saveBar()
            Divider()
            Group {
                if let d = draft {
                    scrollContent(d)
                } else {
                    ContentUnavailableView("No substrate rules loaded", systemImage: "doc.questionmark")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { syncFromStore() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: .substrate)
                syncFromStore()
            }
            Button("Override With My Edits", role: .destructive) {
                let outcome = store.overrideWithCurrentDraft(section: .substrate)
                handleOutcome(outcome)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was modified externally (checksum: \(pendingConflictChecksum.prefix(8))). Choose how to resolve.")
        }
    }

    // MARK: - Save bar

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
                .disabled(!(store.dirtySections.contains(.substrate)))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(_ d: SubstrateNormalizationRulesFileDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                tagRulesSection(d)
                if let shared = d.sharedSubstrate {
                    sharedSubstrateSection(d, shared: shared)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Substrate tag rules

    @ViewBuilder
    private func tagRuleRow(idx: Int, d: SubstrateNormalizationRulesFileDraft) -> some View {
        mapRuleRow(
            rule: d.substrateTagRules[idx],
            isSelected: selectedTagRuleIndex == idx
        ) {
            selectedTagRuleIndex = idx == selectedTagRuleIndex ? nil : idx
        }
        if selectedTagRuleIndex == idx {
            mapRuleEditor(binding(for: idx, in: \.substrateTagRules))
                .padding(.leading, AppSpacing.xl)
        }
        Divider()
    }

    @ViewBuilder
    private func tagRulesSection(_ d: SubstrateNormalizationRulesFileDraft) -> some View {
        GroupBox("Substrate Tag Rules") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.substrateTagRules.indices, id: \.self) { idx in
                    tagRuleRow(idx: idx, d: d)
                }
                HStack(spacing: AppSpacing.md) {
                    Button("Add Rule") {
                        var updated = d
                        updated.substrateTagRules.append(
                            .init(match: .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: []),
                                  value: "")
                        )
                        applyDraft(updated)
                        selectedTagRuleIndex = updated.substrateTagRules.count - 1
                    }
                    .buttonStyle(.bordered)
                    if let sel = selectedTagRuleIndex {
                        Button("Remove", role: .destructive) {
                            var updated = d
                            updated.substrateTagRules.remove(at: sel)
                            applyDraft(updated)
                            selectedTagRuleIndex = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - Shared substrate section

    @ViewBuilder
    private func sharedSubstrateSection(
        _ d: SubstrateNormalizationRulesFileDraft,
        shared: SubstrateNormalizationRulesFileDraft.SharedSubstrate
    ) -> some View {
        GroupBox("Shared Substrate Rules") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // tokenSeparators
                LabeledContent("Token Separators") {
                    TextField("e.g. _- ()", text: Binding(
                        get: { shared.tokenSeparators },
                        set: { updateShared(\.tokenSeparators, value: $0, base: d) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                }

                Divider()

                // originStandaloneTokens
                stringListEditor(
                    title: "Origin Standalone Tokens",
                    items: shared.originStandaloneTokens,
                    onChange: { updateShared(\.originStandaloneTokens, value: $0, base: d) }
                )

                Divider()

                // originContainsTokens
                stringListEditor(
                    title: "Origin Contains Tokens",
                    items: shared.originContainsTokens,
                    onChange: { updateShared(\.originContainsTokens, value: $0, base: d) }
                )

                Divider()

                // treatmentKeywords: [String: [String]]
                treatmentKeywordsEditor(d, shared: shared)

                Divider()

                // materialTokens
                stringListEditor(
                    title: "Material Tokens",
                    items: shared.materialTokens,
                    onChange: { updateShared(\.materialTokens, value: $0, base: d) }
                )

                Divider()

                // materialAliases: [String: String]
                keyValueEditor(
                    title: "Material Aliases",
                    subtitle: "alias → canonical token",
                    items: shared.materialAliases ?? [:],
                    onChange: { updateShared(\.materialAliases, value: $0, base: d) }
                )

                Divider()

                // materialDisplayNames: [String: String]
                keyValueEditor(
                    title: "Material Display Names",
                    subtitle: "token → display string",
                    items: shared.materialDisplayNames ?? [:],
                    onChange: { updateShared(\.materialDisplayNames, value: $0, base: d) }
                )

                Divider()

                // orientationTokens
                stringListEditor(
                    title: "Orientation Tokens",
                    items: shared.orientationTokens ?? [],
                    onChange: { updateShared(\.orientationTokens, value: $0, base: d) }
                )

                Divider()

                // orientationAliases
                keyValueEditor(
                    title: "Orientation Aliases",
                    subtitle: "alias → canonical token",
                    items: shared.orientationAliases ?? [:],
                    onChange: { updateShared(\.orientationAliases, value: $0, base: d) }
                )

                Divider()

                // orientationPattern
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Orientation Pattern").font(AppFontScale.groupHeader)
                    inlineRegexField(
                        text: Binding(
                            get: { shared.orientationPattern },
                            set: { updateShared(\.orientationPattern, value: $0, base: d) }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Inline helpers

    @ViewBuilder
    private func mapRuleRow(
        rule: FilenameParseRulesFileDraft.MapRule,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("→ \(rule.value)").font(.callout.weight(.semibold))
                    Text("\(rule.match.scope) · \(rule.match.type) · \(matchValueSummary(rule.match))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .cornerRadius(AppSpacing.xs)
    }

    @ViewBuilder
    private func mapRuleEditor(_ rule: Binding<FilenameParseRulesFileDraft.MapRule>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Scope", selection: rule.match.scope) {
                Text("tokens").tag("tokens")
                Text("joined").tag("joined")
            }.pickerStyle(.segmented)

            Picker("Type", selection: rule.match.type) {
                Text("equals").tag("equals")
                Text("equalsAny").tag("equalsAny")
                Text("contains").tag("contains")
                Text("containsAny").tag("containsAny")
                Text("equalsOrContainsAny").tag("equalsOrContainsAny")
                Text("regex").tag("regex")
            }.pickerStyle(.menu)

            let isMulti = ["equalsAny", "containsAny", "equalsOrContainsAny"].contains(rule.match.type.wrappedValue)
            if isMulti {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Match Values").font(.callout)
                    TextEditor(text: Binding(
                        get: { rule.match.values.wrappedValue?.joined(separator: "\n") ?? "" },
                        set: { rule.match.values.wrappedValue = $0.components(separatedBy: "\n").filter { !$0.isEmpty } }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 60)
                    .border(Color.secondary.opacity(0.3))
                }
            } else {
                LabeledContent("Match Value") {
                    TextField("value", text: Binding(
                        get: { rule.match.value.wrappedValue ?? "" },
                        set: { rule.match.value.wrappedValue = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if rule.match.type.wrappedValue == "regex" {
                if let p = rule.match.value.wrappedValue, !p.isEmpty {
                    regexError(for: p).map { err in
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            LabeledContent("Output Value") {
                TextField("value", text: rule.value)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(AppSpacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(AppSpacing.md)
    }

    @ViewBuilder
    private func inlineRegexField(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            TextField("regex pattern", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            if let err = regexError(for: text.wrappedValue) {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func stringListEditor(title: String, items: [String], onChange: @escaping ([String]) -> Void) -> some View {
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
                        set: { var updated = items; updated[idx] = $0; onChange(updated) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var updated = items; updated.remove(at: idx); onChange(updated)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
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
                    Text(title).font(AppFontScale.groupHeader)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Row") {
                    var updated = items
                    var key = "new_key"
                    var n = 2
                    while updated.keys.contains(key) { key = "new_key_\(n)"; n += 1 }
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
                        .frame(minWidth: 100, alignment: .leading)
                    Text("→").foregroundStyle(.secondary)
                    TextField("value", text: Binding(
                        get: { items[key] ?? "" },
                        set: { var updated = items; updated[key] = $0; onChange(updated) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var updated = items; updated.removeValue(forKey: key); onChange(updated)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
                }
            }
        }
    }

    @ViewBuilder
    private func treatmentKeywordsEditor(
        _ d: SubstrateNormalizationRulesFileDraft,
        shared: SubstrateNormalizationRulesFileDraft.SharedSubstrate
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Treatment Keywords").font(AppFontScale.groupHeader)
                    Text("key → aliases").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Group") {
                    var updated = shared.treatmentKeywords
                    var key = "NEW"
                    var n = 2
                    while updated.keys.contains(key) { key = "NEW_\(n)"; n += 1 }
                    updated[key] = []
                    updateShared(\.treatmentKeywords, value: updated, base: d)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(shared.treatmentKeywords.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack {
                        Text(key).font(.callout.weight(.semibold).monospaced())
                        Spacer()
                        Button(role: .destructive) {
                            var updated = shared.treatmentKeywords
                            updated.removeValue(forKey: key)
                            updateShared(\.treatmentKeywords, value: updated, base: d)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove group")
                    }
                    let aliases = shared.treatmentKeywords[key] ?? []
                    ForEach(aliases.indices, id: \.self) { idx in
                        HStack(spacing: AppSpacing.sm) {
                            TextField("alias", text: Binding(
                                get: { aliases[idx] },
                                set: {
                                    var updated = shared.treatmentKeywords
                                    var list = updated[key] ?? []
                                    list[idx] = $0
                                    updated[key] = list
                                    updateShared(\.treatmentKeywords, value: updated, base: d)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                            Button(role: .destructive) {
                                var updated = shared.treatmentKeywords
                                var list = updated[key] ?? []
                                list.remove(at: idx)
                                updated[key] = list
                                updateShared(\.treatmentKeywords, value: updated, base: d)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove alias")
                        }
                    }
                    Button("Add alias") {
                        var updated = shared.treatmentKeywords
                        var list = updated[key] ?? []
                        list.append("")
                        updated[key] = list
                        updateShared(\.treatmentKeywords, value: updated, base: d)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(AppSpacing.sm)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(AppSpacing.xs)
            }
        }
    }

    // MARK: - Draft mutations

    private func updateShared<V>(
        _ kp: WritableKeyPath<SubstrateNormalizationRulesFileDraft.SharedSubstrate, V>,
        value: V,
        base: SubstrateNormalizationRulesFileDraft
    ) {
        guard var d = draft else { return }
        var shared = d.sharedSubstrate ?? defaultShared()
        shared[keyPath: kp] = value
        d.sharedSubstrate = shared
        draft = d
        store.updateSubstrate(d)
    }

    private func binding(
        for index: Int,
        in kp: WritableKeyPath<SubstrateNormalizationRulesFileDraft, [FilenameParseRulesFileDraft.MapRule]>
    ) -> Binding<FilenameParseRulesFileDraft.MapRule> {
        Binding(
            get: { self.draft?[keyPath: kp][index] ?? .init(match: .init(scope: "tokens", type: "equals"), value: "") },
            set: { newValue in
                guard var d = self.draft else { return }
                d[keyPath: kp][index] = newValue
                self.draft = d
                self.store.updateSubstrate(d)
            }
        )
    }

    private func applyDraft(_ d: SubstrateNormalizationRulesFileDraft) {
        draft = d
        store.updateSubstrate(d)
    }

    // MARK: - Save / Discard

    private func saveEdits() {
        let outcome = store.saveCurrent()
        handleOutcome(outcome)
    }

    private func discardEdits() {
        store.discardCurrent()
        syncFromStore()
        saveErrors = []
    }

    private func syncFromStore() {
        if let current = store.substrateDraft { draft = current }
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

    // MARK: - Helpers

    private func matchValueSummary(_ spec: FilenameParseRulesFileDraft.MapRule.MatchSpec) -> String {
        if let v = spec.value { return "\"\(v)\"" }
        if let vs = spec.values { return "[\(vs.prefix(3).joined(separator: ", "))\(vs.count > 3 ? "…" : "")]" }
        return "(none)"
    }

    private func regexError(for pattern: String) -> String? {
        guard !pattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return "Invalid regex: \(error.localizedDescription)"
        }
    }

    private func defaultShared() -> SubstrateNormalizationRulesFileDraft.SharedSubstrate {
        SubstrateNormalizationRulesFileDraft.SharedSubstrate(
            tokenSeparators: "_- ()",
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
    }
}
