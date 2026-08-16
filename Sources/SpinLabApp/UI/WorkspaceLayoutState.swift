import Foundation
import CoreGraphics

/// Effective on-screen widths for the app-wide three-pane workspace
/// (Navigation | Primary | Detail) at a given available width.
struct WorkspacePaneLayout: Equatable {
    var left: CGFloat
    var center: CGFloat
    var right: CGFloat
}

/// Canonical layout constants for the app-wide workspace. Not persisted —
/// these are the min/ideal/max bounds every area shares.
struct WorkspaceLayoutDefaults {
    var leftMin: CGFloat
    var leftIdeal: CGFloat
    var leftMax: CGFloat
    var centerMin: CGFloat
    var rightMin: CGFloat
    var rightIdeal: CGFloat
    var rightMax: CGFloat

    static let standard = WorkspaceLayoutDefaults(
        leftMin: 180, leftIdeal: 220, leftMax: 260,
        centerMin: 420,
        rightMin: 320, rightIdeal: 420, rightMax: 720
    )
}

/// Owns the app-wide three-pane divider-width state contract: exactly two
/// persisted user preferences (`leftPreferredWidth` for Navigation|Primary,
/// `rightPreferredWidth` for Primary|Detail). Center width is always derived,
/// never stored.
///
/// This is the single writer of divider-width persistence for the whole app.
/// Only `commitLeftWidth(_:)`/`commitRightWidth(_:)`, called from a genuine
/// completed divider drag in `AppWorkspaceSplitView`, may change these
/// values — layout observation (window resize, route change, workflow
/// switch, content update) may only read `layout(for:)`, never mutate.
@Observable
final class WorkspaceLayoutState {
    let defaults: WorkspaceLayoutDefaults
    private let store: UserDefaults

    private(set) var leftPreferredWidth: CGFloat
    private(set) var rightPreferredWidth: CGFloat

    static let leftStorageKey = "workspace.leftWidth"
    static let rightStorageKey = "workspace.rightWidth"

    init(defaults: WorkspaceLayoutDefaults = .standard, store: UserDefaults = .standard) {
        self.defaults = defaults
        self.store = store

        if store.object(forKey: Self.leftStorageKey) != nil {
            leftPreferredWidth = CGFloat(store.double(forKey: Self.leftStorageKey))
        } else {
            leftPreferredWidth = defaults.leftIdeal
        }

        if store.object(forKey: Self.rightStorageKey) != nil {
            rightPreferredWidth = CGFloat(store.double(forKey: Self.rightStorageKey))
        } else {
            rightPreferredWidth = defaults.rightIdeal
        }
    }

    /// Persisted mirror of `leftPreferredWidth`, read directly from the store.
    /// Exposed for diagnostics/tests; not used as a live render input.
    var persistedLeftWidth: CGFloat? {
        guard store.object(forKey: Self.leftStorageKey) != nil else { return nil }
        return CGFloat(store.double(forKey: Self.leftStorageKey))
    }

    /// Persisted mirror of `rightPreferredWidth`.
    var persistedRightWidth: CGFloat? {
        guard store.object(forKey: Self.rightStorageKey) != nil else { return nil }
        return CGFloat(store.double(forKey: Self.rightStorageKey))
    }

    /// Pure derived three-pane layout for a given available width. Never
    /// mutates `leftPreferredWidth`/`rightPreferredWidth` — constraint
    /// clamping here does not "burn in" a reduced preference: once
    /// `availableWidth` grows again this returns back toward the unmodified
    /// preferred widths.
    ///
    /// `leftIntent`/`rightIntent` let a caller preview a width other than the
    /// stored preference (e.g. a live divider drag) without mutating
    /// anything — `nil` (the default) means "use the persisted/current
    /// preferred width". This overload is as pure as the base one: it only
    /// ever reads state, never writes it.
    ///
    /// When the window is too narrow to honor both preferred outer widths
    /// plus `centerMin`, outer panes are constrained toward their minima in
    /// proportion to how far each currently sits above its own minimum —
    /// the pane with more slack gives up more first. If even both minima
    /// plus `centerMin` don't fit, panes degrade toward zero, never negative.
    func layout(
        for availableWidth: CGFloat,
        dividerThickness: CGFloat = 0,
        leftIntent: CGFloat? = nil,
        rightIntent: CGFloat? = nil
    ) -> WorkspacePaneLayout {
        let usable = max(availableWidth - 2 * dividerThickness, 0)

        var left = min(max(leftIntent ?? leftPreferredWidth, defaults.leftMin), defaults.leftMax)
        var right = min(max(rightIntent ?? rightPreferredWidth, defaults.rightMin), defaults.rightMax)

        let requiredAtMinima = defaults.leftMin + defaults.centerMin + defaults.rightMin
        guard usable >= requiredAtMinima else {
            // Not enough room even at minima: split what's left evenly between
            // the outer panes, center absorbs the rest (down to zero).
            let outerBudget = max(usable - defaults.centerMin, 0)
            left = outerBudget / 2
            right = outerBudget - left
            let center = max(usable - left - right, 0)
            return WorkspacePaneLayout(left: left, center: center, right: right)
        }

        let availableForOuter = usable - defaults.centerMin
        if left + right > availableForOuter {
            let leftSlack = max(left - defaults.leftMin, 0)
            let rightSlack = max(right - defaults.rightMin, 0)
            let totalSlack = leftSlack + rightSlack
            let overflow = (left + right) - availableForOuter
            if totalSlack > 0 {
                left -= overflow * (leftSlack / totalSlack)
                right -= overflow * (rightSlack / totalSlack)
            } else {
                left = defaults.leftMin
                right = defaults.rightMin
            }
        }

        let center = max(usable - left - right, 0)
        return WorkspacePaneLayout(left: left, center: center, right: right)
    }

    /// The only path allowed to change Navigation|Primary divider intent.
    /// Must only be invoked from a genuine user drag-end signal.
    func commitLeftWidth(_ width: CGFloat) {
        let clamped = min(max(width, defaults.leftMin), defaults.leftMax)
        leftPreferredWidth = clamped
        store.set(Double(clamped), forKey: Self.leftStorageKey)
    }

    /// The only path allowed to change Primary|Detail divider intent.
    /// Must only be invoked from a genuine user drag-end signal.
    func commitRightWidth(_ width: CGFloat) {
        let clamped = min(max(width, defaults.rightMin), defaults.rightMax)
        rightPreferredWidth = clamped
        store.set(Double(clamped), forKey: Self.rightStorageKey)
    }
}
