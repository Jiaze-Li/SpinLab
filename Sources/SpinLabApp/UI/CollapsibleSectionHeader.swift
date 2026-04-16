import SwiftUI

/// Unified collapsible section header used across Inbox, Library, and Workbench.
///
/// Provides a full-width clickable header row with animated chevron.
/// Callers wrap their own content below, conditionally on `isExpanded`.
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    var titleFont: Font = AppFontScale.sectionHeader

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(titleFont)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
