import CoreGraphics

/// Pure responsive width policy for the Selected Hits pane.
///
/// Selected Hits width is derived layout, not state: no persistence, no user
/// preference, no drag state. It is recomputed purely from the current
/// Workbench Primary pane width every time that width changes (e.g. because
/// the app-wide Navigation|Primary or Primary|Detail divider moved, or the
/// window resized) — see `WorkflowWorkspaceLeftColumn`.
enum SelectedHitsLayout {
    static let ratio: CGFloat = 0.34
    static let selectedMin: CGFloat = 240
    static let selectedMax: CGFloat = 360
    static let searchResultsMin: CGFloat = 220
    static let separatorWidth: CGFloat = 1

    /// - Parameter primaryWidth: the current width available to the whole
    ///   Workbench Primary pane (Search Results + separator + Selected Hits).
    static func width(primaryWidth: CGFloat) -> CGFloat {
        let desired = min(max(primaryWidth * ratio, selectedMin), selectedMax)
        let ceiling = max(primaryWidth - searchResultsMin - separatorWidth, 0)
        return max(min(desired, ceiling), 0)
    }
}
