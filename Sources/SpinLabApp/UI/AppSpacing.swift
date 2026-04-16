import SwiftUI

/// App-wide spacing scale for consistent visual rhythm.
///
/// All new layout code should use these constants instead of bare numeric literals.
/// Legacy values (3, 10, 14) should be migrated to the nearest scale value
/// when the surrounding code is next modified.
///
/// Scale rationale:
/// - xxs (2): tight inline elements, minimal VStack gaps
/// - xs  (4): compact groups, small internal padding
/// - sm  (6): icon+text gaps, related items within a group
/// - md  (8): standard stack spacing, standard padding
/// - lg  (12): section body spacing, GroupBox internals
/// - xl  (16): between major sections
/// - xxl (24): outer margins, dialog padding
enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24
}
