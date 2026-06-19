import SwiftUI

/// Shared visual tokens for compact Workbench controls.
///
/// This layer composes the base app typography and spacing scales rather than
/// introducing new ad-hoc numbers in individual control views.
enum WorkbenchUIStyle {
    static let controlLabelFont: Font = AppFontScale.minimumReadable.weight(.semibold)
    static let controlValueFont: Font = AppFontScale.minimumReadable
    static let controlHintFont: Font = AppFontScale.minimumReadable
    static let minimumReadableFont: Font = AppFontScale.minimumReadable

    static let secondaryTextColor: Color = .secondary
    static let primaryTextColor: Color = .primary
    static let warningColor: Color = .orange
    static let errorColor: Color = .red

    static let confidenceBadgeFont: Font = AppFontScale.minimumReadable.weight(.semibold)
    static let confidenceBadgeForeground: Color = .accentColor
    static let confidenceBadgeBackground: Color = Color.accentColor.opacity(0.12)

    static let chipBackground: Color = Color.secondary.opacity(0.12)
    static let chipCornerRadius: CGFloat = 4
    static let chipHorizontalPadding: CGFloat = AppSpacing.xs
    static let chipVerticalPadding: CGFloat = AppSpacing.xxs
    static let controlRowSpacing: CGFloat = AppSpacing.xs
    static let controlInlineSpacing: CGFloat = AppSpacing.xs
}
