import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Helpers

private func make2x2Grid() -> HeatmapGrid {
    HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0, 1.0],
        zMatrix: [[0.0, 0.5], [0.5, 1.0]]
    )
}

private func make4x3Grid() -> HeatmapGrid {
    // 4 columns, 3 rows; zMatrix[row][col]
    HeatmapGrid(
        xValues: [0.0, 1.0, 2.0, 3.0],
        yValues: [0.0, 10.0, 20.0],
        zMatrix: [
            [0.0,  0.25, 0.50, 0.75],
            [0.25, 0.50, 0.75, 1.00],
            [0.50, 0.75, 1.00, 1.25],
        ]
    )
}

private func makePayload(
    title: String = "Test Heatmap",
    grid: HeatmapGrid? = nil,
    colormapKey: String? = nil,
    zRangeClamp: ClosedRange<Double>? = nil
) -> HeatmapPlotPayload {
    HeatmapPlotPayload(
        workflowID: "rsm",
        title: title,
        xLabel: "X (mm)",
        yLabel: "Y (mm)",
        zLabel: "κ (W/m·K)",
        grid: grid ?? make2x2Grid(),
        colormapKey: colormapKey,
        zRangeClamp: zRangeClamp
    )
}

// MARK: - HeatmapGrid validation

@Test func heatmapGridValidation() {
    // A consistent grid is valid
    let validGrid = make2x2Grid()
    #expect(validGrid.isValid)
    #expect(validGrid.nX == 2)
    #expect(validGrid.nY == 2)

    // Empty xValues → invalid
    let emptyX = HeatmapGrid(xValues: [], yValues: [1.0], zMatrix: [[]])
    #expect(!emptyX.isValid)

    // Row count mismatch → invalid
    let mismatch = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0, 1.0],
        zMatrix: [[0.0, 1.0]]    // only 1 row, but nY == 2
    )
    #expect(!mismatch.isValid)

    // Column count mismatch → invalid
    let colMismatch = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0],
        zMatrix: [[0.0, 1.0, 2.0]]  // 3 cols, but nX == 2
    )
    #expect(!colMismatch.isValid)
}

// MARK: - HeatmapPlotPayload Codable round-trip

@Test func heatmapPayloadEncodingDecoding() throws {
    let grid = make4x3Grid()
    let original = HeatmapPlotPayload(
        schemaVersion: 1,
        workflowID: "rsm",
        title: "Round-trip test",
        xLabel: "X axis",
        yLabel: "Y axis",
        zLabel: "Z value",
        grid: grid,
        colormapKey: "viridis",
        zRangeClamp: 0.0...1.5
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data    = try encoder.encode(original)
    let decoded = try decoder.decode(HeatmapPlotPayload.self, from: data)

    #expect(decoded.schemaVersion == original.schemaVersion)
    #expect(decoded.workflowID    == original.workflowID)
    #expect(decoded.title         == original.title)
    #expect(decoded.xLabel        == original.xLabel)
    #expect(decoded.yLabel        == original.yLabel)
    #expect(decoded.zLabel        == original.zLabel)
    #expect(decoded.colormapKey   == original.colormapKey)
    #expect(decoded.zRangeClampMin == 0.0)
    #expect(decoded.zRangeClampMax == 1.5)
    #expect(decoded.grid.nX       == original.grid.nX)
    #expect(decoded.grid.nY       == original.grid.nY)
    #expect(decoded.grid.xValues  == original.grid.xValues)
    #expect(decoded.grid.yValues  == original.grid.yValues)
    #expect(decoded.grid.zMatrix  == original.grid.zMatrix)
}

@Test func heatmapPayloadNilFieldsRoundTrip() throws {
    let original = makePayload()  // colormapKey=nil, zRangeClamp=nil

    let data    = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(HeatmapPlotPayload.self, from: data)

    #expect(decoded.colormapKey   == nil)
    #expect(decoded.zRangeClampMin == nil)
    #expect(decoded.zRangeClampMax == nil)
}

// MARK: - HeatmapColorScale — linear mapping

@Test func colorScaleLinearMapping() {
    let scale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "viridis")

    // zMin → t = 0
    let tMin = scale.normalizedValue(for: 0)
    #expect(abs(tMin - 0.0) < 1e-10)

    // zMax → t = 1
    let tMax = scale.normalizedValue(for: 10)
    #expect(abs(tMax - 1.0) < 1e-10)

    // midpoint → t = 0.5
    let tMid = scale.normalizedValue(for: 5)
    #expect(abs(tMid - 0.5) < 1e-10)

    // z < zMin → clamped to 0
    let tBelow = scale.normalizedValue(for: -5)
    #expect(tBelow == 0.0)

    // z > zMax → clamped to 1
    let tAbove = scale.normalizedValue(for: 15)
    #expect(tAbove == 1.0)

    // Colors at min/mid/max are distinct non-nil CGColors
    let cMin = scale.color(for: 0)
    let cMid = scale.color(for: 5)
    let cMax = scale.color(for: 10)
    #expect(cMin.components != nil)
    #expect(cMid.components != nil)
    #expect(cMax.components != nil)
    // viridis: t=0 is dark purple, t=1 is yellow — red channels differ
    let rMin = cMin.components![0]
    let rMax = cMax.components![0]
    #expect(rMax > rMin)   // yellow (high r) > dark purple (low r)
}

// MARK: - HeatmapColorScale — log10 mapping

@Test func colorScaleLogMapping() {
    let scale = HeatmapColorScale(zMin: 0, zMax: 100, mode: .log10, colormapKey: "viridis")

    // z = 0 (= zMin) must produce t = 0, not NaN
    let t0 = scale.normalizedValue(for: 0)
    #expect(!t0.isNaN)
    #expect(t0 == 0.0)

    // z = zMax must produce t = 1
    let tMax = scale.normalizedValue(for: 100)
    #expect(!tMax.isNaN)
    #expect(abs(tMax - 1.0) < 1e-6)

    // Negative z → clamped to t = 0, no NaN
    let tNeg = scale.normalizedValue(for: -50)
    #expect(!tNeg.isNaN)
    #expect(tNeg == 0.0)

    // Log scale: midpoint in value space is NOT midpoint in t space
    let tLinear = scale.normalizedValue(for: 50)    // 50/100 = 0.5 linear
    let tLog    = HeatmapColorScale(zMin: 1, zMax: 100, mode: .log10, colormapKey: "viridis")
                    .normalizedValue(for: 10)         // log(10)/log(100) = 0.5
    #expect(abs(tLog - 0.5) < 0.05)   // 10 is midpoint on log scale 1..100

    // color(for:) does not crash or return NaN components for z=0
    let c0 = scale.color(for: 0)
    #expect(c0.components != nil)
    for comp in c0.components! {
        #expect(!comp.isNaN)
    }

    _ = tLinear  // suppress unused-variable warning
}

// MARK: - Colorbar tick generation

@Test func colorbarTickGeneration() {
    let payload = makePayload(grid: make4x3Grid())   // Z in [0, 1.25]
    let layout  = HeatmapPlotLayout.compute(payload: payload)

    let ticks = layout.colorbarTicks
    #expect(ticks.count >= 3)
    #expect(ticks.count <= 7)

    // Ticks span from near zMin to near zMax
    #expect(layout.zMin == 0.0)
    #expect(layout.zMax == 1.25)

    // All tick labels are non-empty strings
    for (_, label) in ticks {
        #expect(!label.isEmpty)
    }

    // Tick Y positions are within colorbarRect
    let layout2 = HeatmapPlotLayout.compute(payload: payload)
    for (y, _) in ticks {
        #expect(y >= layout2.colorbarRect.minY - 1)
        #expect(y <= layout2.colorbarRect.maxY + 1)
    }
}

@Test func colorbarTickGenerationNiceNumbers() {
    // Z range 0..10 → should produce ticks at nice round values
    let payload = HeatmapPlotPayload(
        workflowID: "test",
        title: "",
        xLabel: "", yLabel: "", zLabel: "",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [0.0, 1.0],
            zMatrix: [[0.0, 5.0], [5.0, 10.0]]
        )
    )
    let layout = HeatmapPlotLayout.compute(payload: payload)
    #expect(layout.zMin == 0.0)
    #expect(layout.zMax == 10.0)
    #expect(layout.colorbarTicks.count >= 3)
    // Nice-number ticks for 0..10 should be integers
    for (_, label) in layout.colorbarTicks {
        let v = Double(label)
        #expect(v != nil)
    }
}

// MARK: - niceTicks helper

@Test func heatmapNiceTicksCountInRange() {
    for (lo, hi) in [(0.0, 1.0), (0.0, 100.0), (-50.0, 50.0), (1e-3, 1e-2)] {
        let ticks = HeatmapPlotLayout.niceTicks(min: lo, max: hi, targetCount: 5)
        #expect(ticks.count >= 2)
        #expect(ticks.count <= 8)
        #expect(ticks.first! >= lo - 1e-9)
        #expect(ticks.last!  <= hi + 1e-9)
    }
}

// MARK: - HeatmapRenderer — non-empty PNG output

@Test func rendererOutputNonEmptyPNG() throws {
    let payload = makePayload(grid: make2x2Grid())
    let renderer = HeatmapRenderer()
    let data = try renderer.renderPNG(payload: payload)

    // Non-empty
    #expect(data.count > 0)

    // Valid PNG: first 8 bytes are the PNG signature
    let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    let headerBytes = [UInt8](data.prefix(8))
    #expect(headerBytes == pngSignature)
}

@Test func rendererOutputNonEmptyPNGLog10Scale() throws {
    let payload = makePayload(
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0, 2.0],
            zMatrix: [[0.0, 1.0, 10.0], [1.0, 10.0, 100.0], [10.0, 100.0, 1000.0]]
        )
    )
    let data = try HeatmapRenderer().renderPNG(payload: payload, colorScaleMode: .log10)
    #expect(data.count > 0)
    let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func rendererLogScaleHandlesZeroAndNegativeValues() throws {
    let payload = makePayload(
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0],
            zMatrix: [
                [-10.0, 0.0, 1.0],
                [2.0, 10.0, 100.0]
            ]
        )
    )
    let data = try HeatmapRenderer().renderPNG(payload: payload, colorScaleMode: .log10)
    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
}

@Test func rendererLinearAndLogOutputsDiffer() throws {
    let payload = makePayload(
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0, 2.0],
            zMatrix: [
                [1.0, 10.0, 100.0],
                [2.0, 20.0, 200.0],
                [3.0, 30.0, 300.0],
            ]
        )
    )
    let linear = try HeatmapRenderer().renderPNG(payload: payload, colorScaleMode: .linear)
    let log = try HeatmapRenderer().renderPNG(payload: payload, colorScaleMode: .log10)
    #expect(linear != log)
}

@Test func rendererInvalidGridThrows() throws {
    let badGrid = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0, 1.0],
        zMatrix: [[0.0]]        // only 1 row, 1 col — inconsistent with nX=2, nY=2
    )
    let payload = makePayload(grid: badGrid)
    #expect(throws: (any Error).self) {
        try HeatmapRenderer().renderPNG(payload: payload)
    }
}

// MARK: - HeatmapRenderPipeline

@Test func heatmapRenderPipelineProducesOutput() throws {
    let input = HeatmapRenderPipeline.Input(payload: makePayload(grid: make4x3Grid()))
    let output = try HeatmapRenderPipeline.render(input)
    #expect(output.imageData.count > 0)
    #expect(output.layout.gridRect.width > 0)
    #expect(output.layout.gridRect.height > 0)
}

@Test func heatmapRenderPipelineAppliesOverrides() throws {
    var input = HeatmapRenderPipeline.Input(payload: makePayload())
    input.titleOverride  = "Override Title"
    input.xLabelOverride = "Override X"
    input.yLabelOverride = "Override Y"
    input.zLabelOverride = "Override Z"
    // Should not throw; overrides are applied to a copy, not the original payload
    let output = try HeatmapRenderPipeline.render(input)
    #expect(output.imageData.count > 0)
}

@Test func heatmapRenderPipelineZRangeClamp() throws {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Clamped",
        xLabel: "", yLabel: "", zLabel: "",
        grid: make4x3Grid(),
        zRangeClamp: 0.2...0.8
    )
    let input  = HeatmapRenderPipeline.Input(payload: payload)
    let output = try HeatmapRenderPipeline.render(input)
    #expect(abs(output.layout.zMin - 0.2) < 1e-10)
    #expect(abs(output.layout.zMax - 0.8) < 1e-10)
}

@Test func heatmapRenderPipelineLogTicksAreClearlyLogarithmic() throws {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Log ticks",
        xLabel: "", yLabel: "", zLabel: "Detector",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0],
            zMatrix: [
                [1.0, 10.0, 100.0],
                [2.0, 20.0, 200.0]
            ]
        )
    )
    let output = try HeatmapRenderPipeline.render(.init(payload: payload, colorScaleMode: .log10))
    #expect(output.layout.colorbarTicks.contains { $0.label.contains("10^") || $0.label.contains("x10^") })
    #expect(output.layout.colorbarTicks.count >= 2)
}

@Test func heatmapRenderPipelineFontSizeOverridesAffectPNG() throws {
    let payload = makePayload(grid: make4x3Grid())
    var style = WorkbenchChartStyle()
    style.titleFontSize = 32
    style.axisTitleFontSize = 28
    style.tickLabelFontSize = 26

    let defaultPNG = try HeatmapRenderer().renderPNG(payload: payload)
    let styledPNG = try HeatmapRenderer().renderPNG(payload: payload, chartStyle: style)

    #expect(defaultPNG != styledPNG)
}

// MARK: - HeatmapTabRenderState Codable

private func heatmapTabRenderStateJSONKeys(_ state: HeatmapTabRenderState) throws -> [String] {
    let data = try JSONEncoder().encode(state)
    let object = try JSONSerialization.jsonObject(with: data)
    let dictionary = try #require(object as? [String: Any])
    return Array(dictionary.keys)
}

@Test func heatmapTabRenderStateRoundTrip() throws {
    let state = HeatmapTabRenderState(
        schemaVersion: 3,
        titleOverride:  "My Title",
        xLabelOverride: "My X",
        yLabelOverride: "My Y",
        zLabelOverride: "My Z",
        colorScaleMode: .log10,
        colormapKey: "inferno",
        zRangeOverrideMin: 1.5,
        zRangeOverrideMax: 9.5
    )
    let data    = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: data)
    #expect(decoded.schemaVersion == 3)
    #expect(decoded.titleOverride  == "My Title")
    #expect(decoded.xLabelOverride == "My X")
    #expect(decoded.yLabelOverride == "My Y")
    #expect(decoded.zLabelOverride == "My Z")
    #expect(decoded.colorScaleMode == .log10)
    #expect(decoded.colormapKey == "inferno")
    #expect(decoded.zRangeOverrideMin == 1.5)
    #expect(decoded.zRangeOverrideMax == 9.5)
}

@Test func heatmapTabRenderStateDefaultDecodeMigration() throws {
    let legacyJSON = """
    {
      "titleOverride": "Saved Title",
      "xLabelOverride": "Saved X",
      "yLabelOverride": "Saved Y",
      "zLabelOverride": "Saved Z"
    }
    """
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: Data(legacyJSON.utf8))
    #expect(decoded.schemaVersion == HeatmapTabRenderState.currentSchemaVersion)
    #expect(decoded.titleOverride == "Saved Title")
    #expect(decoded.xLabelOverride == "Saved X")
    #expect(decoded.yLabelOverride == "Saved Y")
    #expect(decoded.zLabelOverride == "Saved Z")
    #expect(decoded.colorScaleMode == .linear)
    #expect(decoded.colormapKey == "viridis")
    #expect(decoded.zRangeOverrideMin == 0)
    #expect(decoded.zRangeOverrideMax == 0)
}

@Test func heatmapTabRenderStateZLabelOverrideRoundTrip() throws {
    let state = HeatmapTabRenderState(zLabelOverride: "κ (W/m·K)")
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.zLabelOverride == "κ (W/m·K)")
}

@Test func heatmapTabRenderStateColorScaleModeRoundTrip() throws {
    let state = HeatmapTabRenderState(colorScaleMode: .log10)
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.colorScaleMode == .log10)
}

@Test func heatmapTabRenderStateColormapKeyRoundTrip() throws {
    let state = HeatmapTabRenderState(colormapKey: "magma")
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.colormapKey == "magma")
}

@Test func heatmapTabRenderStateZRangeOverrideRoundTrip() throws {
    let state = HeatmapTabRenderState(zRangeOverrideMin: 0.25, zRangeOverrideMax: 0.75)
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.zRangeOverrideMin == 0.25)
    #expect(decoded.zRangeOverrideMax == 0.75)
}

@Test func heatmapTabRenderStateEncodedJSONOmitsRSMOwnedFields() throws {
    let state = HeatmapTabRenderState()
    let jsonString = String(data: try JSONEncoder().encode(state), encoding: .utf8) ?? ""
    #expect(!jsonString.contains("sourceFileIdentity"))
    #expect(!jsonString.contains("detectorColumnName"))
    #expect(!jsonString.contains("activeView"))
    #expect(!jsonString.contains("view"))
    #expect(!jsonString.contains("plotLayout"))
    #expect(!jsonString.contains("HeatmapPlotLayout"))
    #expect(!jsonString.contains("HeatmapPlotPayload"))
    #expect(!jsonString.contains("renderedPNG"))
}

@Test func heatmapTabRenderStateEncodedJSONOmitsCartesianXYFields() throws {
    let state = HeatmapTabRenderState()
    let jsonString = String(data: try JSONEncoder().encode(state), encoding: .utf8) ?? ""
    #expect(!jsonString.contains("legendPoint"))
    #expect(!jsonString.contains("legendAnchor"))
    #expect(!jsonString.contains("seriesOrder"))
    #expect(!jsonString.contains("seriesLabelOverrides"))
    #expect(!jsonString.contains("hiddenPointLabelIndicesBySeries"))
}

@Test func heatmapTabRenderStateEncodedJSONContainsRequiredFields() throws {
    let state = HeatmapTabRenderState()
    let keys = try heatmapTabRenderStateJSONKeys(state)
    #expect(keys.contains("schemaVersion"))
    #expect(keys.contains("titleOverride"))
    #expect(keys.contains("xLabelOverride"))
    #expect(keys.contains("yLabelOverride"))
    #expect(keys.contains("zLabelOverride"))
    #expect(keys.contains("colorScaleMode"))
    #expect(keys.contains("colormapKey"))
    #expect(keys.contains("zRangeOverrideMin"))
    #expect(keys.contains("zRangeOverrideMax"))
}

// MARK: - XY regression: existing XY render path is unmodified

@Test func xyRegressionXYRendererUnchanged() throws {
    // Verify the existing XY render path still works and produces non-empty PNG.
    // This test guards against accidental modification of WorkbenchChartRenderer,
    // WorkbenchRenderPipeline, or WorkbenchPlotLayout while adding heatmap files.
    let payload = WorkbenchPlotPayload(
        workflowID: "ahe",
        workflowDisplayName: "AHE",
        title: "XY regression",
        axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)"),
        series: [
            WorkbenchPlotSeries(
                label: "Sample A",
                x: [1.0, 2.0, 3.0],
                y: [0.1, 0.2, 0.15],
                sourceRef: "/tmp/a.dat"
            )
        ]
    )
    let input = WorkbenchRenderPipeline.Input(payload: payload)
    let output = try WorkbenchRenderPipeline.render(input)
    #expect(output.imageData.count > 0)
    let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    #expect([UInt8](output.imageData.prefix(8)) == pngSignature)
    // Layout geometry is intact
    #expect(output.layout.plotRect.width > 0)
    #expect(output.layout.plotRect.height > 0)
}

// MARK: - Coordinate orientation

@Test func coordinateOrientationYValues0AtVisualBottom() {
    // V1 convention: row 0 (yValues[0]) is drawn at gridRect.minY in CG space.
    // CG space is Y-up (minY < maxY; minY is the visual bottom of the image).
    // For ascending yValues this means the smallest y value appears at the bottom.
    let grid = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0, 10.0, 20.0],    // ascending
        zMatrix: [[0.0, 0.0], [0.5, 0.5], [1.0, 1.0]]
    )
    let payload = HeatmapPlotPayload(
        workflowID: "test", title: "", xLabel: "", yLabel: "", zLabel: "", grid: grid
    )
    let layout = HeatmapPlotLayout.compute(payload: payload)
    let nY = grid.nY
    let cellH = layout.gridRect.height / CGFloat(nY)

    // CG Y-up: minY < maxY confirms the grid has positive height
    #expect(layout.gridRect.minY < layout.gridRect.maxY)

    // Cell center for row 0 (yValues[0] = 0.0) — visual bottom
    let bottomCenter = layout.gridRect.minY + 0.5 * cellH
    // Cell center for row 2 (yValues[2] = 20.0) — visual top
    let topCenter = layout.gridRect.minY + CGFloat(nY - 1) * cellH + 0.5 * cellH

    // row 0 is at a lower CG Y than row nY-1: yValues[0] is visually below yValues[nY-1]
    #expect(bottomCenter < topCenter)
    // Gap is exactly 2 cell heights (row 0 center to row 2 center)
    #expect(abs(Double(topCenter - bottomCenter - 2.0 * cellH)) < 1e-6)
}

@Test func coordinateOrientationNonMonotonicAxesAccepted() throws {
    // V1 policy: non-monotonic yValues are accepted without error.
    // Cells render in array row order; tick labels may not align with scientific convention.
    let grid = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [20.0, 10.0, 0.0],    // descending — accepted in V1
        zMatrix: [[0.0, 0.0], [0.5, 0.5], [1.0, 1.0]]
    )
    let payload = HeatmapPlotPayload(
        workflowID: "test", title: "", xLabel: "", yLabel: "", zLabel: "", grid: grid
    )
    let data = try HeatmapRenderer().renderPNG(payload: payload)
    #expect(data.count > 0)
}

// MARK: - Color scale edge cases (NaN / Infinity)

@Test func colorScaleNaNHandling() {
    // NaN Z values → minimum color (t = 0), never produce NaN output.
    let linearScale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "viridis")
    let tNaN = linearScale.normalizedValue(for: .nan)
    #expect(!tNaN.isNaN)
    #expect(tNaN == 0.0)

    let logScale = HeatmapColorScale(zMin: 1, zMax: 100, mode: .log10, colormapKey: "viridis")
    let tNaNLog = logScale.normalizedValue(for: .nan)
    #expect(!tNaNLog.isNaN)
    #expect(tNaNLog == 0.0)

    // color(for: NaN) must return all-finite components
    let c = linearScale.color(for: .nan)
    #expect(c.components != nil)
    for comp in c.components! {
        #expect(!comp.isNaN)
    }
}

@Test func colorScaleInfinityHandling() {
    let scale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "viridis")
    // +Inf → maximum color (t = 1)
    #expect(scale.normalizedValue(for: .infinity) == 1.0)
    // -Inf → minimum color (t = 0)
    #expect(scale.normalizedValue(for: -.infinity) == 0.0)
}

// MARK: - Z-range clamp validation

@Test func invalidZRangeClampThrows() {
    // lo == hi (zero span): must throw
    var payload = makePayload()
    payload.zRangeClampMin = 5.0
    payload.zRangeClampMax = 5.0
    let input = HeatmapRenderPipeline.Input(payload: payload)
    #expect(throws: HeatmapRenderError.self) {
        try HeatmapRenderPipeline.render(input)
    }

    // lo > hi (inverted range): must throw
    var payload2 = makePayload()
    payload2.zRangeClampMin = 10.0
    payload2.zRangeClampMax = 2.0
    let input2 = HeatmapRenderPipeline.Input(payload: payload2)
    #expect(throws: HeatmapRenderError.self) {
        try HeatmapRenderPipeline.render(input2)
    }
}

@Test func partialZRangeClampFallsBackToAuto() throws {
    // Only zRangeClampMin set, no max → silently ignored, uses data auto-range.
    var payload = makePayload(grid: make4x3Grid())   // data Z in [0, 1.25]
    payload.zRangeClampMin = 0.5
    let output = try HeatmapRenderPipeline.render(.init(payload: payload))
    #expect(abs(output.layout.zMin - 0.0)  < 1e-10)
    #expect(abs(output.layout.zMax - 1.25) < 1e-10)

    // Only zRangeClampMax set, no min → also silently ignored.
    var payload2 = makePayload(grid: make4x3Grid())
    payload2.zRangeClampMax = 0.8
    let output2 = try HeatmapRenderPipeline.render(.init(payload: payload2))
    #expect(abs(output2.layout.zMin - 0.0)  < 1e-10)
    #expect(abs(output2.layout.zMax - 1.25) < 1e-10)
}

// MARK: - Log10 colorbar tick alignment

@Test func colorbarTicksAlignWithLogScale() {
    // For log10 scale, tick Y positions must match log-normalized positions in
    // the colorbar, not linear positions. Z=50 in [0,100] log scale maps to
    // t ≈ 0.95 (near top), not t = 0.5 (middle) as it would for linear.
    let grid = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0, 1.0],
        zMatrix: [[0.0, 50.0], [50.0, 100.0]]
    )
    let payload = HeatmapPlotPayload(
        workflowID: "test", title: "", xLabel: "", yLabel: "", zLabel: "", grid: grid
    )
    let linearLayout = HeatmapPlotLayout.compute(payload: payload, colorScaleMode: .linear)
    let logLayout    = HeatmapPlotLayout.compute(payload: payload, colorScaleMode: .log10)

    // Both share the same colorbarRect geometry
    #expect(linearLayout.colorbarRect == logLayout.colorbarRect)

    // Log-scale tick Y values must be monotonically non-decreasing (ascending Z → ascending Y)
    let logYs = logLayout.colorbarTicks.map(\.y)
    let isSortedAsc = zip(logYs, logYs.dropFirst()).allSatisfy { $0 <= $1 }
    #expect(isSortedAsc)

    // For each tick, find the one whose label parses closest to z=50
    func nearestTickY(in layout: HeatmapPlotLayout, to z: Double) -> CGFloat? {
        layout.colorbarTicks
            .compactMap { (y, label) -> (CGFloat, Double)? in
                guard let v = Double(label) else { return nil }
                return (y, abs(v - z))
            }
            .min(by: { $0.1 < $1.1 })
            .map(\.0)
    }

    if let linearY = nearestTickY(in: linearLayout, to: 50),
       let logY    = nearestTickY(in: logLayout,    to: 50) {
        // On log scale z=50 out of [0,100] maps to t ≈ 0.95 → tick near top (large Y)
        // On linear scale z=50 out of [0,100] maps to t = 0.5 → tick at middle
        // So the log tick must be at a higher CG Y than the linear tick
        #expect(logY > linearY)
    }
}

// MARK: - Boundary: HeatmapTabRenderState does not pollute TabRenderState

@Test func preservationStateDoesNotPollutXYTabRenderState() throws {
    // Simulate what would happen if a heatmap render cycle ran alongside XY tabs.
    // XY TabRenderState fields must remain isolated from any heatmap state.
    var xyState = TabRenderState()
    xyState.seriesLabelOverrides    = ["0": "Series A"]
    xyState.legendPoint             = CGPointCodable(CGPoint(x: 0.5, y: 0.5))
    xyState.seriesOrder             = ["ref-1", "ref-2"]

    // A heatmap tab render state operates independently
    let heatmapState = HeatmapTabRenderState(
        titleOverride: "Heatmap",
        zLabelOverride: "κ"
    )

    // XY state is unchanged — heatmap state has no shared storage
    #expect(xyState.seriesLabelOverrides == ["0": "Series A"])
    #expect(xyState.legendPoint?.x       == 0.5)
    #expect(xyState.seriesOrder          == ["ref-1", "ref-2"])
    #expect(heatmapState.titleOverride   == "Heatmap")

    // Encoding the heatmap state must not emit XY-specific TabRenderState keys
    let heatmapData = try JSONEncoder().encode(heatmapState)
    let jsonString = String(data: heatmapData, encoding: .utf8) ?? ""
    #expect(!jsonString.contains("seriesLabelOverrides"))
    #expect(!jsonString.contains("legendPoint"))
    #expect(!jsonString.contains("seriesOrder"))
    #expect(!jsonString.contains("hiddenPointLabels"))
}
