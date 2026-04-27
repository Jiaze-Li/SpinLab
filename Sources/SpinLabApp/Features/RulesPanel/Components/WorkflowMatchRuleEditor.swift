import SwiftUI

struct WorkflowMatchRuleEditor: View {
    @Binding var spec: WorkflowFileDraft.WorkflowMatchSpec

    private let scopeOptions = ["tokens", "joined"]
    private let typeOptions = ["equals", "equalsAny", "contains", "containsAny", "equalsOrContainsAny", "regex"]
    private let multiValueTypes: Set<String> = ["equalsAny", "containsAny", "equalsOrContainsAny"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Scope", selection: $spec.scope) {
                ForEach(scopeOptions, id: \.self) { Text($0).tag($0) }
            }
            Picker("Type", selection: $spec.type) {
                ForEach(typeOptions, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: spec.type) { _, newType in normalizeValueStorage(for: newType) }

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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    spec.matchValues.append("")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(spec.matchValues.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.sm) {
                    TextField(
                        "value",
                        text: Binding(
                            get: { spec.matchValues.indices.contains(index) ? spec.matchValues[index] : "" },
                            set: { newValue in
                                guard spec.matchValues.indices.contains(index) else { return }
                                spec.matchValues[index] = newValue
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        guard spec.matchValues.indices.contains(index) else { return }
                        spec.matchValues.remove(at: index)
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
            get: { spec.matchValues.first ?? "" },
            set: { newValue in
                spec.matchValues = newValue.isEmpty ? [] : [newValue]
            }
        )
    }

    private func normalizeValueStorage(for type: String) {
        if multiValueTypes.contains(type) {
            if spec.matchValues.isEmpty || spec.matchValues == [""] {
                spec.matchValues = [""]
            }
        } else {
            let first = spec.matchValues.first ?? ""
            spec.matchValues = first.isEmpty ? [] : [first]
        }
    }
}
