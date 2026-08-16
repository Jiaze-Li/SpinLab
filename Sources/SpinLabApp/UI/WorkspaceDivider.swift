import SwiftUI
import AppKit

/// One visible divider line between two app-wide workspace panes, with a
/// comfortably sized horizontal hit target and native-looking resize cursor.
/// Purely a rendering surface — it owns no width or gesture state; the
/// caller (`AppWorkspaceShell`) attaches its own drag gesture via
/// `.gesture(...)` so it can route live translation into `@GestureState`.
struct WorkspaceDivider: View {
    /// The full width this divider occupies in its parent `HStack`. Callers
    /// computing pane layout must pass this same value as
    /// `WorkspaceLayoutState.layout(for:dividerThickness:...)`'s
    /// `dividerThickness`, or rendered panes and computed panes will drift.
    static let thickness: CGFloat = 9

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: Self.thickness)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
