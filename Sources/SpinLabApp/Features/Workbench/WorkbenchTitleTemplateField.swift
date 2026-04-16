import SwiftUI

// MARK: - WorkbenchTitleTemplateField

/// Shared title template input field with dynamic hint showing available tokens.
/// Used by 3ω and AHE plot controls.
struct WorkbenchTitleTemplateField: View {
    @Binding var titleTemplate: String
    let numericDisplayCache: [String: [String: String]]
    var onChange: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Title")
                    .font(.body)
                TextField("#tab #device #sample", text: $titleTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onChange(of: titleTemplate) { _, _ in
                        onChange?()
                    }
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var hint: String {
        var tokens = ["#tab", "#method", "#device", "#sample"]
        let numericKeys = numericDisplayCache.values.flatMap { $0.keys }
        for key in Set(numericKeys).sorted() {
            tokens.append("#\(key)")
        }
        return "Available: " + tokens.joined(separator: " ")
    }
}
