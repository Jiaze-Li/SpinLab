import SwiftUI

/// App-wide font hierarchy for structural headings.
///
/// All three areas (Inbox, Library, Workbench) share this scale.
/// Body/content fonts (.callout, .body, .caption) remain contextual.
enum AppFontScale {
    /// Top-level area titles (e.g. "Inbox", "Library", section banners).
    static let sectionTitle: Font = .title2.bold()

    /// Collapsible section headers (e.g. "Library Settings", "File").
    static let sectionHeader: Font = .title3.weight(.semibold)

    /// GroupBox labels, subsection headers.
    static let groupHeader: Font = .headline

    // MARK: - Minimum readable size

    /// Minimum font for any visible text: .callout = 12pt on macOS.
    /// Nothing in the UI should use .caption, .caption2, .footnote, or .subheadline
    /// unless it is purely decorative or explicitly exempted.
    static let minimumReadable: Font = .callout
    static let minimumReadableSize: CGFloat = 12
}
