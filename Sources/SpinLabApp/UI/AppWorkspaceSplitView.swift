import SwiftUI
import AppKit

/// Owned native rendering for the single app-wide three-pane workspace
/// (Navigation | Primary | Detail).
///
/// Creates and keeps one `NSSplitView` alive for the lifetime of this
/// `View` identity — the identity that must survive Inbox ↔ Library ↔
/// Workbench route changes and Workbench workflow switches.
/// `updateNSView` only swaps the three hosted panes' `rootView` — it never
/// tears down and recreates the split view, so both dividers' native
/// identity (and therefore their rendered widths) survive content swaps.
///
/// Width is single-directional: `WorkspaceLayoutState` is the intent
/// authority (user preference + persistence + legal effective layout); this
/// view is the rendering authority (actual on-screen divider positions).
/// The only path that reads native width back into `WorkspaceLayoutState`
/// is `AppOwnedWorkspaceSplitView.onUserDividerResizeEnded`, which fires
/// from a real AppKit divider mouse-down/drag/mouse-up sequence — never
/// from a resize notification.
struct AppWorkspaceSplitView<Navigation: View, Primary: View, Detail: View>: NSViewRepresentable {
    let layoutState: WorkspaceLayoutState
    let navigation: Navigation
    let primary: Primary
    let detail: Detail

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = AppOwnedWorkspaceSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.identifier = NSUserInterfaceItemIdentifier("AppWorkspaceSplitView")

        let navHost = NSHostingView(rootView: navigation)
        let primaryHost = NSHostingView(rootView: primary)
        let detailHost = NSHostingView(rootView: detail)
        navHost.identifier = NSUserInterfaceItemIdentifier("AppWorkspaceSplitView.navigationHost")
        primaryHost.identifier = NSUserInterfaceItemIdentifier("AppWorkspaceSplitView.primaryHost")
        detailHost.identifier = NSUserInterfaceItemIdentifier("AppWorkspaceSplitView.detailHost")

        splitView.addArrangedSubview(navHost)
        splitView.addArrangedSubview(primaryHost)
        splitView.addArrangedSubview(detailHost)
        splitView.delegate = context.coordinator

        context.coordinator.splitView = splitView
        context.coordinator.navHost = navHost
        context.coordinator.primaryHost = primaryHost
        context.coordinator.detailHost = detailHost
        context.coordinator.layoutState = layoutState

        let coordinator = context.coordinator
        splitView.onUserDividerResizeEnded = { dividerIndex, finalWidth in
            if dividerIndex == 0 {
                coordinator.layoutState?.commitLeftWidth(finalWidth)
            } else {
                coordinator.layoutState?.commitRightWidth(finalWidth)
            }
        }

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        context.coordinator.navHost?.rootView = navigation
        context.coordinator.primaryHost?.rootView = primary
        context.coordinator.detailHost?.rootView = detail
        context.coordinator.layoutState = layoutState
        context.coordinator.applyInitialLayoutIfNeeded()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        weak var splitView: NSSplitView?
        weak var navHost: NSHostingView<Navigation>?
        weak var primaryHost: NSHostingView<Primary>?
        weak var detailHost: NSHostingView<Detail>?
        var layoutState: WorkspaceLayoutState?

        private var hasAppliedInitialLayout = false

        /// One-time fallback in case the split view's first legal bounds
        /// don't arrive via `resizeSubviews(withOldSize:)`. Not a retry
        /// loop — runs at most once per `Coordinator` lifetime.
        func applyInitialLayoutIfNeeded() {
            guard !hasAppliedInitialLayout, let splitView, splitView.bounds.width > 0 else { return }
            applyLayout(containerWidth: splitView.bounds.width)
        }

        private func applyLayout(containerWidth: CGFloat) {
            guard let splitView, let layoutState, let navHost, let primaryHost, let detailHost else { return }
            let dividerThickness = splitView.dividerThickness
            let paneLayout = layoutState.layout(for: containerWidth, dividerThickness: dividerThickness)
            let height = splitView.bounds.height

            var x: CGFloat = 0
            navHost.frame = NSRect(x: x, y: 0, width: paneLayout.left, height: height)
            x += paneLayout.left + dividerThickness
            primaryHost.frame = NSRect(x: x, y: 0, width: paneLayout.center, height: height)
            x += paneLayout.center + dividerThickness
            detailHost.frame = NSRect(x: x, y: 0, width: paneLayout.right, height: height)

            hasAppliedInitialLayout = true
        }

        // MARK: NSSplitViewDelegate

        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            applyLayout(containerWidth: splitView.bounds.width)
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard let layoutState else { return proposedMinimumPosition }
            let d = layoutState.defaults
            switch dividerIndex {
            case 0:
                return d.leftMin
            default:
                let dividerThickness = splitView.dividerThickness
                let navWidth = navHost?.frame.width ?? d.leftMin
                let minByCenterMin = navWidth + dividerThickness + d.centerMin
                let minByRightMax = splitView.bounds.width - dividerThickness - d.rightMax
                return max(minByCenterMin, minByRightMax)
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard let layoutState else { return proposedMaximumPosition }
            let d = layoutState.defaults
            let dividerThickness = splitView.dividerThickness
            switch dividerIndex {
            case 0:
                let maxByLeftMax = d.leftMax
                let maxByAvailable = splitView.bounds.width - 2 * dividerThickness - d.centerMin - d.rightMin
                return min(maxByLeftMax, max(maxByAvailable, d.leftMin))
            default:
                return splitView.bounds.width - dividerThickness - d.rightMin
            }
        }
    }
}

/// Owned `NSSplitView` subclass — the only source of the "did the user
/// actually move a divider, and which one" signal. `mouseDown(with:)` on an
/// `NSSplitView` is only ever the entry point for a divider drag: AppKit
/// runs its own synchronous event-tracking loop inside `super.mouseDown`,
/// which returns once the drag (or a no-op click) completes. Comparing the
/// Navigation and Detail panes' widths before and after that call answers
/// "did the user move divider 0 or divider 1", not "where did this resize
/// come from" — window resize, route changes, and any other programmatic
/// frame assignment never call into this method at all, so they need no
/// classification here. A drag can only ever move one divider at a time
/// (AppKit resolves which divider the mouseDown landed on internally), so
/// exactly one of the two panes changes per interaction.
final class AppOwnedWorkspaceSplitView: NSSplitView {
    var onUserDividerResizeEnded: ((Int, CGFloat) -> Void)?

    /// Guards against floating-point noise in the before/after comparison,
    /// not against misclassifying the resize's origin — origin is already
    /// established by being inside `mouseDown`.
    private static let widthChangeEpsilon: CGFloat = 0.5

    override func mouseDown(with event: NSEvent) {
        let leftBefore = subviews.first?.frame.width ?? .nan
        let rightBefore = subviews.count > 2 ? subviews[2].frame.width : .nan

        super.mouseDown(with: event)

        let leftAfter = subviews.first?.frame.width ?? .nan
        let rightAfter = subviews.count > 2 ? subviews[2].frame.width : .nan
        handleMouseDownResult(leftBefore: leftBefore, leftAfter: leftAfter, rightBefore: rightBefore, rightAfter: rightAfter)
    }

    /// The width-comparison decision `mouseDown` applies once AppKit's own
    /// divider-drag tracking loop has returned. Split out so tests can drive
    /// it directly — AppKit's tracking loop blocks on real mouse events and
    /// can't be driven synthetically in a unit test.
    func handleMouseDownResult(leftBefore: CGFloat, leftAfter: CGFloat, rightBefore: CGFloat, rightAfter: CGFloat) {
        let leftChanged = leftAfter.isFinite && abs(leftAfter - leftBefore) > Self.widthChangeEpsilon
        let rightChanged = rightAfter.isFinite && abs(rightAfter - rightBefore) > Self.widthChangeEpsilon

        if leftChanged {
            onUserDividerResizeEnded?(0, leftAfter)
        } else if rightChanged {
            onUserDividerResizeEnded?(1, rightAfter)
        }
    }
}
