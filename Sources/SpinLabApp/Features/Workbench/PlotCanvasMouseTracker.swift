import AppKit
import SwiftUI

/// Transparent NSView overlay that intercepts left-mouse events via a window-level
/// NSEvent local monitor, bypassing SwiftUI's gesture recognizers and the NSScrollView
/// hit-test chain that block DragGesture on macOS.
struct PlotCanvasMouseTracker: NSViewRepresentable {
    /// When false, events pass through untouched.
    var isEnabled: Bool = true
    var minimumDragDistance: CGFloat = 4

    var onTap: ((CGPoint) -> Void)?
    /// (startLocation, currentLocation) — called on every mouseDragged once threshold met
    var onDragChanged: ((CGPoint, CGPoint) -> Void)?
    /// (startLocation, finalLocation)
    var onDragEnded: ((CGPoint, CGPoint) -> Void)?

    func makeNSView(context: Context) -> _PlotMouseView { _PlotMouseView() }
    func updateNSView(_ nsView: _PlotMouseView, context: Context) { nsView.tracker = self }
}

final class _PlotMouseView: NSView {
    var tracker: PlotCanvasMouseTracker? {
        didSet { if !(tracker?.isEnabled ?? false) { _reset() } }
    }

    private var eventMonitor: Any?
    private var downPt: CGPoint?
    private var dragging = false

    // Top-left origin, y increases downward — matches SwiftUI coordinate space.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _removeMonitor()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?._handle(event)
            return event  // always return — observe only, do not consume
        }
    }

    override func removeFromSuperview() {
        _removeMonitor()
        super.removeFromSuperview()
    }

    private func _removeMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func _reset() { downPt = nil; dragging = false }

    private func _handle(_ event: NSEvent) {
        guard tracker?.isEnabled == true else { _reset(); return }
        // Convert window-space event point to this view's local space (isFlipped=true → top-left origin)
        let pt = convert(event.locationInWindow, from: nil)

        switch event.type {
        case .leftMouseDown:
            print("[PlotCanvasMouseTracker] leftMouseDown location=\(NSStringFromPoint(pt)) boundsContains=\(bounds.contains(pt))")
            guard bounds.contains(pt) else { _reset(); return }
            downPt = pt
            dragging = false
            print("[PlotCanvasMouseTracker] mouseDown storedStart=\(String(describing: downPt)) dragging=\(dragging)")

        case .leftMouseDragged:
            print("[PlotCanvasMouseTracker] leftMouseDragged location=\(NSStringFromPoint(pt)) start=\(String(describing: downPt))")
            guard let start = downPt else { return }
            let dist = hypot(pt.x - start.x, pt.y - start.y)
            let threshold = tracker?.minimumDragDistance ?? 4
            print("[PlotCanvasMouseTracker] drag-distance start=\(NSStringFromPoint(start)) current=\(NSStringFromPoint(pt)) distance=\(dist) threshold=\(threshold) thresholdPassed=\(dist >= threshold)")
            guard dist >= threshold else { return }
            dragging = true
            print("[PlotCanvasMouseTracker] onDragChangedCallbackCalled=true")
            tracker?.onDragChanged?(start, pt)

        case .leftMouseUp:
            print("[PlotCanvasMouseTracker] leftMouseUp location=\(NSStringFromPoint(pt)) start=\(String(describing: downPt)) dragging=\(dragging)")
            guard let start = downPt else { return }
            if dragging {
                print("[PlotCanvasMouseTracker] onDragEndedCallbackCalled=true")
                tracker?.onDragEnded?(start, pt)
            } else {
                tracker?.onTap?(pt)
            }
            _reset()
            print("[PlotCanvasMouseTracker] mouseUp reset start=\(String(describing: downPt)) dragging=\(dragging)")

        default: break
        }
    }
}
