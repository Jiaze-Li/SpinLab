import SwiftUI

struct WrappingValueText: View {
    let value: String
    var monospaced: Bool = false

    var body: some View {
        Text(value)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
    }
}

struct MetadataValueRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            WrappingValueText(value: value, monospaced: monospaced)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditableMetadataField: View {
    let label: String
    @Binding var value: String
    var isAuto: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isAuto {
                    Text("Auto")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }
            }
            TextField(label, text: $value, axis: .vertical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
