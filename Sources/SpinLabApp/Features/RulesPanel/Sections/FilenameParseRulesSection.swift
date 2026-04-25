import SwiftUI

struct FilenameParseRulesSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: FilenameParseRulesFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""
    @State private var expandedRotationRuleIndex: Int? = nil
    @State private var expandedMeasurementRuleIndex: Int? = nil
    @State private var expandedTokenMapKey: String? = nil
    @State private var expandedTokenMapRuleIndices: [String: Int] = [:]
    @State private var selectedConditionDefID: String? = nil

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        VStack(spacing: 0) {
            saveBar()
            Divider()
            Group {
                if let d = draft {
                    scrollContent(d)
                } else {
                    ContentUnavailableView("No filename parse rules loaded", systemImage: "doc.questionmark")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { syncFromStore() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: .filenameParse)
                syncFromStore()
            }
            Button("Override With My Edits", role: .destructive) {
                let outcome = store.overrideWithCurrentDraft(section: .filenameParse)
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
                .disabled(!store.dirtySections.contains(.filenameParse))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(_ d: FilenameParseRulesFileDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                tokenizationSection(d)
                sourcesSection(d)
                batchSection(d)
                channelSection(d)
                rotationHintRulesSection(d)
                measurementNameRulesSection(d)
                conditionsSection(d)
                conditionDefinitionsSection(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Tokenization

    @ViewBuilder
    private func tokenizationSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Tokenization") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                LabeledContent("Separators") {
                    TextField("e.g. _- ()", text: Binding(
                        get: { d.tokenization.separators },
                        set: { v in var u = d; u.tokenization.separators = v; applyDraft(u) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .font(.body.monospaced())
                }
                LabeledContent("Case Fold") {
                    Picker("", selection: Binding(
                        get: { d.tokenization.caseFold },
                        set: { v in var u = d; u.tokenization.caseFold = v; applyDraft(u) }
                    )) {
                        Text("preserve").tag("preserve")
                        Text("lower").tag("lower")
                        Text("upper").tag("upper")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Sources

    @ViewBuilder
    private func sourcesSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Sources") {
            orderedStringListEditor(
                items: d.sources,
                onChange: { v in var u = d; u.sources = v; applyDraft(u) }
            )
        }
    }

    // MARK: - Batch

    @ViewBuilder
    private func batchSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Batch") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Toggle("Prefer Sample ID", isOn: Binding(
                    get: { d.batch.preferSampleId },
                    set: { v in var u = d; u.batch.preferSampleId = v; applyDraft(u) }
                ))
                Divider()
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text("Fallback Patterns").font(AppFontScale.groupHeader)
                        Spacer()
                        Button("Add") {
                            var u = d; u.batch.fallbackPatterns.append(""); applyDraft(u)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ForEach(d.batch.fallbackPatterns.indices, id: \.self) { idx in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                TextField("regex pattern", text: Binding(
                                    get: { d.batch.fallbackPatterns[idx] },
                                    set: { v in var u = d; u.batch.fallbackPatterns[idx] = v; applyDraft(u) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                if let err = regexError(for: d.batch.fallbackPatterns[idx]) {
                                    Text(err).font(.caption).foregroundStyle(.red)
                                }
                            }
                            Button(role: .destructive) {
                                var u = d; u.batch.fallbackPatterns.remove(at: idx); applyDraft(u)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove pattern")
                            .padding(.top, AppSpacing.xs)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Channel

    @ViewBuilder
    private func channelSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Channel") {
            keyValueEditor(
                title: "Aliases",
                subtitle: "alias → canonical channel name",
                items: d.channel.aliases,
                onChange: { v in var u = d; u.channel.aliases = v; applyDraft(u) }
            )
        }
    }

    // MARK: - Rotation Hint Rules

    @ViewBuilder
    private func rotationHintRulesSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Rotation Hint Rules") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.rotationHintRules.indices, id: \.self) { idx in
                    mapRuleRow(rule: d.rotationHintRules[idx], isSelected: expandedRotationRuleIndex == idx) {
                        expandedRotationRuleIndex = idx == expandedRotationRuleIndex ? nil : idx
                    }
                    if expandedRotationRuleIndex == idx {
                        MatchRuleEditor(rule: mapRuleBinding(at: idx, keyPath: \.rotationHintRules))
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                    Divider()
                }
                HStack(spacing: AppSpacing.md) {
                    Button("Add Rule") {
                        var u = d
                        u.rotationHintRules.append(
                            .init(match: .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: []),
                                  value: "")
                        )
                        applyDraft(u)
                        expandedRotationRuleIndex = u.rotationHintRules.count - 1
                    }
                    .buttonStyle(.bordered)
                    if let sel = expandedRotationRuleIndex, d.rotationHintRules.indices.contains(sel) {
                        Button("Remove", role: .destructive) {
                            var u = d; u.rotationHintRules.remove(at: sel); applyDraft(u)
                            expandedRotationRuleIndex = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - Measurement Name Rules

    @ViewBuilder
    private func measurementNameRulesSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Measurement Name Rules") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.measurementNameRules.indices, id: \.self) { idx in
                    mapRuleRow(rule: d.measurementNameRules[idx], isSelected: expandedMeasurementRuleIndex == idx) {
                        expandedMeasurementRuleIndex = idx == expandedMeasurementRuleIndex ? nil : idx
                    }
                    if expandedMeasurementRuleIndex == idx {
                        MatchRuleEditor(rule: mapRuleBinding(at: idx, keyPath: \.measurementNameRules))
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                    Divider()
                }
                HStack(spacing: AppSpacing.md) {
                    Button("Add Rule") {
                        var u = d
                        u.measurementNameRules.append(
                            .init(match: .init(scope: "tokens", type: "equalsOrContainsAny", value: nil, values: []),
                                  value: "")
                        )
                        applyDraft(u)
                        expandedMeasurementRuleIndex = u.measurementNameRules.count - 1
                    }
                    .buttonStyle(.bordered)
                    if let sel = expandedMeasurementRuleIndex, d.measurementNameRules.indices.contains(sel) {
                        Button("Remove", role: .destructive) {
                            var u = d; u.measurementNameRules.remove(at: sel); applyDraft(u)
                            expandedMeasurementRuleIndex = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private func conditionsSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Conditions") {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                extraConditionsEditor(d)
                Divider()
                tokenMapRulesEditor(d)
                Divider()
                keyValueEditor(
                    title: "Display Labels",
                    subtitle: "condition ID → display label",
                    items: d.conditions.displayLabels,
                    onChange: { v in var u = d; u.conditions.displayLabels = v; applyDraft(u) }
                )
            }
        }
    }

    @ViewBuilder
    private func extraConditionsEditor(_ d: FilenameParseRulesFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Extra Conditions").font(AppFontScale.groupHeader)
                    Text("condition ID → regex pattern").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add") {
                    var u = d
                    var key = "new_condition"
                    var n = 2
                    while u.conditions.extraConditions.keys.contains(key) { key = "new_condition_\(n)"; n += 1 }
                    u.conditions.extraConditions[key] = ""
                    applyDraft(u)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(d.conditions.extraConditions.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text(key)
                        .font(.body.monospaced())
                        .frame(minWidth: 120, alignment: .leading)
                        .padding(.top, AppSpacing.xs)
                    Text("→").foregroundStyle(.secondary).padding(.top, AppSpacing.xs)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        TextField("regex pattern", text: Binding(
                            get: { d.conditions.extraConditions[key] ?? "" },
                            set: { v in var u = d; u.conditions.extraConditions[key] = v; applyDraft(u) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        if let err = regexError(for: d.conditions.extraConditions[key] ?? "") {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Button(role: .destructive) {
                        var u = d; u.conditions.extraConditions.removeValue(forKey: key); applyDraft(u)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
    }

    @ViewBuilder
    private func tokenMapRulesEditor(_ d: FilenameParseRulesFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Token Map Rules").font(AppFontScale.groupHeader)
                    Text("condition ID → match rules").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Group") {
                    var u = d
                    var key = "new_group"
                    var n = 2
                    while u.conditions.tokenMapRules.keys.contains(key) { key = "new_group_\(n)"; n += 1 }
                    u.conditions.tokenMapRules[key] = []
                    applyDraft(u)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(d.conditions.tokenMapRules.keys.sorted(), id: \.self) { key in
                let rules = d.conditions.tokenMapRules[key] ?? []
                let isGroupExpanded = expandedTokenMapKey == key
                let expandedRuleIdx: Int? = expandedTokenMapRuleIndices[key]

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button(action: {
                        expandedTokenMapKey = isGroupExpanded ? nil : key
                        if isGroupExpanded { expandedTokenMapRuleIndices.removeValue(forKey: key) }
                    }) {
                        HStack {
                            Image(systemName: isGroupExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption).foregroundStyle(.secondary).frame(width: 12)
                            Text(key).font(.callout.weight(.semibold).monospaced())
                            Text("(\(rules.count) rule\(rules.count == 1 ? "" : "s"))")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                var u = d; u.conditions.tokenMapRules.removeValue(forKey: key); applyDraft(u)
                                if expandedTokenMapKey == key { expandedTokenMapKey = nil }
                                expandedTokenMapRuleIndices.removeValue(forKey: key)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove group")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isGroupExpanded {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            ForEach(rules.indices, id: \.self) { idx in
                                mapRuleRow(rule: rules[idx], isSelected: expandedRuleIdx == idx) {
                                    var updated = expandedTokenMapRuleIndices
                                    if expandedRuleIdx == idx { updated.removeValue(forKey: key) }
                                    else { updated[key] = idx }
                                    expandedTokenMapRuleIndices = updated
                                }
                                if expandedRuleIdx == idx {
                                    MatchRuleEditor(rule: tokenMapRuleBinding(key: key, index: idx))
                                        .padding(AppSpacing.md)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(AppSpacing.md)
                                }
                            }
                            HStack(spacing: AppSpacing.md) {
                                Button("Add Rule") {
                                    var u = d
                                    var groupRules = u.conditions.tokenMapRules[key] ?? []
                                    groupRules.append(
                                        .init(match: .init(scope: "tokens", type: "equalsOrContainsAny",
                                                           value: nil, values: []), value: "")
                                    )
                                    u.conditions.tokenMapRules[key] = groupRules
                                    applyDraft(u)
                                    expandedTokenMapRuleIndices[key] = groupRules.count - 1
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                if let sel = expandedRuleIdx, rules.indices.contains(sel) {
                                    Button("Remove Rule", role: .destructive) {
                                        var u = d
                                        var groupRules = u.conditions.tokenMapRules[key] ?? []
                                        groupRules.remove(at: sel)
                                        u.conditions.tokenMapRules[key] = groupRules
                                        applyDraft(u)
                                        expandedTokenMapRuleIndices.removeValue(forKey: key)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.leading, AppSpacing.xl)
                    }
                }
                .padding(AppSpacing.sm)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(AppSpacing.xs)
            }
        }
    }

    // MARK: - Condition Definitions

    @ViewBuilder
    private func conditionDefinitionsSection(_ d: FilenameParseRulesFileDraft) -> some View {
        GroupBox("Condition Definitions") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(d.conditionDefinitions.indices, id: \.self) { idx in
                    let def = d.conditionDefinitions[idx]
                    conditionDefRow(def: def, isSelected: selectedConditionDefID == def.id) {
                        selectedConditionDefID = def.id == selectedConditionDefID ? nil : def.id
                    }
                    if selectedConditionDefID == def.id {
                        conditionDefDetail(idx: idx, d: d)
                            .padding(AppSpacing.md)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(AppSpacing.md)
                    }
                    Divider()
                }
                HStack(spacing: AppSpacing.md) {
                    Button("Add Definition") {
                        var u = d
                        let newID = "new_condition"
                        u.conditionDefinitions.append(FilenameParseRulesFileDraft.ConditionDefinition(
                            id: newID,
                            label: nil,
                            kind: "unit_suffix",
                            binding: autoBinding(kind: "unit_suffix", id: newID)
                        ))
                        applyDraft(u)
                        selectedConditionDefID = newID
                    }
                    .buttonStyle(.bordered)
                    if let selID = selectedConditionDefID,
                       let selIdx = d.conditionDefinitions.firstIndex(where: { $0.id == selID }) {
                        Button("Remove", role: .destructive) {
                            var u = d; u.conditionDefinitions.remove(at: selIdx); applyDraft(u)
                            selectedConditionDefID = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conditionDefRow(
        def: FilenameParseRulesFileDraft.ConditionDefinition,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(def.id).font(.callout.weight(.semibold).monospaced())
                    HStack(spacing: AppSpacing.xs) {
                        Text(def.kind).font(.caption).foregroundStyle(.secondary)
                        if let label = def.label {
                            Text("· \(label)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .cornerRadius(AppSpacing.xs)
    }

    @ViewBuilder
    private func conditionDefDetail(idx: Int, d: FilenameParseRulesFileDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LabeledContent("ID") {
                TextField("condition ID", text: Binding(
                    get: { d.conditionDefinitions[idx].id },
                    set: { newID in
                        var u = d
                        u.conditionDefinitions[idx].id = newID
                        u.conditionDefinitions[idx].binding = autoBinding(
                            kind: u.conditionDefinitions[idx].kind, id: newID
                        )
                        applyDraft(u)
                        selectedConditionDefID = newID
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            LabeledContent("Label") {
                TextField("display label (optional)", text: Binding(
                    get: { d.conditionDefinitions[idx].label ?? "" },
                    set: { v in
                        var u = d
                        u.conditionDefinitions[idx].label = v.isEmpty ? nil : v
                        applyDraft(u)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Kind") {
                Picker("", selection: Binding(
                    get: { d.conditionDefinitions[idx].kind },
                    set: { newKind in
                        var u = d
                        u.conditionDefinitions[idx].kind = newKind
                        u.conditionDefinitions[idx].binding = autoBinding(
                            kind: newKind, id: u.conditionDefinitions[idx].id
                        )
                        applyDraft(u)
                    }
                )) {
                    Text("unit_suffix").tag("unit_suffix")
                    Text("token_map").tag("token_map")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .labelsHidden()
            }
            LabeledContent("Binding") {
                Text(d.conditionDefinitions[idx].binding)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Shared helpers

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
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .cornerRadius(AppSpacing.xs)
    }

    @ViewBuilder
    private func orderedStringListEditor(items: [String], onChange: @escaping ([String]) -> Void) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Spacer()
                Button("Add") { onChange(items + [""]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: AppSpacing.sm) {
                    VStack(spacing: AppSpacing.xxs) {
                        Button {
                            guard idx > 0 else { return }
                            var updated = items; updated.swapAt(idx - 1, idx); onChange(updated)
                        } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(idx == 0)
                        Button {
                            guard idx < items.count - 1 else { return }
                            var updated = items; updated.swapAt(idx, idx + 1); onChange(updated)
                        } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(idx == items.count - 1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    TextField("source", text: Binding(
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
                        set: { v in var updated = items; updated[key] = v; onChange(updated) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var updated = items; updated.removeValue(forKey: key); onChange(updated)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
                }
            }
        }
    }

    // MARK: - Binding helpers

    private func mapRuleBinding(
        at index: Int,
        keyPath: WritableKeyPath<FilenameParseRulesFileDraft, [FilenameParseRulesFileDraft.MapRule]>
    ) -> Binding<FilenameParseRulesFileDraft.MapRule> {
        Binding(
            get: {
                guard let d = self.draft, d[keyPath: keyPath].indices.contains(index) else {
                    return .init(match: .init(scope: "tokens", type: "equals", value: nil, values: nil), value: "")
                }
                return d[keyPath: keyPath][index]
            },
            set: { newValue in
                guard var d = self.draft, d[keyPath: keyPath].indices.contains(index) else { return }
                d[keyPath: keyPath][index] = newValue
                self.applyDraft(d)
            }
        )
    }

    private func tokenMapRuleBinding(key: String, index: Int) -> Binding<FilenameParseRulesFileDraft.MapRule> {
        Binding(
            get: {
                guard let d = self.draft,
                      let rules = d.conditions.tokenMapRules[key],
                      rules.indices.contains(index) else {
                    return .init(match: .init(scope: "tokens", type: "equals", value: nil, values: nil), value: "")
                }
                return rules[index]
            },
            set: { newValue in
                guard var d = self.draft,
                      var rules = d.conditions.tokenMapRules[key],
                      rules.indices.contains(index) else { return }
                rules[index] = newValue
                d.conditions.tokenMapRules[key] = rules
                self.applyDraft(d)
            }
        )
    }

    // MARK: - Auto-binding for ConditionDefinition

    private func autoBinding(kind: String, id: String) -> String {
        switch kind {
        case "unit_suffix": return "conditions.extraConditions.\(id)"
        case "token_map":   return "conditions.tokenMapRules.\(id)"
        default:            return ""
        }
    }

    // MARK: - Draft mutations

    private func applyDraft(_ d: FilenameParseRulesFileDraft) {
        draft = d
        store.updateFilenameParse(d)
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
        if let current = store.filenameParseDraft { draft = current }
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
}
