import SwiftUI
import Testing
@testable import SpinLabApp

@Suite("Controls flow planner (pure geometry)")
struct WorkbenchFlowPlannerTests {
    private func item(_ ideal: CGFloat, min: CGFloat = 40, fills: Bool = false) -> WorkbenchFlowItem {
        WorkbenchFlowItem(ideal: ideal, minimum: min, fills: fills)
    }

    @Test("Non-finite proposals use intrinsic width instead of giving flexible fields infinite width")
    func nonFiniteAvailableWidth() {
        let items = [WorkbenchFlowItem(ideal: 100, minimum: 40, fills: true), item(80)]
        let expected = WorkbenchFlowPlanner.plan(items: items, available: 192, spacing: 12)
        for offered in [CGFloat.infinity, -CGFloat.infinity, CGFloat.nan] {
            let actual = WorkbenchFlowPlanner.plan(items: items, available: offered, spacing: 12)
            #expect(actual == expected, "non-finite width must fall back to intrinsic width")
            #expect(actual.allSatisfy { $0.x.isFinite && $0.width.isFinite && $0.width >= 0 })
        }
    }

    @Test("Groups stay on one line when the offered width is enough")
    func compactWhenWide() {
        let plan = WorkbenchFlowPlanner.plan(items: [item(100), item(100), item(100)], available: 720, spacing: 12)
        #expect(plan.map(\.line) == [0, 0, 0])
        #expect(plan.map(\.x) == [0, 112, 224])
    }

    @Test("Whole groups wrap when the width is not enough")
    func wrapsWholeGroups() {
        let plan = WorkbenchFlowPlanner.plan(items: [item(140), item(140), item(140)], available: 300, spacing: 12)
        #expect(plan.map(\.line) == [0, 0, 1])
    }

    @Test("A group wider than the line is capped to the line, never overflowing")
    func capsToLine() {
        let plan = WorkbenchFlowPlanner.plan(items: [item(500, min: 120)], available: 300, spacing: 12)
        #expect(plan[0].width == 300)
        #expect(plan[0].clipped == false)
    }

    @Test("Clipping is reported when the line cannot hold the minimum")
    func reportsClipping() {
        let plan = WorkbenchFlowPlanner.plan(items: [item(500, min: 400)], available: 300, spacing: 12)
        #expect(plan[0].clipped)
    }

    @Test("Fill items absorb leftover width on their own line only")
    func fillAbsorbsLeftover() {
        let plan = WorkbenchFlowPlanner.plan(items: [item(100), item(100, fills: true), item(250)], available: 400, spacing: 12)
        #expect(plan[1].width > 100)
        #expect(plan[0].x + plan[0].width + 12 <= plan[1].x + 0.001)
        #expect(plan[1].x + plan[1].width <= 400.001)
        #expect(plan[2].line == 1 && plan[2].width == 250)
    }

    @Test("Row count is monotone non-increasing as width grows (no oscillation)")
    func monotoneRowCount() {
        let items = [item(140), item(120), item(180), item(90), item(200)]
        var previous = Int.max
        for width in stride(from: 200 as CGFloat, through: 900, by: 10) {
            let lines = (WorkbenchFlowPlanner.plan(items: items, available: width, spacing: 12).map(\.line).max() ?? 0)
            #expect(lines <= previous)
            previous = lines
        }
    }

    @Test("Labels sit beside inputs only while the input keeps a comfortable width")
    func labelPlacement() {
        #expect(WorkbenchFlowPlanner.labelBeside(labelWidth: 60, gap: 6, contentIdeal: 200, available: 300))
        #expect(!WorkbenchFlowPlanner.labelBeside(labelWidth: 120, gap: 6, contentIdeal: 200, available: 200))
        #expect(WorkbenchFlowPlanner.labelBeside(labelWidth: 60, gap: 6, contentIdeal: 40, available: 120))
    }

    // MARK: Flexible growth & justify

    @Test("A flexible item grows only up to its cap; the rest stays unused when not justified")
    func growthIsBounded() {
        let items = [WorkbenchFlowItem(ideal: 100, minimum: 40, fills: true, maxGrowth: 30), item(100)]
        let plan = WorkbenchFlowPlanner.plan(items: items, available: 600, spacing: 12)
        #expect(plan[0].width == 130)
        #expect(plan[1].x == 142 && plan[1].width == 100)
    }

    @Test("Leftover is shared evenly among flexible items, capped ones release their share")
    func growthWaterFills() {
        let items = [WorkbenchFlowItem(ideal: 100, minimum: 40, fills: true, maxGrowth: 10),
                     WorkbenchFlowItem(ideal: 100, minimum: 40, fills: true, maxGrowth: 200)]
        let plan = WorkbenchFlowPlanner.plan(items: items, available: 400, spacing: 12)
        #expect(plan[0].width == 110)
        #expect(abs(plan[1].width - (400 - 12 - 110)) < 0.01)
    }

    @Test("Justify spreads leftover over gaps, each gap bounded; flexible items grow first")
    func justifySpreadsBounded() {
        let items = [item(100), item(100), item(100)]
        let tight = WorkbenchFlowPlanner.plan(items: items, available: 400, spacing: 12, distribution: .justified(maxExtraGap: 100))
        #expect(abs(tight[1].x - (100 + 12 + 38)) < 0.01 && abs(tight[2].x + tight[2].width - 400) < 0.01)
        let bounded = WorkbenchFlowPlanner.plan(items: items, available: 700, spacing: 12, distribution: .justified(maxExtraGap: 20))
        #expect(abs(bounded[1].x - bounded[0].width - 32) < 0.01, "gap is spacing + max extra, never more")
        let flexible = WorkbenchFlowPlanner.plan(items: [WorkbenchFlowItem(ideal: 100, minimum: 40, fills: true, maxGrowth: 50), item(100)],
                                                 available: 400, spacing: 12, distribution: .justified(maxExtraGap: 200))
        #expect(flexible[0].width == 150, "the flexible item reached its cap before any gap grew")
        #expect(abs(flexible[1].x + flexible[1].width - 400) < 0.01)
    }

    @Test("Justify leaves one-item lines and the last line of a wrapped flow leading; never overflows")
    func justifyEdges() {
        let single = WorkbenchFlowPlanner.plan(items: [item(100)], available: 500, spacing: 12, distribution: .justified(maxExtraGap: 50))
        #expect(single[0].x == 0 && single[0].width == 100)
        let wrapped = WorkbenchFlowPlanner.plan(items: [item(200), item(200), item(100), item(100)], available: 500, spacing: 12,
                                                distribution: .justified(maxExtraGap: 50))
        #expect(wrapped.map(\.line) == [0, 0, 1, 1])
        #expect(wrapped[3].x == 112, "last line stays leading")
        for placement in wrapped { #expect(placement.x + placement.width <= 500.001) }
    }

    @Test("Justify keeps row count monotone and never changes wrapping")
    func justifyKeepsWrapping() {
        let items = [item(140), item(120), item(180), item(90), item(200)]
        for width in stride(from: 200 as CGFloat, through: 900, by: 10) {
            let leading = WorkbenchFlowPlanner.plan(items: items, available: width, spacing: 12)
            let justified = WorkbenchFlowPlanner.plan(items: items, available: width, spacing: 12, distribution: .justified(maxExtraGap: 36))
            #expect(leading.map(\.line) == justified.map(\.line))
            #expect(justified.allSatisfy { $0.x + $0.width <= width + 0.001 })
        }
    }
}
