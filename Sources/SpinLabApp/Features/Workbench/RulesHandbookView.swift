import AppKit
import SwiftUI

struct RulesHandbookView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [RuleEntry]
    @State private var step: Step = .edit
    @State private var validationIssues: [HandbookValidationIssue] = []
    @State private var proposals: [ConditionChangeProposal] = []
    @State private var acceptedProposalIDs: Set<UUID> = []
    @State private var testInput: String = ""
    @State private var saveError: String?
    @State private var showAddCustomEntrySheet: Bool = false
    @State private var addCustomKind: RuleEntryKind = .unitSuffix
    @State private var showCancelConfirmAlert: Bool = false

    private let store: ConditionRulesHandbookStore
    private let originalEntries: [RuleEntry]
    private let defaultEntries: [RuleEntry]

    init(store: ConditionRulesHandbookStore) {
        self.store = store
        let loaded = store.loadCurrentEntries()
        self.originalEntries = loaded
        self.defaultEntries = store.loadDefaultEntries()
        self._draft = State(initialValue: loaded)
    }

    enum Step {
        case edit
        case confirmSave(diff: RuleEntriesDiff)
        case reviewProposals
    }

    private struct LabelGroup: Identifiable {
        var id: String { ruleID }
        let ruleID: String
        let label: String
        let unitSuffixIndex: Int?
        let tokenMapIndex: Int?
        let readOnlyIndexes: [Int]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rules Handbook")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            switch step {
            case .edit:
                editBody
            case let .confirmSave(diff):
                confirmSaveBody(diff: diff)
            case .reviewProposals:
                reviewProposalsBody
            }
        }
        .frame(minWidth: 560, idealWidth: 820, minHeight: 540, idealHeight: 720)
        .alert("Unsaved Changes", isPresented: $showCancelConfirmAlert) {
            Button("Save and Exit") {
                saveAndDismiss()
            }
            Button("Exit Without Saving", role: .destructive) {
                dismiss()
            }
            Button("Continue Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Save before closing?")
        }
        .sheet(isPresented: $showAddCustomEntrySheet) {
            NewRuleEntrySheet(
                kind: addCustomKind,
                existingEntries: draft,
                onAdd: { ruleID, label in
                    let existingLabel = draft.first(where: {
                        $0.ruleID.caseInsensitiveCompare(ruleID) == .orderedSame
                    })?.label
                    let resolvedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? (existingLabel ?? ConditionFieldCatalog.defaultLabel(for: ruleID))
                        : label.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch addCustomKind {
                    case .unitSuffix:
                        draft.append(
                            RuleEntry(
                                ruleID: ruleID,
                                label: resolvedLabel,
                                kind: .unitSuffix,
                                units: []
                            )
                        )
                    case .tokenMap:
                        draft.append(
                            RuleEntry(
                                ruleID: ruleID,
                                label: resolvedLabel,
                                kind: .tokenMap,
                                mappings: []
                            )
                        )
                    case .customReadOnly:
                        break
                    }
                    validationIssues = []
                    saveError = nil
                }
            )
        }
    }

    private var editBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Edit filename recognition rules. Unit-suffix entries support shorthand like \"xxK\". Token-map entries support exact token matching (for example, \"wafer\") and regex/shorthand matching (for example, \"xxdeg\").")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GroupBox {
                        VStack(spacing: 12) {
                            ForEach(Array(labelGroups.enumerated()), id: \.element.id) { position, group in
                                if position > 0 { Divider() }
                                labelGroupRow(group)
                            }
                        }
                        .padding(4)
                    }

                    let templates = store.addableTemplates(for: draft)
                    HStack(spacing: 10) {
                        Menu("Add Label") {
                            Button("Custom Unit-Suffix…") {
                                addCustomKind = .unitSuffix
                                showAddCustomEntrySheet = true
                            }
                            Button("Custom Token-Map…") {
                                addCustomKind = .tokenMap
                                showAddCustomEntrySheet = true
                            }
                            if !templates.isEmpty { Divider() }
                            ForEach(templates) { template in
                                Button("Built-In: \(template.label) (\(template.kind.rawValue))") {
                                    draft.append(template.materialize())
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }

                    if !validationIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(validationIssues) { issue in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(issue.severity == .error ? .red : .yellow)
                                        .font(.caption)
                                    Text("[\(issue.field)] \(issue.message)")
                                        .font(.caption)
                                        .foregroundStyle(issue.severity == .error ? .red : .primary)
                                }
                            }
                        }
                    }

                    GroupBox("Test a File Name Token") {
                        HStack(spacing: 10) {
                            TextField("e.g. 80K, wafer, 1000Oe, 30deg", text: $testInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                            if testInput.isEmpty {
                                Text("Enter a token to test")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            } else if let result = testMatchResult {
                                Label(result, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.callout)
                            } else {
                                Label("No match", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        }
                        .padding(4)
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.visible)

            Divider()

            HStack {
                Button("Export…") { exportRules() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Revert") {
                    draft = originalEntries
                    validationIssues = []
                    saveError = nil
                }
                .disabled(draft == originalEntries)
                Button("Cancel") {
                    handleCancel()
                }
                .keyboardShortcut(.escape)
                Button("Save") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func confirmSaveBody(diff: RuleEntriesDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Review the changes before saving.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    GroupBox("Changes") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(diff.entries.indices), id: \.self) { index in
                                diffRow(diff.entries[index])
                                if index < diff.entries.count - 1 { Divider() }
                            }
                        }
                        .padding(4)
                    }

                    let warnings = validationIssues.filter { $0.severity == .warning }
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(warnings) { issue in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                    Text("[\(issue.field)] \(issue.message)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.visible)
            .scrollIndicators(.visible)

            Divider()

            HStack {
                Button("Back") { step = .edit }
                Spacer()
                Button("Save & Apply") { commitSave() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var reviewProposalsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if proposals.isEmpty {
                        Text("Rules saved. No existing files in Inbox were affected.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("The following Inbox files have different condition values under the new rules. Select which ones to update.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                                    if index > 0 { Divider() }
                                    proposalRow(proposal)
                                }
                            }
                            .padding(4)
                        }

                        HStack(spacing: 12) {
                            Button("Select All") {
                                acceptedProposalIDs = Set(proposals.map(\.pendingID))
                            }
                            Button("Deselect All") {
                                acceptedProposalIDs = []
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                if proposals.isEmpty {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Skip") { dismiss() }
                    Button("Apply Selected (\(acceptedProposalIDs.count))") {
                        appState.applyConditionRuleProposals(pendingIDs: acceptedProposalIDs)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(acceptedProposalIDs.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func labelGroupRow(_ group: LabelGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.label)
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Remove Label", role: .destructive) {
                    draft.removeAll { $0.ruleID.caseInsensitiveCompare(group.ruleID) == .orderedSame }
                    validationIssues = []
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            GroupBox("Conditions") {
                VStack(alignment: .leading, spacing: 10) {
                    if group.unitSuffixIndex != nil {
                        conditionCard(for: .unitSuffix, index: group.unitSuffixIndex, group: group)
                    }
                    if group.tokenMapIndex != nil {
                        conditionCard(for: .tokenMap, index: group.tokenMapIndex, group: group)
                    }

                    let canAddUnit = group.unitSuffixIndex == nil
                    let canAddToken = group.tokenMapIndex == nil
                    if canAddUnit && canAddToken {
                        Text("No mapping configured.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if canAddUnit || canAddToken {
                        HStack {
                            Text("Add mapping for this label")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Menu("Add Mapping") {
                                if canAddUnit {
                                    Button("Unit Suffix") {
                                        addCondition(kind: .unitSuffix, group: group)
                                    }
                                }
                                if canAddToken {
                                    Button("Token Map") {
                                        addCondition(kind: .tokenMap, group: group)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            ForEach(group.readOnlyIndexes, id: \.self) { idx in
                if draft.indices.contains(idx) {
                    customReadOnlyRow(entry: draft[idx], ruleID: group.ruleID)
                }
            }
        }
    }

    @ViewBuilder
    private func conditionCard(for kind: RuleEntryKind, index: Int?, group: LabelGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind == .unitSuffix ? "Unit Suffix" : "Token Map")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let index {
                switch kind {
                case .unitSuffix:
                    unitSuffixConditionRow(index: index, ruleID: group.ruleID)
                case .tokenMap:
                    tokenMapConditionRow(index: index, ruleID: group.ruleID)
                case .customReadOnly:
                    EmptyView()
                }
            } else {
                Text("No mapping configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }

    private func addCondition(kind: RuleEntryKind, group: LabelGroup) {
        switch kind {
        case .unitSuffix:
            draft.append(
                RuleEntry(
                    ruleID: group.ruleID,
                    label: group.label,
                    kind: .unitSuffix,
                    units: []
                )
            )
        case .tokenMap:
            draft.append(
                RuleEntry(
                    ruleID: group.ruleID,
                    label: group.label,
                    kind: .tokenMap,
                    mappings: []
                )
            )
        case .customReadOnly:
            return
        }
        validationIssues = []
        saveError = nil
    }

    private func unitSuffixConditionRow(index: Int, ruleID: String) -> some View {
        let defaultUnits = defaultEntries.first { $0.ruleID == draft[index].ruleID && $0.kind == .unitSuffix }?.units ?? []
        return HStack(alignment: .top, spacing: 10) {
            UnitTagEditor(units: Binding(
                get: { draft[index].units },
                set: { draft[index].units = $0 }
            ))
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Reset") {
                draft[index].units = defaultUnits
                validationIssues = []
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Menu {
                Button("Remove Entry", role: .destructive) {
                    draft.remove(at: index)
                    validationIssues = []
                }
                Button("Remove Label", role: .destructive) {
                    draft.removeAll { $0.ruleID.caseInsensitiveCompare(ruleID) == .orderedSame }
                    validationIssues = []
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.borderless)
        }
    }

    private func tokenMapConditionRow(index: Int, ruleID: String) -> some View {
        let defaultMappings = defaultEntries.first { $0.ruleID == draft[index].ruleID && $0.kind == .tokenMap }?.mappings ?? []
        return HStack(alignment: .top, spacing: 10) {
            TokenMapEditor(mappings: Binding(
                get: { draft[index].mappings },
                set: { draft[index].mappings = $0 }
            ))
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Reset") {
                draft[index].mappings = defaultMappings
                validationIssues = []
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Menu {
                Button("Remove Entry", role: .destructive) {
                    draft.remove(at: index)
                    validationIssues = []
                }
                Button("Remove Label", role: .destructive) {
                    draft.removeAll { $0.ruleID.caseInsensitiveCompare(ruleID) == .orderedSame }
                    validationIssues = []
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.borderless)
        }
    }

    private func customReadOnlyRow(entry: RuleEntry, ruleID: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Read-only custom rule")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.readOnlyMessage ?? "This entry cannot be edited in handbook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Remove Label", role: .destructive) {
                draft.removeAll { $0.ruleID.caseInsensitiveCompare(ruleID) == .orderedSame }
                validationIssues = []
            }
            .font(.caption)
            .buttonStyle(.borderless)
            Spacer()
        }
    }

    private func diffRow(_ entryDiff: RuleEntriesDiff.EntryDiff) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entryDiff.label)
                .font(.callout.weight(.medium))
                .frame(width: 110, alignment: .leading)
            if entryDiff.hasChanges {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entryDiff.before)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .font(.caption.monospaced())
                    Text(entryDiff.after)
                        .foregroundStyle(.primary)
                        .font(.caption.monospaced())
                }
            } else {
                Text("No change")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private func proposalRow(_ proposal: ConditionChangeProposal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { acceptedProposalIDs.contains(proposal.pendingID) },
                set: { checked in
                    if checked { acceptedProposalIDs.insert(proposal.pendingID) }
                    else { acceptedProposalIDs.remove(proposal.pendingID) }
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.fileName)
                    .font(.callout.weight(.medium))
                ForEach(proposal.changes, id: \.label) { change in
                    HStack(spacing: 6) {
                        Text(change.label + ":")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(change.before ?? "—")
                            .strikethrough()
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(change.after ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func saveAndDismiss() {
        saveError = nil
        let issues = store.validate(draft)
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            validationIssues = issues
            return
        }
        do {
            if draft != originalEntries {
                validationIssues = issues
                try store.save(draft)
            }
            dismiss()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func handleCancel() {
        if draft == originalEntries {
            dismiss()
            return
        }
        showCancelConfirmAlert = true
    }

    private func commitSave() {
        do {
            try store.save(draft)
            let found = appState.dryRunConditionRuleRecompute()
            proposals = found
            acceptedProposalIDs = Set(found.map(\.id))
            step = .reviewProposals
        } catch {
            step = .edit
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "filename_rules.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
        } catch {
            saveError = "Export failed: \(error.localizedDescription)"
        }
    }

    private var testMatchResult: String? {
        let input = testInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        for entry in draft {
            switch entry.kind {
            case .unitSuffix:
                let pattern = RulePatternCodec.pattern(from: entry.units)
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                if regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil {
                    return "→ \(entry.label)"
                }
            case .tokenMap:
                for mapping in entry.mappings {
                    let value = mapping.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch mapping.matchType {
                    case .equals:
                        if input.caseInsensitiveCompare(mapping.pattern.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                            return value.isEmpty ? "→ \(entry.label) (\(input))" : "→ \(entry.label) (\(value))"
                        }
                    case .regex:
                        let pattern = RulePatternCodec.regexPattern(from: mapping.pattern)
                        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                        if regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil {
                            return value.isEmpty ? "→ \(entry.label) (\(input))" : "→ \(entry.label) (\(value))"
                        }
                    }
                }
            case .customReadOnly:
                continue
            }
        }

        return nil
    }

    private var labelGroups: [LabelGroup] {
        var grouped: [String: (label: String, unit: Int?, token: Int?, readonly: [Int])] = [:]
        var order: [String] = []

        for (index, entry) in draft.enumerated() {
            let key = entry.ruleID.lowercased()
            if grouped[key] == nil {
                grouped[key] = (label: entry.label, unit: nil, token: nil, readonly: [])
                order.append(key)
            }
            guard var value = grouped[key] else { continue }
            if value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !entry.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                value.label = entry.label
            }
            switch entry.kind {
            case .unitSuffix:
                value.unit = index
            case .tokenMap:
                value.token = index
            case .customReadOnly:
                value.readonly.append(index)
            }
            grouped[key] = value
        }

        return order.compactMap { key in
            guard let value = grouped[key] else { return nil }
            let ruleID = (value.unit.flatMap { draft[$0].ruleID })
                ?? (value.token.flatMap { draft[$0].ruleID })
                ?? (value.readonly.first.map { draft[$0].ruleID })
                ?? key
            let label = value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ConditionFieldCatalog.defaultLabel(for: ruleID)
                : value.label
            return LabelGroup(
                ruleID: ruleID,
                label: label,
                unitSuffixIndex: value.unit,
                tokenMapIndex: value.token,
                readOnlyIndexes: value.readonly
            )
        }
    }

}

private struct UnitTagEditor: View {
    @Binding var units: [String]
    @State private var newUnit: String = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(Array(units.enumerated()), id: \.offset) { index, unit in
                HStack(spacing: 3) {
                    Text(unit)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                    Button {
                        units.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 4)
                }
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }

            HStack(spacing: 4) {
                TextField("Add", text: $newUnit)
                    .font(.caption.monospaced())
                    .textFieldStyle(.plain)
                    .frame(width: max(30, CGFloat(newUnit.count) * 8 + 16))
                    .focused($isAddFieldFocused)
                    .onSubmit { commitNewUnit() }
                if !newUnit.isEmpty {
                    Button { commitNewUnit() } label: {
                        Image(systemName: "return")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            )
        }
    }

    private func commitNewUnit() {
        let trimmed = newUnit.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !units.contains(trimmed) else {
            newUnit = ""
            return
        }
        units.append(trimmed)
        newUnit = ""
    }
}

private struct TokenMapEditor: View {
    @Binding var mappings: [TokenMapping]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mappings.isEmpty {
                Text("No mapping. Add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(mappings.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { mappings[index].matchType },
                        set: { mappings[index].matchType = $0 }
                    )) {
                        Text("equals").tag(TokenMatchType.equals)
                        Text("regex").tag(TokenMatchType.regex)
                    }
                    .labelsHidden()
                    .frame(width: 90)

                    TextField("pattern (e.g. wafer or xxdeg)", text: Binding(
                        get: { mappings[index].pattern },
                        set: { mappings[index].pattern = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("value (blank = matched token)", text: Binding(
                        get: { mappings[index].value },
                        set: { mappings[index].value = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        mappings.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button("Add Mapping") {
                mappings.append(TokenMapping(pattern: "", value: ""))
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct NewRuleEntrySheet: View {
    let kind: RuleEntryKind
    let existingEntries: [RuleEntry]
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ruleID: String = ""
    @State private var label: String = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .tokenMap ? "New Token-Map Entry" : "New Unit-Suffix Entry")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Rule ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. wafer_type", text: $ruleID)
                    .textFieldStyle(.roundedBorder)
                Text("Label (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Wafer Type", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            GroupBox("Save Preview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Binding: \(resolvedBindingPreview)")
                        .font(.caption.monospaced())
                    if let reservedNotice {
                        Text(reservedNotice)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(bindingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    commit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func commit() {
        let normalizedID = ruleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            validationError = "Rule ID cannot be empty."
            return
        }
        guard !normalizedID.contains(where: { $0.isWhitespace }) else {
            validationError = "Rule ID cannot contain spaces."
            return
        }
        let existsSameKind = existingEntries.contains {
            $0.ruleID.caseInsensitiveCompare(normalizedID) == .orderedSame &&
            $0.kind == kind
        }
        guard !existsSameKind else {
            validationError = "This label already has a \(kind.rawValue) entry."
            return
        }

        onAdd(normalizedID, label)
        dismiss()
    }

    private var resolvedBindingPreview: String {
        let normalizedID = ruleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            return kind == .tokenMap ? "conditions.tokenMapRules.<rule_id>" : "conditions.extraConditions.<rule_id>"
        }
        switch kind {
        case .unitSuffix:
            return "conditions.extraConditions.\(normalizedID)"
        case .tokenMap:
            return "conditions.tokenMapRules.\(normalizedID)"
        case .customReadOnly:
            return "n/a"
        }
    }

    private var bindingDescription: String {
        switch kind {
        case .unitSuffix:
            return "Unit-suffix entries match tokens like 20K/1mA and are stored as regex-backed condition patterns."
        case .tokenMap:
            return "Token-map entries match text tokens and map them to normalized condition values for workflow fields."
        case .customReadOnly:
            return "Read-only entries cannot be created from this dialog."
        }
    }

    private var reservedNotice: String? { nil }
}
