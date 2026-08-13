import Foundation
import Testing
@testable import SpinLabApp

/// Pure-function coverage for `SelectedHitsLayout` — the derived,
/// non-persisted, non-draggable Selected Hits width policy that replaced
/// the old `workbench.selectedHitsTrayWidth` drag/persistence system.
@Suite("SelectedHitsLayout width policy")
struct SelectedHitsLayoutTests {

    @Test("width is clamped to selectedMin/selectedMax within a spacious primary width")
    func widthClampsToMinMaxWhenSpacious() {
        let narrow = SelectedHitsLayout.width(primaryWidth: 500)
        #expect(narrow >= SelectedHitsLayout.selectedMin)

        let wide = SelectedHitsLayout.width(primaryWidth: 4000)
        #expect(wide <= SelectedHitsLayout.selectedMax)
    }

    @Test("width scales with primary width between the min and max bounds")
    func widthScalesWithPrimaryWidth() {
        let smaller = SelectedHitsLayout.width(primaryWidth: 900)
        let larger = SelectedHitsLayout.width(primaryWidth: 1100)
        #expect(larger >= smaller)
    }

    @Test("Search Results retains its minimum width even when primary is narrow")
    func searchResultsRetainsMinimumWidth() {
        for primaryWidth: CGFloat in [260, 300, 400, 600, 1200] {
            let width = SelectedHitsLayout.width(primaryWidth: primaryWidth)
            let searchResultsWidth = primaryWidth - width - SelectedHitsLayout.separatorWidth
            #expect(searchResultsWidth >= -0.01, "primaryWidth=\(primaryWidth) width=\(width)")
        }
    }

    @Test("narrow layouts never produce a negative width")
    func narrowLayoutsNeverProduceNegativeWidth() {
        for primaryWidth: CGFloat in [0, 1, 50, 100, 200] {
            let width = SelectedHitsLayout.width(primaryWidth: primaryWidth)
            #expect(width >= 0)
            #expect(width.isFinite)
        }
    }
}

/// Source-inspection guard: the old drag/persistence system for Selected
/// Hits must not reappear in `WorkflowWorkspaceLeftColumn`.
@Suite("Selected Hits drag/persistence removal guard")
struct SelectedHitsDragRemovalGuardTests {

    @Test("WorkflowWorkspaceLeftColumn has no tray drag/persistence system")
    func noTrayDragOrPersistence() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceLeftColumn.swift"
        let source = try String(contentsOf: base.appendingPathComponent(path), encoding: .utf8)

        #expect(!source.contains("selectedHitsTrayWidth"))
        #expect(!source.contains("trayWidthBase"))
        #expect(!source.contains("DragGesture"))
        #expect(!source.contains("210...380"))
        #expect(source.contains("SelectedHitsLayout.width(primaryWidth:"))
    }
}
