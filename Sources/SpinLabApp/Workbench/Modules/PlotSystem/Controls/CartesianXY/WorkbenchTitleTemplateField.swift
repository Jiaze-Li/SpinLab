import SwiftUI

// MARK: - WorkbenchAvailableTokensHint

/// Shared "Available: #tab #method ..." hint, decoupled from the input row so it can span
/// the full width of its containing panel instead of being constrained by the input row's
/// trailing controls.
struct WorkbenchAvailableTokensHint: View {
    let numericDisplayCache: [String: [String: String]]

    var body: some View {
        Text(hint)
            .workbenchTextRole(.hint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String {
        var tokens = ["#tab", "#method", "#device", "#sample", "#测试温度"]
        let numericKeys = numericDisplayCache.values.flatMap { $0.keys }
        for key in Set(numericKeys).sorted() {
            tokens.append("#\(key)")
        }
        return "Available: " + tokens.joined(separator: " ")
    }
}
