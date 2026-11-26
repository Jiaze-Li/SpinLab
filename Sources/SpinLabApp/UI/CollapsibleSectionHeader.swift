import SwiftUI

/// Unified collapsible section header used across Inbox, Library, and Workbench.
///
/// Provides a full-width clickable header row with animated chevron.
/// Callers wrap their own content below, conditionally on `isExpanded`, and indent it by
/// `contentIndent` when it should line up under the title.
///
/// `trailing` is for counts, short status or a hint at the end of the row. It sits inside the
/// header's own button, so it must be display-only: never put a Button, Toggle, Menu or other
/// interactive control there (a nested control's click is ambiguous). The type system cannot
/// enforce this; review does.
struct CollapsibleSectionHeader<Trailing: View>: View {
    /// Leading offset that places expanded content under the title text: chevron width plus gap.
    static var contentIndent: CGFloat { 20 + AppSpacing.sm }

    let title: String
    @Binding var isExpanded: Bool
    var titleFont: Font = AppFontScale.sectionHeader
    private let trailing: Trailing

    init(
        title: String,
        isExpanded: Binding<Bool>,
        titleFont: Font = AppFontScale.sectionHeader,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.titleFont = titleFont
        self.trailing = trailing()
    }

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
                trailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension CollapsibleSectionHeader where Trailing == EmptyView {
    init(title: String, isExpanded: Binding<Bool>, titleFont: Font = AppFontScale.sectionHeader) {
        self.init(title: title, isExpanded: isExpanded, titleFont: titleFont) { EmptyView() }
    }
}
