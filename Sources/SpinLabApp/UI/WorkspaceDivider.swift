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
            .overlay(ResizeCursorArea())
    }
}

/// Resize cursor over the divider through an AppKit cursor rect. The window owns the
/// cursor rect lifecycle, so there is no push/pop to fall out of balance when the pointer
/// leaves mid-drag, the view disappears, or the window deactivates.
private struct ResizeCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorRectView { ResizeCursorRectView() }
    func updateNSView(_ nsView: ResizeCursorRectView, context: Context) {}
}

/// Transparent to clicks and drags (`hitTest` is nil), so the drag gesture on the divider
/// is unaffected; it only contributes a cursor rect covering its bounds.
final class ResizeCursorRectView: NSView {
    static let cursor: NSCursor = .resizeLeftRight

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: Self.cursor)
    }

    // SwiftUI's hosting view re-asserts the arrow cursor on pointer movement, which a bare
    // cursor rect does not survive. A tracking area for this view's bounds re-applies the
    // resize cursor on every move inside it and restores the arrow on exit. `set()` has no
    // pairing requirement, so nothing can fall out of balance.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) { Self.cursor.set() }
    override func mouseEntered(with event: NSEvent) { Self.cursor.set() }
    override func mouseMoved(with event: NSEvent) { Self.cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}
