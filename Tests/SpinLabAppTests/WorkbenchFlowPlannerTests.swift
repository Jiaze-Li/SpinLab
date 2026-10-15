import SwiftUI
import Testing
@testable import SpinLabApp

@Suite("Controls flow planner (pure geometry)")
struct WorkbenchFlowPlannerTests {
    private func item(_ ideal: CGFloat, min: CGFloat = 40, fills: Bool = false) -> WorkbenchFlowItem {
        WorkbenchFlowItem(ideal: ideal, minimum: min, fills: fills)
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
}
