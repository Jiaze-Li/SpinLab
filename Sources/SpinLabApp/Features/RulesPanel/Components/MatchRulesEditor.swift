import SwiftUI

// Flat, one-row-per-spec editor for match specs.
// Row layout: [Op Picker] [Value TextField] [Delete]
struct MatchRulesEditor: View {
    @Binding var rules: [FilenameRuleSet.MatchSpec]
    let allowedOps: [FilenameRuleSet.Operation]
    let defaultOp: FilenameRuleSet.Operation

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Matches")
                .font(AppFontScale.groupHeader)
            ForEach(rules.indices, id: \.self) { idx in
                MatchRuleRowShell(
                    opRawValue: Binding(
                        get: { rules[idx].type.rawValue },
                        set: { v in rules[idx].type = FilenameRuleSet.Operation(rawValue: v) ?? defaultOp }
                    ),
                    value: Binding(get: { rules[idx].value }, set: { rules[idx].value = $0 }),
                    allowedOps: allowedOps,
                    onDelete: { rules.remove(at: idx) }
                ) { EmptyView() }
            }
            Button("Add") {
                rules.append(FilenameRuleSet.MatchSpec(type: defaultOp, value: ""))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// Flat, one-row-per-rule editor for map rules (match → output value).
// Row layout: [Op Picker] [Value TextField] [Output TextField] [Delete]
struct MatchMapRulesEditor: View {
    @Binding var rules: [MapRule]
    let allowedOps: [FilenameRuleSet.Operation]
    let defaultOp: FilenameRuleSet.Operation
    var outputTitle: String = "Output"

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Matches")
                .font(AppFontScale.groupHeader)
            ForEach(rules.indices, id: \.self) { idx in
                MatchRuleRowShell(
                    opRawValue: Binding(
                        get: { rules[idx].match.type },
                        set: { rules[idx].match.type = $0 }
                    ),
                    value: Binding(
                        get: { rules[idx].match.matchValues.first ?? "" },
                        set: { rules[idx].match.matchValues = $0.isEmpty ? [] : [$0] }
                    ),
                    allowedOps: allowedOps,
                    onDelete: { rules.remove(at: idx) }
                ) {
                    TextField(outputTitle, text: Binding(
                        get: { rules[idx].value },
                        set: { rules[idx].value = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity)
                }
            }
            Button("Add") {
                rules.append(MapRule(
                    match: .init(scope: "tokens", type: defaultOp.rawValue, matchValues: []),
                    value: ""
                ))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// Shared row shell. Trailing is either EmptyView (MatchRulesEditor) or an output TextField (MatchMapRulesEditor).
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
