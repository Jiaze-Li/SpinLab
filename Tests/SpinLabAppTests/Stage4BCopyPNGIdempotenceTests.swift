import Foundation
import XCTest
@testable import SpinLabApp

// MARK: - Stage 4B: Copy PNG idempotence smoke tests
//
// Guards against accidental state mutation or non-idempotent behavior in the export path.
//
// Background: Stage 2A fixed a reverseSeriesForLegend double-application bug where
// displayPayload was captured post-pipeline, causing the series order to reverse twice
// on Copy PNG. These tests confirm that calling exportPNG twice from the same snapshot
// always produces identical output — catching any future regression.
//
// Uses ThreeOmega stacked series because that workflow had the original idempotence failure
// and has multiple series whose order can be disrupted.

final class Stage4BCopyPNGIdempotenceTests: XCTestCase {

    // MARK: - 1. Calling exportPNG twice from the same snapshot returns identical Data

    func testExportPNGIsIdempotent() throws {
        let displayPayload = try makeStackedDisplayPayload()
        let layout = makeLayout(for: displayPayload)

        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: nil,
            displayPayload: displayPayload,
            layout: layout,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "topRight",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )

        let first  = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        let second = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))

        XCTAssertFalse(first.isEmpty, "First export must produce non-empty PNG")
        XCTAssertEqual(first, second,
            "exportPNG called twice with the same snapshot must return identical Data — " +
            "any difference indicates state mutation or non-idempotent pipeline behavior")
    }

    // MARK: - 2. Idempotence holds at 2x scale

    func testExportPNGIsIdempotentAt2x() throws {
        let displayPayload = try makeStackedDisplayPayload()
        let layout = makeLayout(for: displayPayload)

        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: nil,
            displayPayload: displayPayload,
            layout: layout,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )

        let first  = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 2.0))
        let second = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 2.0))
        XCTAssertEqual(first, second, "2x export must be idempotent")
    }

    // MARK: - 3. Idempotence holds when tabState carries title/axis overrides

    func testExportPNGIsIdempotentWithDisplayOverrides() throws {
        let displayPayload = try makeStackedDisplayPayload()
        let layout = makeLayout(for: displayPayload)

        var tabState = TabRenderState()
        tabState.titleOverride = "My Export Title"
        tabState.xLabelOverride = "Custom X"
        tabState.yLabelOverride = "Custom Y"

        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: nil,
            displayPayload: displayPayload,
            layout: layout,
            tabState: tabState,
            showGrid: true,
            legendAnchor: "topLeft",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )

        let first  = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        let second = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        XCTAssertEqual(first, second,
            "exportPNG with display overrides must still be idempotent")
    }

    // MARK: - 4. Store-level Copy PNG is idempotent (ThreeOmega end-to-end)

    @MainActor
    func testThreeOmegaCopyCurrentPlotPNGIsIdempotent() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let displayPayload = try makeStackedDisplayPayload()
        let layout = makeLayout(for: displayPayload)

        store.tabs.setOutput(
            TabRenderOutput(imageData: nil, layout: layout, manifestPayload: nil, displayPayload: displayPayload),
            for: .fieldSweep1omega
        )
        store.tabs.activeTab = .fieldSweep1omega
        store.ingestionResult = ThreeOmegaIngestionResult(device: "D1")

        let first  = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 1.0))
        let second = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 1.0))

        XCTAssertFalse(first.isEmpty, "First Copy PNG must produce non-empty output")
        XCTAssertEqual(first, second,
            "ThreeOmega copyCurrentPlotPNG called twice with same store state must return identical Data. " +
            "A difference indicates the export path is mutating displayPayload or the pipeline is non-idempotent.")
    }

    // MARK: - Helpers

    private func makeStackedDisplayPayload() throws -> WorkbenchPlotPayload {
        let sweeps = (0..<4).map { i -> ThreeOmegaFieldSweepResult in
            let temperature = Double(100 + i * 50)
            return ThreeOmegaFieldSweepResult(
                temperatureK: temperature,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample-\(i)",
                sourceFilePath: "/tmp/\(i).csv",
                hField: [-1000, 0, 1000],
                r1omega: [temperature, temperature + 1, temperature + 2],
                r3omega: [temperature / 10.0, temperature / 10.0 + 1, temperature / 10.0 + 2],
                iRms: 1e-3,
                rahe1omega: 1.0,
                rahe1omegaWA: 1.0,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 2e-5,
                v3omegaFit: 2e-5
            )
        }
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.0
        let (_, _, displayPayload, _) = renderer.renderR1omega(sweeps: sweeps, device: "0deg")
        return try XCTUnwrap(displayPayload, "renderR1omega must return a non-nil displayPayload for non-empty sweeps")
    }

    private func makeLayout(for payload: WorkbenchPlotPayload) -> WorkbenchPlotLayout {
        WorkbenchPlotLayout.compute(
            options: .init(), payload: payload, legendPoint: nil,
            style: .from(styleParams: [:]), seriesLabelOverrides: [:]
        )
    }
}
