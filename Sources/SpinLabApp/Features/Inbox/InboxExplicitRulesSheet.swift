import SwiftUI

struct InboxExplicitRulesSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var workbench = appState.workbench

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Explicit Rules")
                    .font(AppFontScale.sectionTitle)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            if let message = workbench.workflowRegistryMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox("Sample ID Patterns") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Regex patterns used for sample ID recognition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if workbench.sampleIDPatterns.isEmpty {
                        Text("No patterns defined.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(workbench.sampleIDPatterns.enumerated()), id: \.offset) { index, pattern in
                            HStack(spacing: 8) {
                                TextField("Regex pattern", text: Binding(
                                    get: { pattern },
                                    set: { workbench.updateSampleIDPattern(at: index, value: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                                Button(role: .destructive) {
                                    workbench.removeSampleIDPattern(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete")
                            }
                        }
                    }

                    Button {
                        workbench.addSampleIDPattern()
                    } label: {
                        Label("Add Pattern", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 8) {
                        Button("Discard") {
                            workbench.discardSampleIDPatternEdits()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!workbench.hasUnsavedSampleIDPatterns)

                        Button("Confirm Save") {
                            workbench.confirmSampleIDPatternsSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!workbench.hasUnsavedSampleIDPatterns)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("Substrate Rules") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Origin recognition and substrate tag mapping.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Token Separators")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "_-",
                                text: Binding(
                                    get: { workbench.substrateTokenSeparators },
                                    set: { workbench.updateSubstrateTokenSeparators($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Origin Standalone Tokens (comma-separated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "O, o",
                                text: Binding(
                                    get: { workbench.substrateOriginStandaloneTokens.joined(separator: ", ") },
                                    set: { workbench.updateSubstrateOriginStandaloneTokensCSV($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Origin Contains Tokens (comma-separated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "ORIGIN, ORIGINAL",
                                text: Binding(
                                    get: { workbench.substrateOriginContainsTokens.joined(separator: ", ") },
                                    set: { workbench.updateSubstrateOriginContainsTokensCSV($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }

                        Divider()

                        Text("Substrate Tag Rules")
                            .font(.subheadline.weight(.semibold))

                        if workbench.substrateTagRules.isEmpty {
                            Text("No substrate tag rules.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(workbench.substrateTagRules) { rule in
                                HStack(alignment: .top, spacing: 8) {
                                    Picker(
                                        "Scope",
                                        selection: Binding(
                                            get: { rule.scope },
                                            set: { workbench.updateSubstrateTagRuleScope(rule.id, scope: $0) }
                                        )
                                    ) {
                                        Text("tokens").tag(FilenameRuleSet.MatchScope.tokens)
                                        Text("joined").tag(FilenameRuleSet.MatchScope.joined)
                                    }
                                    .labelsHidden()
                                    .frame(width: 92)

                                    Picker(
                                        "Type",
                                        selection: Binding(
                                            get: { rule.type },
                                            set: { workbench.updateSubstrateTagRuleType(rule.id, type: $0) }
                                        )
                                    ) {
                                        ForEach(substrateMatchTypeOptions(for: rule.type), id: \.self) { option in
                                            Text(substrateMatchTypeLabel(option)).tag(option)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)

                                    TextField(
                                        "match values",
                                        text: Binding(
                                            get: { workbench.substrateTagRuleValuesCSV(rule.id) },
                                            set: { workbench.updateSubstrateTagRuleValuesCSV(rule.id, csv: $0) }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))

                                    TextField(
                                        "tag value",
                                        text: Binding(
                                            get: { rule.value },
                                            set: { workbench.updateSubstrateTagRuleValue(rule.id, value: $0) }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 120)

                                    Button(role: .destructive) {
                                        workbench.removeSubstrateTagRule(rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Button {
                            workbench.addSubstrateTagRule()
                        } label: {
                            Label("Add Substrate Rule", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)

                        HStack(spacing: 8) {
                            Button("Discard") {
                                workbench.discardSubstrateRuleEdits()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!workbench.hasUnsavedSubstrateRules)

                            Button("Confirm Save") {
                                workbench.confirmSubstrateRulesSave()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!workbench.hasUnsavedSubstrateRules)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .frame(minHeight: 280, maxHeight: 420)
            }
        }
        .padding(18)
        .frame(minWidth: 900, minHeight: 700)
    }

    private func substrateMatchTypeOptions(for current: FilenameRuleSet.MatchType) -> [FilenameRuleSet.MatchType] {
        let preferred: [FilenameRuleSet.MatchType] = [.equals, .contains, .regex, .equalsAny, .containsAny, .equalsOrContainsAny]
        if preferred.contains(current) { return preferred }
        return preferred + [current]
    }

    private func substrateMatchTypeLabel(_ type: FilenameRuleSet.MatchType) -> String {
        switch type {
        case .equals: return "equals"
        case .contains: return "contains"
        case .regex: return "regex"
        case .equalsAny: return "equalsAny"
        case .containsAny: return "containsAny"
        case .equalsOrContainsAny: return "equalsOrContainsAny"
        }
    }
}
