import Foundation
import XCTest
@testable import SpinLabApp

// MARK: - Copy PNG direct-copy architecture guards
//
// Copy PNG no longer re-renders. WorkbenchPlotCanvas's context menu copies the
// imageData already on screen; live render is the single source of truth and
// always renders at WorkbenchPlotRenderScale.display.

final class WorkbenchCopyPNGDirectCopyTests: XCTestCase {

    // MARK: - Canvas Copy PNG context menu only copies current imageData

    func testCopyPNGContextMenuHasNoExportCallback() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Canvas/WorkbenchPlotCanvas.swift"
        )
        let src = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(src.contains("onCopyPNG"), "Canvas must not declare an onCopyPNG export callback")
        XCTAssertFalse(src.contains("copyPNGScales"), "Canvas must not declare per-scale Copy PNG options")
        XCTAssertTrue(src.contains("Button(\"Copy PNG\")"), "Canvas must expose a single Copy PNG button")
        XCTAssertTrue(
            src.contains("pb.setData(imageData, forType: .png)"),
            "Copy PNG must copy the currently displayed imageData directly, with no re-render"
        )
    }

    // MARK: - Live render input defaults to WorkbenchPlotRenderScale.display (3x)

    @MainActor
    func testTabRenderManagerBuildPipelineInputDefaultsToDisplayScale() {
        enum TestTab: Hashable, Sendable { case first }
        let manager = TabRenderManager<TestTab>(defaultTab: .first)

        let series = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1])
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Scale Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [series]
        )

        let input = manager.buildPipelineInput(payload: payload, for: .first)

        XCTAssertEqual(input.pixelScaleOverride, WorkbenchPlotRenderScale.display)
        XCTAssertEqual(WorkbenchPlotRenderScale.display, 3)
    }
}
