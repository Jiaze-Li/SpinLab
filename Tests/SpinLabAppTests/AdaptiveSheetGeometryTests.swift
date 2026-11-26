import AppKit
import Observation
import SwiftUI
import Testing
@testable import SpinLabApp

@Observable
@MainActor
private final class SheetFixtureModel {
    var contentHeight: CGFloat
    var text = ""
    init(contentHeight: CGFloat) { self.contentHeight = contentHeight }
}

private struct SheetFixture: View {
    let model: SheetFixtureModel
    let cap: CGFloat?
    /// Same structure as the real delete-confirmation dialog: title, short body, two buttons.
    let isConfirmation: Bool

    var body: some View {
        AdaptiveSheet(minWidth: 480, maxContentHeight: cap) {
            Text("Delete item")
        } content: {
            if isConfirmation {
                Text("This item will be moved to Trash.")
            } else {
                VStack {
                    TextField("", text: Bindable(model).text)
                        .accessibilityIdentifier("AdaptiveSheetFixture.Field")
                    Color.clear.frame(height: model.contentHeight)
                }
            }
        } actions: {
            HStack {
                Button("Cancel") {}
                Spacer()
                Button("Delete") {}
            }
        }
    }
}

@MainActor
private final class SheetHarness {
    let window: NSWindow
    let hosting: NSHostingView<SheetFixture>

    init(model: SheetFixtureModel, cap: CGFloat?, isConfirmation: Bool = false) {
        hosting = NSHostingView(rootView: SheetFixture(model: model, cap: cap, isConfirmation: isConfirmation))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 1600),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 1600)
        settle()
    }

    func settle() {
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        hosting.layoutSubtreeIfNeeded()
    }

    var scrollView: NSScrollView? { Self.findScrollView(in: hosting) }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    /// Distance the middle area could scroll: content taller than the visible clip.
    var scrollableRange: CGFloat {
        guard let scroll = scrollView, let doc = scroll.documentView else { return -1 }
        return max(0, doc.frame.height - scroll.contentSize.height)
    }

    var middleHeight: CGFloat { scrollView?.frame.height ?? -1 }
}

@Suite("AdaptiveSheet geometry", .serialized)
@MainActor
struct AdaptiveSheetGeometryTests {
    private let padding = AppSpacing.xxl * 2

    @Test("Short content: middle area equals content height, nothing to scroll")
    func shortContent() {
        let harness = SheetHarness(model: SheetFixtureModel(contentHeight: 0), cap: nil, isConfirmation: true)
        #expect(harness.scrollView != nil)
        #expect(harness.scrollableRange == 0)
        // One text line plus the dialog padding: well under the lower bound of a long form.
        #expect(harness.middleHeight < AppSpacing.xxl * 10)
        #expect(harness.middleHeight > padding)
    }

    @Test("Dynamic content: grows with expansion, shrinks back, stays one scroll view")
    func dynamicContent() throws {
        let model = SheetFixtureModel(contentHeight: 100)
        let harness = SheetHarness(model: model, cap: nil)
        let scroll = try #require(harness.scrollView)
        let collapsed = harness.middleHeight
        #expect(harness.scrollableRange == 0)

        model.contentHeight = 400
        harness.settle()
        #expect(harness.middleHeight > collapsed + 250)
        #expect(harness.scrollableRange == 0)
        #expect(harness.scrollView === scroll)

        model.contentHeight = 100
        harness.settle()
        #expect(abs(harness.middleHeight - collapsed) < 1)
    }

    @Test("Long content: middle capped, scrolls, header and actions stay visible")
    func longContent() throws {
        let cap: CGFloat = 400
        let model = SheetFixtureModel(contentHeight: 2000)
        let harness = SheetHarness(model: model, cap: cap)
        let scroll = try #require(harness.scrollView)
        #expect(abs(harness.middleHeight - cap) < 1)
        #expect(harness.scrollableRange > 1500)
        // Header and actions are siblings outside the scroll view and inside the window.
        let windowHeight = harness.hosting.bounds.height
        #expect(harness.hosting.fittingSize.height < cap + 200)
        #expect(windowHeight >= harness.hosting.fittingSize.height)
        #expect(harness.scrollView === scroll)
    }

    @Test("Crossing the cap keeps the same scroll view and the typed text")
    func identityAcrossCap() throws {
        let model = SheetFixtureModel(contentHeight: 100)
        let harness = SheetHarness(model: model, cap: 400)
        let scroll = try #require(harness.scrollView)
        model.text = "typed"
        model.contentHeight = 2000
        harness.settle()
        #expect(harness.scrollView === scroll)
        #expect(harness.scrollableRange > 0)
        #expect(model.text == "typed")
        model.contentHeight = 100
        harness.settle()
        #expect(harness.scrollView === scroll)
        #expect(harness.scrollableRange == 0)
    }

    @Test("Screen cap keeps the lower bound on a small screen")
    func screenCap() {
        #expect(AdaptiveSheet<EmptyView, EmptyView, EmptyView>.cappedHeight(screenVisibleHeight: 100) == AppSpacing.xxl * 10)
        #expect(AdaptiveSheet<EmptyView, EmptyView, EmptyView>.cappedHeight(screenVisibleHeight: 1000) == 1000 - AppSpacing.xxl * 8)
    }
}
