import SwiftUI

// MARK: - PlotControlSection

/// Shared GroupBox wrapper for plot control sections.
struct PlotControlSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.vertical, 4)
        }
    }
}
