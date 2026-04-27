import SwiftUI

struct MatchRuleEditor: View {
    @Binding var rule: MapRule

    private let scopeOptions = ["tokens", "joined"]
    private let typeOptions = ["equals", "equalsAny", "contains", "containsAny", "equalsOrContainsAny", "regex"]
    private let multiValueTypes: Set<String> = ["equalsAny", "containsAny", "equalsOrContainsAny"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Scope", selection: $rule.match.scope) {
                ForEach(scopeOptions, id: \.self) { Text($0).tag($0) }
            }

            Picker("Type", selection: $rule.match.type) {
                ForEach(typeOptions, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: rule.match.type) { _, newType in normalizeValueStorage(for: newType) }

            HStack(alignment: .center, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Read from file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if multiValueTypes.contains(rule.match.type) {
                        valuesEditor
                    } else {
                        TextField("value to match", text: bindingForSingleValue)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Mapped to token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("token", text: $rule.value)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var bindingForSingleValue: Binding<String> {
        Binding(
            get: { rule.match.matchValues.first ?? "" },
            set: { newValue in
                rule.match.matchValues = newValue.isEmpty ? [] : [newValue]
            }
        )
    }

    private var valuesEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(Array(rule.match.matchValues.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: AppSpacing.sm) {
                    TextField("Value", text: bindingForListValue(at: index))
                        .textFieldStyle(.roundedBorder)
                    Button("-") { removeValue(at: index) }
                        .buttonStyle(.bordered)
                }
            }
            Button("Add Value") {
                rule.match.matchValues.append("")
            }
            .buttonStyle(.bordered)
        }
    }

    private func bindingForListValue(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard rule.match.matchValues.indices.contains(index) else { return "" }
                return rule.match.matchValues[index]
            },
            set: { newValue in
                guard rule.match.matchValues.indices.contains(index) else { return }
                rule.match.matchValues[index] = newValue
            }
        )
    }

    private func removeValue(at index: Int) {
        guard rule.match.matchValues.indices.contains(index) else { return }
        rule.match.matchValues.remove(at: index)
    }

    private func normalizeValueStorage(for type: String) {
        if multiValueTypes.contains(type) {
            if rule.match.matchValues.isEmpty || rule.match.matchValues == [""] {
                rule.match.matchValues = [""]
            }
        } else {
            let first = rule.match.matchValues.first ?? ""
            rule.match.matchValues = first.isEmpty ? [] : [first]
        }
    }
}
