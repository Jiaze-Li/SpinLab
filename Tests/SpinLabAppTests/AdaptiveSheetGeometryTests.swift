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
    let area: AdaptiveSheetScreenArea
    /// Same structure as the real delete-confirmation dialog: title, short body, two buttons.
    let isConfirmation: Bool

    var body: some View {
        AdaptiveSheet(minWidth: 480, screenArea: area) {
            Text("Delete item")
        } content: {
            if isConfirmation {
                Text("This item will be moved to Trash.")
            } else {
                VStack {
                    TextField("", text: Bindable(model).text)
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

/// A screen whose visible area is `visibleHeight` tall (bottom at 0, e.g. above a Dock) and a
/// sheet whose top edge is `topInset` below the top of that area, like a sheet hanging from a
/// parent window.
private func area(visibleHeight: CGFloat, topInset: CGFloat = 60) -> AdaptiveSheetScreenArea {
    AdaptiveSheetScreenArea(visibleMinY: 0, visibleMaxY: visibleHeight, windowTopY: visibleHeight - topInset)
}

@MainActor
private final class SheetHarness {
    let window: NSWindow
    let hosting: NSHostingView<SheetFixture>

    init(model: SheetFixtureModel, area: AdaptiveSheetScreenArea, isConfirmation: Bool = false) {
        hosting = NSHostingView(rootView: SheetFixture(model: model, area: area, isConfirmation: isConfirmation))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 3000),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 3000)
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

    /// How far the middle area could scroll: content taller than the visible clip.
    var scrollableRange: CGFloat {
        guard let scroll = scrollView, let doc = scroll.documentView else { return -1 }
        return max(0, doc.frame.height - scroll.contentSize.height)
    }

    var middleHeight: CGFloat { scrollView?.frame.height ?? -1 }
    /// Header + middle + actions: the height the sheet window would take.
    var totalHeight: CGFloat { hosting.fittingSize.height }
    var chromeHeight: CGFloat { totalHeight - middleHeight }
}

@Suite("AdaptiveSheet geometry", .serialized)
@MainActor
struct AdaptiveSheetGeometryTests {
    private let padding = AppSpacing.xxl * 2
    /// Realistic visible heights: small laptop, 13", 14", 27", portrait-ish external.
    private let visibleHeights: [CGFloat] = [560, 700, 860, 1400, 2000]

    // MARK: Pure sizing rules

    @Test("Cap keeps the sheet's bottom inside the visible area for every screen height")
    func capRule() {
        let chrome: CGFloat = 100
        for h in visibleHeights {
            let a = area(visibleHeight: h)
            let cap = AdaptiveSheetLayout.maxMiddleHeight(area: a, chromeHeight: chrome)
            #expect(AdaptiveSheetLayout.fitsScreen(area: a, chromeHeight: chrome, middleHeight: cap), "height \(h)")
            // ...and leaves the margin, not just touching the edge.
            #expect(a.windowTopY - (chrome + cap) >= AdaptiveSheetLayout.bottomMargin - 0.5)
        }
    }

    @Test("A window placed low on the screen gets less room than one at the top")
    func capFollowsWindowTop() {
        let high = AdaptiveSheetLayout.maxMiddleHeight(area: area(visibleHeight: 1000, topInset: 40), chromeHeight: 100)
        let low = AdaptiveSheetLayout.maxMiddleHeight(area: area(visibleHeight: 1000, topInset: 400), chromeHeight: 100)
        #expect(low < high)
        #expect(high - low == 360)
    }

    @Test("Pinned actions stay on screen whenever the chrome itself fits")
    func actionsStayOnScreenOnLowWindows() {
        let chrome: CGFloat = 120
        // Window hanging low on a normal screen: little room, but the buttons must stay visible.
        for inset in stride(from: CGFloat(40), through: 760, by: 60) {
            let a = area(visibleHeight: 900, topInset: inset)
            let cap = AdaptiveSheetLayout.maxMiddleHeight(area: a, chromeHeight: chrome)
            #expect(cap >= 0)
            #expect(AdaptiveSheetLayout.fitsScreen(area: a, chromeHeight: chrome, middleHeight: cap), "inset \(inset)")
            // The first-frame height is also capped.
            #expect(AdaptiveSheetLayout.middleHeight(measured: nil, cap: cap) <= cap)
        }
        // Not even the chrome fits: the middle area collapses to zero and the shortfall is detectable.
        let tiny = area(visibleHeight: 150)
        let tinyCap = AdaptiveSheetLayout.maxMiddleHeight(area: tiny, chromeHeight: chrome)
        #expect(tinyCap == 0)
        #expect(!AdaptiveSheetLayout.fitsScreen(area: tiny, chromeHeight: chrome, middleHeight: tinyCap))
    }

    @Test("The old failure: a tall secondary screen's room is not taken from another screen")
    func roomIsPerScreen() {
        // Main screen 949 tall, sheet on a 969 tall screen hanging from y = 880: only 880 - 111 room.
        let onSecondary = AdaptiveSheetScreenArea(visibleMinY: 111, visibleMaxY: 1080, windowTopY: 880)
        let cap = AdaptiveSheetLayout.maxMiddleHeight(area: onSecondary, chromeHeight: 90)
        #expect(AdaptiveSheetLayout.fitsScreen(area: onSecondary, chromeHeight: 90, middleHeight: cap))
        #expect(cap == 880 - 111 - AdaptiveSheetLayout.bottomMargin - 90)
    }

    @Test("A live window reports the visible area of its own screen")
    func probeUsesWindowScreen() throws {
        let screen = try #require(NSScreen.screens.first)
        let window = NSWindow(contentRect: NSRect(x: screen.frame.minX + 50, y: screen.frame.minY + 50, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false, screen: screen)
        let live = AdaptiveSheetScreenArea.of(window: window)
        #expect(live.visibleMinY == screen.visibleFrame.minY)
        #expect(live.visibleMaxY == screen.visibleFrame.maxY)
        #expect(live.windowTopY == window.frame.maxY)
    }

    // MARK: Rendered layout

    @Test("Short content: middle area equals content height, nothing to scroll, on any screen")
    func shortContent() {
        for h in visibleHeights {
            let harness = SheetHarness(model: SheetFixtureModel(contentHeight: 0), area: area(visibleHeight: h), isConfirmation: true)
            #expect(harness.scrollView != nil)
            #expect(harness.scrollableRange == 0, "height \(h)")
            #expect(harness.middleHeight < AppSpacing.xxl * 10)
            #expect(harness.middleHeight > padding)
            #expect(AdaptiveSheetLayout.fitsScreen(area: area(visibleHeight: h), chromeHeight: harness.chromeHeight, middleHeight: harness.middleHeight))
        }
    }

    @Test("Dynamic content: grows with expansion, shrinks back, stays one scroll view")
    func dynamicContent() throws {
        let model = SheetFixtureModel(contentHeight: 100)
        let harness = SheetHarness(model: model, area: area(visibleHeight: 1400))
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

    @Test("Dynamic content on a small screen: grows until the cap, never past the screen")
    func dynamicContentSmallScreen() throws {
        let a = area(visibleHeight: 560)
        let model = SheetFixtureModel(contentHeight: 100)
        let harness = SheetHarness(model: model, area: a)
        #expect(harness.scrollableRange == 0)
        for expanded in [200, 400, 800, 3000] as [CGFloat] {
            model.contentHeight = expanded
            harness.settle()
            #expect(AdaptiveSheetLayout.fitsScreen(area: a, chromeHeight: harness.chromeHeight, middleHeight: harness.middleHeight),
                    "content \(expanded)")
        }
        #expect(harness.scrollableRange > 0)
        model.contentHeight = 100
        harness.settle()
        #expect(harness.scrollableRange == 0)
    }

    @Test("Long content: capped to the screen, scrolls, actions stay reachable on every screen height")
    func longContent() {
        for h in visibleHeights {
            let a = area(visibleHeight: h)
            let harness = SheetHarness(model: SheetFixtureModel(contentHeight: 5000), area: a)
            let expectedCap = AdaptiveSheetLayout.maxMiddleHeight(area: a, chromeHeight: harness.chromeHeight)
            #expect(abs(harness.middleHeight - expectedCap) < 1, "height \(h)")
            #expect(harness.scrollableRange > 1000, "height \(h)")
            #expect(AdaptiveSheetLayout.fitsScreen(area: a, chromeHeight: harness.chromeHeight, middleHeight: harness.middleHeight),
                    "actions would leave the screen at height \(h)")
        }
    }

    @Test("Crossing the cap keeps the same scroll view and the typed text")
    func identityAcrossCap() throws {
        let model = SheetFixtureModel(contentHeight: 100)
        let harness = SheetHarness(model: model, area: area(visibleHeight: 700))
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

    @Test("Moving the window lower shrinks the middle area")
    func windowPositionMatters() {
        let model = SheetFixtureModel(contentHeight: 5000)
        let high = SheetHarness(model: model, area: area(visibleHeight: 1000, topInset: 40))
        let low = SheetHarness(model: model, area: area(visibleHeight: 1000, topInset: 300))
        #expect(low.middleHeight < high.middleHeight - 200)
    }
}
