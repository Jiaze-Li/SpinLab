import Foundation
import Testing
@testable import SpinLabApp

@Suite("Heatmap Gwyddion Palette and Layout Extensions")
struct HeatmapGwyddionPaletteAndLayoutTests {

    @Test("Approved Gwyddion palette SHA-256 matches exact hash and has 256 stops starting black and ending white")
    func approvedGwyddionPaletteVerification() {
        #expect(HeatmapColorScale.approvedGwyddionPaletteSHA256 == "e146daecdcef85a77006ffe1f0008b2dbdb74f6db62bd7e41b9baec61aada04f")
        let stops = HeatmapColorScale.gwyddionStops
        #expect(stops.count == 256)
        
        let first = stops.first!
        #expect(first.r == 0.0 && first.g == 0.0 && first.b == 0.0)
        
        let last = stops.last!
        #expect(last.r == 1.0 && last.g == 1.0 && last.b == 1.0)
    }

    @Test("HeatmapColorScale resolves gwyddion colormap key")
    func heatmapColorScaleResolvesGwyddion() {
        let scale = HeatmapColorScale(zMin: 0, zMax: 100, mode: .linear, colormapKey: "gwyddion")
        #expect(scale.colormap == .gwyddion)
        
        let c0 = scale.color(for: 0)
        #expect(c0.components?[0] == 0 && c0.components?[1] == 0 && c0.components?[2] == 0)
        
        let c1 = scale.color(for: 100)
        #expect(c1.components?[0] == 1 && c1.components?[1] == 1 && c1.components?[2] == 1)
    }

    @Test("Colorbar endpointsOnly formatting produces unicode minus and 2 decimals")
    func endpointsFormattingProducesExpectedLabels() {
        let entries = HeatmapPlotLayout.makeEndpointsColorbarTickEntries(zMin: -0.284, zMax: 0.192, decimals: 2)
        #expect(entries.count == 2)
        #expect(entries[0].normalizedY == 0.0)
        #expect(entries[0].label == "−0.28")
        #expect(entries[1].normalizedY == 1.0)
        #expect(entries[1].label == "0.19")
    }

    @Test("HeatmapPlotLayout with hideSpatialAxes omits spatial tick entries")
    func hideSpatialAxesOmitsTicks() {
        let grid = HeatmapGrid(
            xValues: [0, 1, 2],
            yValues: [0, 1, 2],
            zMatrix: [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        )
        let payloadNormal = HeatmapPlotPayload(
            workflowID: "test",
            title: "Test",
            xLabel: "X",
            yLabel: "Y",
            zLabel: "Z",
            grid: grid,
            hideSpatialAxes: false
        )
        let layoutNormal = HeatmapPlotLayout.compute(payload: payloadNormal)
        #expect(!layoutNormal.hideSpatialAxes)
        #expect(!layoutNormal.xTickEntries.isEmpty)
        #expect(!layoutNormal.yTickEntries.isEmpty)

        let payloadHidden = HeatmapPlotPayload(
            workflowID: "test",
            title: "Test",
            xLabel: "X",
            yLabel: "Y",
            zLabel: "Z",
            grid: grid,
            hideSpatialAxes: true
        )
        let layoutHidden = HeatmapPlotLayout.compute(payload: payloadHidden)
        #expect(layoutHidden.hideSpatialAxes)
        #expect(layoutHidden.xTickEntries.isEmpty)
        #expect(layoutHidden.yTickEntries.isEmpty)
    }

    @Test("HeatmapPlotLayout with endpointsOnly shifts colorbar rightward")
    func endpointsOnlyShiftsColorbarRightward() {
        let grid = HeatmapGrid(
            xValues: [0, 1, 2],
            yValues: [0, 1, 2],
            zMatrix: [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        )
        let payload = HeatmapPlotPayload(
            workflowID: "test",
            title: "Test",
            xLabel: "X",
            yLabel: "Y",
            zLabel: "Z",
            grid: grid
        )
        let standardLayout = HeatmapPlotLayout.compute(payload: payload, colorbarTickStyle: .standard)
        let endpointsLayout = HeatmapPlotLayout.compute(payload: payload, colorbarTickStyle: .endpointsOnly(decimals: 2))

        let expectedShift = 100.0 / 350.0 * 72.0
        #expect(abs((endpointsLayout.colorbarRect.minX - standardLayout.colorbarRect.minX) - expectedShift) < 1.0)
    }
}
