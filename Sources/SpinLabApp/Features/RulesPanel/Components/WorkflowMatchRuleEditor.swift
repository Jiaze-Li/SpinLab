import SwiftUI

struct WorkflowMatchRuleEditor: View {
    @Binding var spec: WorkflowFileDraft.WorkflowMatchSpec

    private let scopeOptions = ["tokens", "joined"]
    private let typeOptions = ["equals", "equalsAny", "contains", "containsAny", "equalsOrContainsAny", "regex"]
    private let multiValueTypes: Set<String> = ["equalsAny", "containsAny", "equalsOrContainsAny"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Scope", selection: $spec.scope) {
                ForEach(scopeOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }

            Picker("Type", selection: $spec.type) {
                ForEach(typeOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .onChange(of: spec.type) { _, newType in
                normalizeValueStorage(for: newType)
            }

            if multiValueTypes.contains(spec.type) {
                valuesEditor
            } else {
                TextField("Match Value", text: bindingForSingleValue)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var valuesEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Match Values")
                    .font(AppFontScale.groupHeader)
                Spacer()
                Button("Add") {
                    var values = spec.values ?? []
                    values.append("")
                    spec.values = values
                    spec.value = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach((spec.values ?? []).indices, id: \.self) { index in
                HStack(spacing: AppSpacing.sm) {
                    TextField(
                        "value",
                        text: Binding(
                            get: { (spec.values ?? [])[safe: index] ?? "" },
                            set: { newValue in
                                var values = spec.values ?? []
                                guard values.indices.contains(index) else { return }
                                values[index] = newValue
                                spec.values = values
                                spec.value = nil
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        var values = spec.values ?? []
                        guard values.indices.contains(index) else { return }
                        values.remove(at: index)
                        spec.values = values
                        spec.value = nil
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove value")
                }
            }
        }
    }

    private var bindingForSingleValue: Binding<String> {
        Binding(
            get: { spec.value ?? "" },
            set: { newValue in
                spec.value = newValue
                spec.values = nil
            }
        )
    }

    private func normalizeValueStorage(for type: String) {
        if multiValueTypes.contains(type) {
            let seed = spec.value.flatMap { $0.isEmpty ? nil : $0 }
            if spec.values == nil {
                spec.values = seed.map { [$0] } ?? []
            }
            spec.value = nil
        } else {
            if let values = spec.values, !values.isEmpty {
                spec.value = values[0]
            } else if spec.value == nil {
                spec.value = ""
            }
            spec.values = nil
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
