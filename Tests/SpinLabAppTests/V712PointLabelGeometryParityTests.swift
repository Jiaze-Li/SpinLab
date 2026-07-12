import CoreGraphics
import XCTest
@testable import SpinLabApp

final class V712PointLabelGeometryParityTests: XCTestCase {

    private let plotRect = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func assertRect(
        _ actual: CGRect,
        _ expected: CGRect,
        accuracy: CGFloat = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private func assertPoint(
        _ actual: CGPoint,
        _ expected: CGPoint,
        accuracy: CGFloat = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }

    private func makePayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "workflow",
            workflowDisplayName: "Workflow",
            title: "Point Labels",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(
                    label: "Series A",
                    x: [10, 100],
                    y: [10, 100],
                    sourceRef: "/tmp/a.csv",
                    sampleID: "sample-a",
                    renderMode: .scatter,
                    pointLabels: ["target"],
                    lineWidth: 1.5,
                    metadata: [:]
                )
            ],
            styleParams: [:],
            reverseSeriesForLegend: false,
            seriesReorderable: false
        )
    }

    func testNearRightPlacement_flipsLeft() {
        let geometry = WorkbenchPlotLayout.pointLabelGeometry(
            center: CGPoint(x: 90, y: 50),
            plotRect: plotRect
        )

        XCTAssertEqual(geometry.placement, .left)
        assertRect(geometry.pointLabelHitRect, CGRect(x: 32.5, y: 40, width: 50, height: 20))
        assertRect(geometry.pointDotHitRect, CGRect(x: 83, y: 43, width: 14, height: 14))
        assertPoint(geometry.drawAnchor, CGPoint(x: 82.5, y: 50))
    }

    func testNearTopPlacement_flipsBelow() {
        let geometry = WorkbenchPlotLayout.pointLabelGeometry(
            center: CGPoint(x: 20, y: 95),
            plotRect: plotRect
        )

        XCTAssertEqual(geometry.placement, .below)
        assertRect(geometry.pointLabelHitRect, CGRect(x: -5, y: 67.5, width: 50, height: 20))
        assertRect(geometry.pointDotHitRect, CGRect(x: 13, y: 88, width: 14, height: 14))
        assertPoint(geometry.drawAnchor, CGPoint(x: 20, y: 67.5))
    }

    func testNearRightAndNearTopPlacement_prefersLeft() {
        let geometry = WorkbenchPlotLayout.pointLabelGeometry(
            center: CGPoint(x: 90, y: 95),
            plotRect: plotRect
        )

        XCTAssertEqual(geometry.placement, .left)
        assertRect(geometry.pointLabelHitRect, CGRect(x: 32.5, y: 85, width: 50, height: 20))
        assertRect(geometry.pointDotHitRect, CGRect(x: 83, y: 88, width: 14, height: 14))
        assertPoint(geometry.drawAnchor, CGPoint(x: 82.5, y: 95))
    }

    func testNormalPlacement_staysRightSide() {
        let geometry = WorkbenchPlotLayout.pointLabelGeometry(
            center: CGPoint(x: 20, y: 50),
            plotRect: plotRect
        )

        XCTAssertEqual(geometry.placement, .right)
        assertRect(geometry.pointLabelHitRect, CGRect(x: 27.5, y: 40, width: 50, height: 20))
        assertRect(geometry.pointDotHitRect, CGRect(x: 13, y: 43, width: 14, height: 14))
        assertPoint(geometry.drawAnchor, CGPoint(x: 27.5, y: 50))
    }

    func testLayoutHitRectMatchesSharedGeometry() {
        let payload = makePayload()
        let options = WorkbenchChartRenderer.Options(
            width: 100,
            height: 100,
            paddingTop: 10,
            paddingBottom: 10,
            paddingLeft: 10,
            paddingRight: 10
        )
        let layout = WorkbenchPlotLayout.compute(
            options: options,
            payload: payload,
            legendPoint: nil
        )

        guard let hitTarget = layout.pointLabelHitTargets.first else {
            XCTFail("Expected one point-label hit target")
            return
        }
        guard let dotTarget = layout.pointDotHitTargets.first else {
            XCTFail("Expected one point-dot hit target")
            return
        }

        let axisXSpan = layout.axisXMax - layout.axisXMin
        let axisYSpan = layout.axisYMax - layout.axisYMin
        let center = CGPoint(
            x: layout.plotRect.minX + CGFloat((10 - layout.axisXMin) / axisXSpan) * layout.plotRect.width,
            y: layout.plotRect.minY + CGFloat((10 - layout.axisYMin) / axisYSpan) * layout.plotRect.height
        )
        let geometry = WorkbenchPlotLayout.pointLabelGeometry(
            center: center,
            plotRect: layout.plotRect
        )

        XCTAssertEqual(hitTarget.seriesIndex, 0)
        XCTAssertEqual(hitTarget.pointIndex, 0)
        XCTAssertEqual(geometry.placement, .left)
        assertRect(hitTarget.hitRect, geometry.pointLabelHitRect)
        assertRect(dotTarget.hitRect, geometry.pointDotHitRect)
    }
}
