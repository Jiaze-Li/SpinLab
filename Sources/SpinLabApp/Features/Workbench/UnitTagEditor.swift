import SwiftUI

struct UnitTagEditor: View {
    @Binding var units: [String]
    @State private var newUnit: String = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
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
                    .accessibilityLabel("Remove unit")
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
                    .accessibilityLabel("Confirm add unit")
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
