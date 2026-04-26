import Foundation
import XCTest
@testable import SpinLabApp

final class V535ScopeGateTests: XCTestCase {

    func testNoPointLabelsYieldsEmptyHitTargets() {
        let payload = makePayload(series: [
            WorkbenchPlotSeries(label: "A", x: [0, 1], y: [1, 2], pointLabels: []),
            WorkbenchPlotSeries(label: "B", x: [0, 1], y: [2, 3], pointLabels: [])
        ])

        let layout = WorkbenchPlotLayout.compute(options: .init(), payload: payload, legendPoint: nil)
        XCTAssertTrue(layout.pointDotHitTargets.isEmpty)
    }

    func testHasPointLabelsYieldsHitTargets() {
        let payload = makePayload(series: [
            WorkbenchPlotSeries(label: "A", x: [0, 1], y: [1, 2], pointLabels: ["p0", "p1"]),
            WorkbenchPlotSeries(label: "B", x: [0, 1], y: [2, 3], pointLabels: [])
        ])

        let layout = WorkbenchPlotLayout.compute(options: .init(), payload: payload, legendPoint: nil)
        XCTAssertFalse(layout.pointDotHitTargets.isEmpty)
    }

    func testHitTargetCountMatchesPoints() {
        let payload = makePayload(series: [
            WorkbenchPlotSeries(label: "A", x: [0, 1, 2], y: [1, 2, 3], pointLabels: ["a", "b", "c"]),
            WorkbenchPlotSeries(label: "B", x: [0, 1], y: [2, 1], pointLabels: []),
            WorkbenchPlotSeries(label: "C", x: [0, 1], y: [4, 5], pointLabels: ["x", "y"])
        ])

        let layout = WorkbenchPlotLayout.compute(options: .init(), payload: payload, legendPoint: nil)
        XCTAssertEqual(layout.pointDotHitTargets.count, 5)
    }

    private func makePayload(series: [WorkbenchPlotSeries]) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Scope Gate",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: series
        )
    }
}
