import SwiftUI

enum MatchRuleOutputBehavior: Equatable {
    case none
    case editable(title: String)
    case editableWithLockedOps(title: String, lockedOps: Set<FilenameRuleSet.Operation>, lockedValue: String)
}

// Unified rule editor — two init overloads:
// • specs: Binding<[MatchSpec]>   – no output column; for Batch ID / Substrate
// • rules: Binding<[MapRule]>     – with output column; for Workflow tag rules / Condition
struct MatchRulesEditor: View {
    private enum Content {
        case specs(Binding<[FilenameRuleSet.MatchSpec]>)
        case rules(Binding<[MapRule]>, MatchRuleOutputBehavior)
    }
    private let content: Content
    let allowedOps: [FilenameRuleSet.Operation]
    let defaultOp: FilenameRuleSet.Operation

    init(
        specs: Binding<[FilenameRuleSet.MatchSpec]>,
        allowedOps: [FilenameRuleSet.Operation],
        defaultOp: FilenameRuleSet.Operation
    ) {
        self.content = .specs(specs)
        self.allowedOps = allowedOps
        self.defaultOp = defaultOp
    }

    init(
        rules: Binding<[MapRule]>,
        allowedOps: [FilenameRuleSet.Operation],
        defaultOp: FilenameRuleSet.Operation,
        outputBehavior: MatchRuleOutputBehavior
    ) {
        self.content = .rules(rules, outputBehavior)
        self.allowedOps = allowedOps
        self.defaultOp = defaultOp
    }

    var body: some View {
        switch content {
        case .specs(let specsBinding):
            SpecsEditorBody(specs: specsBinding, allowedOps: allowedOps, defaultOp: defaultOp)
        case .rules(let rulesBinding, let outputBehavior):
            MapRulesEditorBody(
                rules: rulesBinding,
                allowedOps: allowedOps,
                defaultOp: defaultOp,
                outputBehavior: outputBehavior
            )
        }
    }
}

private struct SpecsEditorBody: View {
    @Binding var specs: [FilenameRuleSet.MatchSpec]
    let allowedOps: [FilenameRuleSet.Operation]
    let defaultOp: FilenameRuleSet.Operation

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Matches")
                .font(AppFontScale.groupHeader)
            ForEach(specs.indices, id: \.self) { idx in
                MatchRuleRowShell(
                    opRawValue: Binding(
                        get: { specs[idx].type.rawValue },
                        set: { v in specs[idx].type = FilenameRuleSet.Operation(rawValue: v) ?? defaultOp }
                    ),
                    value: Binding(get: { specs[idx].value }, set: { specs[idx].value = $0 }),
                    allowedOps: allowedOps,
                    onDelete: { specs.remove(at: idx) }
                ) { EmptyView() }
            }
            Button("Add") {
                specs.append(FilenameRuleSet.MatchSpec(type: defaultOp, value: ""))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct MapRulesEditorBody: View {
    @Binding var rules: [MapRule]
    let allowedOps: [FilenameRuleSet.Operation]
    let defaultOp: FilenameRuleSet.Operation
    let outputBehavior: MatchRuleOutputBehavior

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Matches")
                .font(AppFontScale.groupHeader)
            ForEach(rules.indices, id: \.self) { idx in
                let op = FilenameRuleSet.Operation(rawValue: rules[idx].match.type)
                let isLocked = isOpLocked(op)
                MatchRuleRowShell(
                    opRawValue: Binding(
                        get: { rules[idx].match.type },
                        set: { newType in
                            let newOp = FilenameRuleSet.Operation(rawValue: newType)
                            rules[idx].match.type = newType
                            if isOpLocked(newOp) {
                                rules[idx].value = lockedSentinel()
                            } else if isLocked {
                                rules[idx].value = ""
                            }
                        }
                    ),
                    value: Binding(
                        get: { rules[idx].match.value },
                        set: { rules[idx].match.value = $0 }
                    ),
                    allowedOps: allowedOps,
                    onDelete: { rules.remove(at: idx) }
                ) {
                    outputTrailing(idx: idx, isLocked: isLocked)
                }
            }
            Button("Add") {
                let op = defaultOp
                let outputValue = isOpLocked(op) ? lockedSentinel() : ""
                rules.append(MapRule(match: .init(type: op.rawValue, value: ""), value: outputValue))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func outputTrailing(idx: Int, isLocked: Bool) -> some View {
        switch outputBehavior {
        case .none:
            EmptyView()
        case .editable(let title), .editableWithLockedOps(let title, _, _):
            TextField(title, text: Binding(
                get: { rules[idx].value },
                set: { if !isLocked { rules[idx].value = $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .frame(maxWidth: .infinity)
            .disabled(isLocked)
            .foregroundStyle(isLocked ? .secondary : .primary)
        }
    }

    private func isOpLocked(_ op: FilenameRuleSet.Operation?) -> Bool {
        guard case .editableWithLockedOps(_, let lockedOps, _) = outputBehavior else { return false }
        guard let op else { return false }
        return lockedOps.contains(op)
    }

    private func lockedSentinel() -> String {
        if case .editableWithLockedOps(_, _, let value) = outputBehavior { return value }
        return ""
    }
}

private struct MatchRuleRowShell<Trailing: View>: View {
    @Binding var opRawValue: String
    @Binding var value: String
    let allowedOps: [FilenameRuleSet.Operation]
    let onDelete: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Picker("", selection: $opRawValue) {
                ForEach(allowedOps, id: \.rawValue) { op in
                    Text(op.rawValue).tag(op.rawValue)
                }
            }
            .labelsHidden()
            .fixedSize()

            TextField("value", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity)

            trailing()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove")
        }
    }
}
