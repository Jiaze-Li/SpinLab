import SwiftUI

struct TokenMapEditor: View {
    @Binding var mappings: [TokenMapping]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mappings.isEmpty {
                Text("No mapping. Add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(mappings.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
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
                        .accessibilityLabel("Delete mapping")
                    }

                    if mappings[index].value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Using matched token value ($MATCH)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Add Mapping") {
                mappings.append(TokenMapping(pattern: "", value: ""))
            }
            .buttonStyle(.bordered)
        }
    }
}
