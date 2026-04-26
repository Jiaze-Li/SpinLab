import SwiftUI

struct MatchRuleEditor: View {
    @Binding var rule: MapRule

    private let scopeOptions = ["tokens", "joined"]
    private let typeOptions = ["equals", "equalsAny", "contains", "containsAny", "equalsOrContainsAny", "regex"]
    private let multiValueTypes: Set<String> = ["equalsAny", "containsAny", "equalsOrContainsAny"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Scope", selection: $rule.match.scope) {
                ForEach(scopeOptions, id: \.self) { value in
                    Text(value).tag(value)
                }
            }

            Picker("Type", selection: $rule.match.type) {
                ForEach(typeOptions, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .onChange(of: rule.match.type) { _, newType in
                normalizeValueStorage(for: newType)
            }

            if multiValueTypes.contains(rule.match.type) {
                valuesEditor
            } else {
                TextField("Match Value", text: bindingForSingleValue)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Mapped Value", text: $rule.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var bindingForSingleValue: Binding<String> {
        Binding(
            get: { rule.match.value ?? "" },
            set: { newValue in
                rule.match.value = newValue
                if !newValue.isEmpty {
                    rule.match.values = nil
                }
            }
        )
    }

    private var valuesEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(Array((rule.match.values ?? []).enumerated()), id: \.offset) { index, _ in
                HStack(spacing: AppSpacing.sm) {
                    TextField("Value", text: bindingForListValue(at: index))
                        .textFieldStyle(.roundedBorder)
                    Button("-") { removeValue(at: index) }
                        .buttonStyle(.bordered)
                }
            }
            Button("Add Value") {
                var values = rule.match.values ?? []
                values.append("")
                rule.match.values = values
                rule.match.value = nil
            }
            .buttonStyle(.bordered)
        }
    }

    private func bindingForListValue(at index: Int) -> Binding<String> {
        Binding(
            get: {
                let values = rule.match.values ?? []
                guard values.indices.contains(index) else { return "" }
                return values[index]
            },
            set: { newValue in
                var values = rule.match.values ?? []
                guard values.indices.contains(index) else { return }
                values[index] = newValue
                rule.match.values = values
                if !newValue.isEmpty {
                    rule.match.value = nil
                }
            }
        )
    }

    private func removeValue(at index: Int) {
        guard var values = rule.match.values, values.indices.contains(index) else { return }
        values.remove(at: index)
        rule.match.values = values
    }

    private func normalizeValueStorage(for type: String) {
        if multiValueTypes.contains(type) {
            if rule.match.values == nil {
                let fromSingle = rule.match.value.map { [$0] } ?? []
                rule.match.values = fromSingle
            }
            rule.match.value = nil
        } else {
            if rule.match.value == nil {
                let fromList = (rule.match.values ?? []).first ?? ""
                rule.match.value = fromList
            }
            rule.match.values = nil
        }
    }
}
