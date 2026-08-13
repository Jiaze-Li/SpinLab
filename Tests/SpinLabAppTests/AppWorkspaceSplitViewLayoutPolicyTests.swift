import Foundation
import SwiftUI
import AppKit
import Testing
@testable import SpinLabApp

/// Behavioral regression guards for `AppWorkspaceSplitView`'s layout policy
/// (the owned three-pane `NSSplitView` primitive backing the single app-wide
/// workspace shell). See
/// `docs/architecture/workbench/WORKBENCH_LAYOUT_OWNERSHIP_AUDIT.md`.
///
/// `NSViewRepresentable.Context` has no public initializer, so these drive
/// `AppWorkspaceSplitView.Coordinator` directly against a manually assembled
/// `AppOwnedWorkspaceSplitView` + three `NSHostingView`s, exercising the same
/// delegate entry points SwiftUI would call at runtime.
///
/// User-resize commits are exercised via
/// `AppOwnedWorkspaceSplitView.handleMouseDownResult` directly rather than a
/// real `mouseDown(with:)` call: AppKit's own divider drag tracking loop
/// (inside `super.mouseDown`) blocks on real mouse events and can't be
/// driven synthetically in a unit test.
@Suite("AppWorkspaceSplitView layout policy")
@MainActor
struct AppWorkspaceSplitViewLayoutPolicyTests {

    private static let testDefaults = WorkspaceLayoutDefaults(
        leftMin: 180, leftIdeal: 220, leftMax: 260,
        centerMin: 400,
        rightMin: 300, rightIdeal: 400, rightMax: 700
    )

    private func makeStore() -> UserDefaults {
        UserDefaults(suiteName: "AppWorkspaceSplitViewLayoutPolicyTests.\(UUID().uuidString)")!
    }

    private struct Fixture {
        let splitView: AppOwnedWorkspaceSplitView
        let navHost: NSHostingView<Text>
        let primaryHost: NSHostingView<Text>
        let detailHost: NSHostingView<Text>
        let coordinator: AppWorkspaceSplitView<Text, Text, Text>.Coordinator
    }

    private func makeFixture(state: WorkspaceLayoutState, containerWidth: CGFloat) -> Fixture {
        let splitView = AppOwnedWorkspaceSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        let navHost = NSHostingView(rootView: Text("N"))
        let primaryHost = NSHostingView(rootView: Text("P"))
        let detailHost = NSHostingView(rootView: Text("D"))
        splitView.addArrangedSubview(navHost)
        splitView.addArrangedSubview(primaryHost)
        splitView.addArrangedSubview(detailHost)

        let coordinator = AppWorkspaceSplitView<Text, Text, Text>.Coordinator()
        coordinator.splitView = splitView
        coordinator.navHost = navHost
        coordinator.primaryHost = primaryHost
        coordinator.detailHost = detailHost
        coordinator.layoutState = state
        splitView.delegate = coordinator
        splitView.onUserDividerResizeEnded = { [weak state] dividerIndex, finalWidth in
            if dividerIndex == 0 {
                state?.commitLeftWidth(finalWidth)
            } else {
                state?.commitRightWidth(finalWidth)
            }
        }

        splitView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: 500)

        return Fixture(splitView: splitView, navHost: navHost, primaryHost: primaryHost, detailHost: detailHost, coordinator: coordinator)
    }

    /// AppKit's own constraint-driven adjustment can snap the applied frame a
    /// point or two off pure math — tolerate that native rounding.
    private let nativeSnapTolerance: CGFloat = 2.0

    @Test("wide container applies both preferred widths verbatim")
    func wideContainerAppliesPreferredWidths() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        state.commitLeftWidth(230)
        state.commitRightWidth(420)
        let fixture = makeFixture(state: state, containerWidth: 1600)

        #expect(abs(fixture.navHost.frame.width - 230) <= nativeSnapTolerance)
        #expect(abs(fixture.detailHost.frame.width - 420) <= nativeSnapTolerance)
    }

    @Test("container shrink constrains effective layout then regrow restores it, preferences untouched")
    func shrinkThenGrowPreservesPreferences() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        state.commitLeftWidth(260)
        state.commitRightWidth(700)
        let fixture = makeFixture(state: state, containerWidth: 2000)

        fixture.splitView.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        #expect(fixture.navHost.frame.width < 260)
        #expect(fixture.detailHost.frame.width < 700)
        #expect(state.leftPreferredWidth == 260)
        #expect(state.rightPreferredWidth == 700)

        fixture.splitView.frame = NSRect(x: 0, y: 0, width: 2000, height: 500)
        #expect(abs(fixture.navHost.frame.width - 260) <= nativeSnapTolerance)
        #expect(abs(fixture.detailHost.frame.width - 700) <= nativeSnapTolerance)
        #expect(state.leftPreferredWidth == 260)
        #expect(state.rightPreferredWidth == 700)
    }

    @Test("window resize does not commit either preference")
    func windowResizeDoesNotCommitPreferences() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        state.commitLeftWidth(230)
        state.commitRightWidth(420)
        let fixture = makeFixture(state: state, containerWidth: 1400)

        fixture.splitView.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        fixture.splitView.frame = NSRect(x: 0, y: 0, width: 1400, height: 500)

        #expect(state.leftPreferredWidth == 230)
        #expect(state.persistedLeftWidth == 230)
        #expect(state.rightPreferredWidth == 420)
        #expect(state.persistedRightWidth == 420)
    }

    @Test("policy-driven initial layout does not commit either preference")
    func policyDrivenInitialLayoutDoesNotCommit() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        state.commitLeftWidth(230)
        state.commitRightWidth(420)
        _ = makeFixture(state: state, containerWidth: 1400)

        #expect(state.persistedLeftWidth == 230)
        #expect(state.persistedRightWidth == 420)
    }

    @Test("left divider drag commits only the left preference")
    func leftDragCommitsLeftOnly() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        let fixture = makeFixture(state: state, containerWidth: 1400)
        let navBefore = fixture.navHost.frame.width
        let detailBefore = fixture.detailHost.frame.width

        fixture.navHost.frame = NSRect(x: 0, y: 0, width: 250, height: 500)
        fixture.splitView.handleMouseDownResult(leftBefore: navBefore, leftAfter: 250, rightBefore: detailBefore, rightAfter: detailBefore)

        #expect(state.leftPreferredWidth == 250)
        #expect(state.persistedLeftWidth == 250)
        #expect(state.persistedRightWidth == nil)
    }

    @Test("right divider drag commits only the right preference")
    func rightDragCommitsRightOnly() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        let fixture = makeFixture(state: state, containerWidth: 1400)
        let navBefore = fixture.navHost.frame.width
        let detailBefore = fixture.detailHost.frame.width

        fixture.detailHost.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        fixture.splitView.handleMouseDownResult(leftBefore: navBefore, leftAfter: navBefore, rightBefore: detailBefore, rightAfter: 500)

        #expect(state.rightPreferredWidth == 500)
        #expect(state.persistedRightWidth == 500)
        #expect(state.persistedLeftWidth == nil)
    }

    @Test("click without divider movement commits nothing")
    func clickWithoutMovementCommitsNothing() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        state.commitLeftWidth(230)
        state.commitRightWidth(420)
        let fixture = makeFixture(state: state, containerWidth: 1400)

        let navWidth = fixture.navHost.frame.width
        let detailWidth = fixture.detailHost.frame.width
        fixture.splitView.handleMouseDownResult(leftBefore: navWidth, leftAfter: navWidth, rightBefore: detailWidth, rightAfter: detailWidth)

        #expect(state.leftPreferredWidth == 230)
        #expect(state.rightPreferredWidth == 420)
    }

    @Test("hosted content update alone does not change layout state")
    func contentUpdateAloneDoesNotChangeState() {
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: makeStore())
        state.commitLeftWidth(230)
        state.commitRightWidth(420)
        let fixture = makeFixture(state: state, containerWidth: 1400)

        fixture.navHost.rootView = Text("Different route")
        fixture.primaryHost.rootView = Text("Different workflow")
        fixture.detailHost.rootView = Text("Different workflow")

        #expect(state.leftPreferredWidth == 230)
        #expect(state.rightPreferredWidth == 420)
    }
}
