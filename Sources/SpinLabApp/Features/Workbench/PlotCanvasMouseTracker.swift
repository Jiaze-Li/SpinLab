import AppKit
import SwiftUI

/// Transparent NSView overlay that captures left-mouse drag and tap events
/// via AppKit's mouseDown/mouseDragged/mouseUp, bypassing SwiftUI's gesture
/// recognizers which are blocked by NSScrollView on macOS.
struct PlotCanvasMouseTracker: NSViewRepresentable {
    /// When false, hitTest returns nil so all events pass through to views below.
    var isEnabled: Bool = true
    var minimumDragDistance: CGFloat = 4

    var onTap: ((CGPoint) -> Void)?
    /// (startLocation, currentLocation)
    var onDragChanged: ((CGPoint, CGPoint) -> Void)?
    /// (startLocation, finalLocation)
    var onDragEnded: ((CGPoint, CGPoint) -> Void)?

    func makeNSView(context: Context) -> _PlotMouseView { _PlotMouseView() }

    func updateNSView(_ nsView: _PlotMouseView, context: Context) {
        nsView.tracker = self
    }
}

final class _PlotMouseView: NSView {
    var tracker: PlotCanvasMouseTracker?

    private var downLocation: CGPoint?
    private var isDragging = false

    // Top-left origin, y increases downward — matches SwiftUI coordinate space.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard tracker?.isEnabled == true else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        downLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - start.x, current.y - start.y) >= (tracker?.minimumDragDistance ?? 4) else { return }
        isDragging = true
        tracker?.onDragChanged?(start, current)
    }

    override func mouseUp(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        if isDragging {
            tracker?.onDragEnded?(downLocation ?? current, current)
        } else if downLocation != nil {
            tracker?.onTap?(current)
        }
        downLocation = nil
        isDragging = false
    }
}
