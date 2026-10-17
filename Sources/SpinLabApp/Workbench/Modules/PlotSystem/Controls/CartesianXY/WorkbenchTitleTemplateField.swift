import SwiftUI

// MARK: - WorkbenchAvailableTokensHint

/// Shared "Available: #tab #method ..." hint, decoupled from the input row so it can span
/// the full width of its containing panel instead of being constrained by the input row's
/// trailing controls.
struct WorkbenchAvailableTokensHint: View {
    let tokens: [String]

    var body: some View {
        Text("Available: " + tokens.joined(separator: " "))
            .workbenchTextRole(.hint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tokens offered by the stacked-curve and dual-axis renderers: the fixed set plus every
    /// numeric display key of the selected samples.
    static func standardTokens(numericDisplayCache: [String: [String: String]]) -> [String] {
        let fixed = ["#tab", "#method", "#device", "#sample", "#测试温度"]
        let numericKeys = Set(numericDisplayCache.values.flatMap { $0.keys }).sorted().map { "#\($0)" }
        return fixed + numericKeys
    }
}
