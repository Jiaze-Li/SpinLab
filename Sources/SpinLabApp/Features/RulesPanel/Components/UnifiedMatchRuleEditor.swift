import SwiftUI

struct UnifiedMatchRuleEditor: View {
    @Binding var type: String
    @Binding var matchValues: [String]
    let outputBinding: Binding<String>?

    private let typeOptions = ["equals", "equalsAny", "contains", "containsAny", "equalsOrContainsAny", "regex"]
    private let multiValueTypes: Set<String> = ["equalsAny", "containsAny", "equalsOrContainsAny"]

    init(
        type: Binding<String>,
        matchValues: Binding<[String]>,
        outputBinding: Binding<String>? = nil
    ) {
        _type = type
        _matchValues = matchValues
        self.outputBinding = outputBinding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Type", selection: $type) {
                ForEach(typeOptions, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: type) { _, newType in normalizeValueStorage(for: newType) }

            if let outputBinding {
                HStack(alignment: .center, spacing: AppSpacing.md) {
                    matchColumn
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    outputColumn(outputBinding)
                }
            } else {
                matchColumn
            }
        }
    }

    private var matchColumn: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("Read from file")
                .font(.caption)
                .foregroundStyle(.secondary)
            if multiValueTypes.contains(type) {
                valuesEditor
            } else {
                TextField("value to match", text: bindingForSingleValue)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputColumn(_ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("Mapped to token")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("token", text: binding)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bindingForSingleValue: Binding<String> {
        Binding(
            get: { matchValues.first ?? "" },
            set: { newValue in
                matchValues = newValue.isEmpty ? [] : [newValue]
            }
        )
    }

    private var valuesEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Match Values")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    matchValues.append("")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(matchValues.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.sm) {
                    TextField("value", text: bindingForListValue(at: index))
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        removeValue(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove value")
                }
            }
        }
    }

    private func bindingForListValue(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard matchValues.indices.contains(index) else { return "" }
                return matchValues[index]
            },
            set: { newValue in
                guard matchValues.indices.contains(index) else { return }
                matchValues[index] = newValue
            }
        )
    }

    private func removeValue(at index: Int) {
        guard matchValues.indices.contains(index) else { return }
        matchValues.remove(at: index)
    }

    private func normalizeValueStorage(for type: String) {
        if multiValueTypes.contains(type) {
            if matchValues.isEmpty || matchValues == [""] {
                matchValues = [""]
            }
        } else {
            let first = matchValues.first ?? ""
            matchValues = first.isEmpty ? [] : [first]
        }
    }
}
