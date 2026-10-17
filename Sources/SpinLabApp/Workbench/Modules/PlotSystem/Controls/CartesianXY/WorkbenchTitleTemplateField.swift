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
}
