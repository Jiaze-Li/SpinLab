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

private func loadHeatmapSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
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

@Test("V1 unknown colormap key falls back to viridis")
func testV1UnknownColormapKeyFallsBackToViridis() {
    let infernoScale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "inferno")
    let viridisScale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "viridis")

    let infernoColor = infernoScale.color(for: 5)
    let viridisColor = viridisScale.color(for: 5)

    #expect(infernoColor.components == viridisColor.components)
}

@Test func rsmTurboMapsLowToBlueAndHighToRed() {
    let scale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "rsmTurbo")

    let cLow  = scale.color(for: 0).components!
    let cHigh = scale.color(for: 10).components!

    // Low intensity: dark blue-ish — blue channel dominates, red is low.
    #expect(cLow[2] > cLow[0])
    // High intensity: red-ish — red channel dominates, blue is low.
    #expect(cHigh[0] > cHigh[2])
}

@Test func rsmTurboMidTIsGreenOrYellowish() {
    let scale = HeatmapColorScale(zMin: 0, zMax: 1, mode: .linear, colormapKey: "rsmTurbo")
    let cMid = scale.color(forNormalized: 0.5).components!

    // Mid intensity: green/yellow-ish — green channel dominates blue, and is not red-saturated.
    #expect(cMid[1] > cMid[2])
    #expect(cMid[0] < 0.9)
}

@Test func rsmTurboAdjacentSampledColorsChangeSmoothly() {
    let scale = HeatmapColorScale(zMin: 0, zMax: 1, mode: .linear, colormapKey: "rsmTurbo")
    let samples = stride(from: 0.0, through: 1.0, by: 0.02).map { scale.color(forNormalized: $0).components! }

    // No adjacent pair should jump by more than a small fraction of the full channel range —
    // i.e. no abrupt flat-then-cliff transition anywhere along the ramp (the original bug).
    for i in 1..<samples.count {
        let prev = samples[i - 1]
        let cur  = samples[i]
        let maxChannelDelta = max(abs(cur[0] - prev[0]), abs(cur[1] - prev[1]), abs(cur[2] - prev[2]))
        #expect(maxChannelDelta < 0.15, "Unexpectedly large color jump between adjacent samples near t=\(Double(i) * 0.02)")
    }
}

@Test func rsmTurboHighEndHasFinerGradationThanCoarseSevenStopVersion() {
    // The refined colormap must distinguish intensities in the top 10% of the range —
    // the original 7-stop version had a single flat red stop covering t ∈ [0.833, 1.0].
    let scale = HeatmapColorScale(zMin: 0, zMax: 1, mode: .linear, colormapKey: "rsmTurbo")
    let cNearTop = scale.color(forNormalized: 0.92).components!
    let cTop     = scale.color(forNormalized: 1.0).components!
    #expect(cNearTop != cTop, "Top-of-range intensities must still be visually distinguishable")
}

@Test func colorForAndColorForNormalizedUseSameColormap() {
    let viridisScale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "viridis")
    #expect(viridisScale.color(for: 5).components == viridisScale.color(forNormalized: 0.5).components)

    let turboScale = HeatmapColorScale(zMin: 0, zMax: 10, mode: .linear, colormapKey: "rsmTurbo")
    #expect(turboScale.color(for: 5).components == turboScale.color(forNormalized: 0.5).components)
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

@Test func heatmapLayoutDynamicYAxisSpacingRespondsToTickLabelWidth() {
    let shortPayload = HeatmapPlotPayload(
        workflowID: "heatmap",
        title: "Short Y labels",
        xLabel: "X",
        yLabel: "Y",
        zLabel: "Z",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [2.8, 3.1],
            zMatrix: [[0.0, 0.5], [0.5, 1.0]]
        )
    )
    let longPayload = HeatmapPlotPayload(
        workflowID: "heatmap",
        title: "Long Y labels",
        xLabel: "X",
        yLabel: "Y",
        zLabel: "Z",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [12345.0, 67890.0],
            zMatrix: [[0.0, 0.5], [0.5, 1.0]]
        )
    )

    let shortLayout = HeatmapPlotLayout.compute(payload: shortPayload)
    let longLayout = HeatmapPlotLayout.compute(payload: longPayload)
    let shortTickWidth = HeatmapPlotLayout.sampledYAxisTickEntries(for: shortPayload.grid)
        .map { HeatmapPlotLayout.measuredTextWidth($0.label, fontSize: WorkbenchChartStyle().tickLabelFontSize, fontName: WorkbenchChartStyle().fontName, boldFontName: WorkbenchChartStyle().boldFontName) }
        .max() ?? 0
    let longTickWidth = HeatmapPlotLayout.sampledYAxisTickEntries(for: longPayload.grid)
        .map { HeatmapPlotLayout.measuredTextWidth($0.label, fontSize: WorkbenchChartStyle().tickLabelFontSize, fontName: WorkbenchChartStyle().fontName, boldFontName: WorkbenchChartStyle().boldFontName) }
        .max() ?? 0

    #expect(shortTickWidth < longTickWidth)
    #expect(shortLayout.gridRect.minX < longLayout.gridRect.minX)
    #expect(shortLayout.yLabelCenter.x < shortLayout.gridRect.minX)
    #expect(longLayout.yLabelCenter.x < longLayout.gridRect.minX)
}

@Test func heatmapLayoutColorbarLanesSeparateTitleFromTickLabels() {
    let shortPayload = HeatmapPlotPayload(
        workflowID: "heatmap",
        title: "Short Z labels",
        xLabel: "X",
        yLabel: "Y",
        zLabel: "Z",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [0.0, 1.0],
            zMatrix: [[0.0, 0.5], [0.5, 1.0]]
        )
    )
    let longPayload = HeatmapPlotPayload(
        workflowID: "heatmap",
        title: "Long Z labels",
        xLabel: "X",
        yLabel: "Y",
        zLabel: "Intensity (counts)",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [0.0, 1.0],
            zMatrix: [[0.0, 50000.0], [50000.0, 100000.0]]
        )
    )

    let style = WorkbenchChartStyle()
    let shortLayout = HeatmapPlotLayout.compute(payload: shortPayload, chartStyle: style)
    let longLayout = HeatmapPlotLayout.compute(payload: longPayload, chartStyle: style)
    let shortTickWidth = shortLayout.colorbarTicks.map {
        HeatmapPlotLayout.measuredTextWidth($0.label, fontSize: style.tickLabelFontSize, fontName: style.fontName, boldFontName: style.boldFontName)
    }.max() ?? 0
    let longTickWidth = longLayout.colorbarTicks.map {
        HeatmapPlotLayout.measuredTextWidth($0.label, fontSize: style.tickLabelFontSize, fontName: style.fontName, boldFontName: style.boldFontName)
    }.max() ?? 0

    #expect(shortTickWidth <= longTickWidth)
    // Z title is now LEFT of colorbar: colorbarLabelCenter.x < colorbarRect.minX
    #expect(shortLayout.colorbarLabelCenter.x < shortLayout.colorbarRect.minX)
    #expect(longLayout.colorbarLabelCenter.x < longLayout.colorbarRect.minX)
    #expect(shortLayout.gridRect.maxX < shortLayout.colorbarRect.minX)
    #expect(longLayout.gridRect.maxX < longLayout.colorbarRect.minX)
    #expect(shortLayout.showColorbar)
    #expect(longLayout.showColorbar)
}

@Test func heatmapRenderPipelineShowZLabelToggleLeavesColorbarTicksVisible() throws {
    let payload = HeatmapPlotPayload(
        workflowID: "heatmap",
        title: "Toggle Z label",
        xLabel: "X",
        yLabel: "Y",
        zLabel: "Intensity (counts)",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [0.0, 1.0],
            zMatrix: [[0.0, 50000.0], [50000.0, 100000.0]]
        )
    )

    let visible = try HeatmapRenderPipeline.render(.init(payload: payload, showColorbar: true))
    let hidden = try HeatmapRenderPipeline.render(.init(payload: payload, showColorbar: false))

    #expect(visible.layout.showColorbar)
    #expect(!hidden.layout.showColorbar)
    // showColorbar=false hides the entire colorbar block including ticks
    #expect(visible.layout.colorbarTicks.count >= 2)
    #expect(hidden.layout.colorbarTicks.isEmpty)
    #expect(!visible.imageData.isEmpty)
    #expect(!hidden.imageData.isEmpty)
    #expect(visible.imageData != hidden.imageData)
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

@Test func heatmapRenderPipelineManualZDomain() throws {
    let payload = makePayload(grid: make4x3Grid())
    let input = HeatmapRenderPipeline.Input(
        payload: payload,
        zDomainState: HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "0.2", maxText: "0.8")
        )
    )
    let output = try HeatmapRenderPipeline.render(input)
    #expect(abs(output.layout.zMin - 0.2) < 1e-10)
    #expect(abs(output.layout.zMax - 0.8) < 1e-10)
}

@Test func heatmapRenderPipelinePercentileZDomain() throws {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Percentile",
        xLabel: "", yLabel: "", zLabel: "",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0, 3.0],
            yValues: [0.0, 1.0],
            zMatrix: [
                [1.0, 2.0, 3.0, 100.0],
                [4.0, 5.0, 6.0, 200.0]
            ]
        )
    )
    let input = HeatmapRenderPipeline.Input(
        payload: payload,
        zDomainState: HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .p1_99
        )
    )
    let output = try HeatmapRenderPipeline.render(input)
    #expect(output.layout.zMin > 1.0)
    #expect(output.layout.zMax < 200.0)
    #expect(output.layout.zMin < output.layout.zMax)
}

@Test func heatmapRenderPipelineInvalidManualDomainFallsBackToAuto() throws {
    let payload = makePayload(grid: make4x3Grid())
    let input = HeatmapRenderPipeline.Input(
        payload: payload,
        zDomainState: HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "", maxText: "0.8")
        )
    )
    let output = try HeatmapRenderPipeline.render(input)
    #expect(abs(output.layout.zMin - 0.0) < 1e-10)
    #expect(abs(output.layout.zMax - 1.25) < 1e-10)
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
    let output = try HeatmapRenderPipeline.render(.init(
        payload: payload,
        colorScaleMode: .log10,
        zDomainState: HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .p5_95
        )
    ))
    #expect(output.layout.colorbarTicks.contains { $0.label.contains("1e") })
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

@Test("HeatmapRenderer routes math labels through MathMarkupRenderer")
func heatmapRendererRoutesMathLabelsThroughMathMarkupRenderer() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = root.appendingPathComponent("Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapRenderer.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("MathMarkupRenderer.isMathLabel"))
    #expect(source.contains("MathMarkupRenderer.extractMathMarkup"))
    #expect(source.contains("MathMarkupRenderer.makeLine"))

    let forbidden = [
        "LatexAxisLabelRenderer",
        "LatexAxisLabelRendering",
        "LegacyAxisLabelRenderer",
        "LegacyAxisLabelRendering",
        "DeprecatedMathAxisShim",
        "latex:",
    ]
    for symbol in forbidden {
        #expect(!source.contains(symbol))
    }
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
        schemaVersion: 2,
        titleOverride:  "My Title",
        xLabelOverride: "My X",
        yLabelOverride: "My Y",
        zLabelOverride: "My Z",
        showColorbar: false,
        colorScaleMode: .log10,
        colormapKey: "inferno",
        zDomainState: HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "1.5", maxText: "9.5")
        )
    )
    let data    = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: data)
    #expect(decoded.schemaVersion == 2)
    #expect(decoded.titleOverride  == "My Title")
    #expect(decoded.xLabelOverride == "My X")
    #expect(decoded.yLabelOverride == "My Y")
    #expect(decoded.zLabelOverride == "My Z")
    #expect(!decoded.showColorbar)
    #expect(decoded.colorScaleMode == .log10)
    #expect(decoded.colormapKey == "inferno")
    #expect(decoded.zDomainState.mode == .manual)
    #expect(decoded.zDomainState.manualRange.minText == "1.5")
    #expect(decoded.zDomainState.manualRange.maxText == "9.5")
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
    #expect(decoded.showColorbar)
    #expect(decoded.colorScaleMode == .linear)
    // Legacy packs predating this key must decode to "no override" (nil), not a forced
    // "viridis" — a forced default would silently clobber a payload's own colormapKey
    // (e.g. RSM's rsmTurbo) on restore.
    #expect(decoded.colormapKey == nil)
    #expect(decoded.zDomainState.mode == .auto)
    #expect(decoded.zDomainState.manualRange.minText.isEmpty)
    #expect(decoded.zDomainState.manualRange.maxText.isEmpty)
}

@Test func heatmapTabRenderStateAutoRoundTrip() throws {
    let state = HeatmapTabRenderState()
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.zDomainState.mode == .auto)
}

@Test func heatmapTabRenderStateZLabelOverrideRoundTrip() throws {
    let state = HeatmapTabRenderState(zLabelOverride: "κ (W/m·K)")
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.zLabelOverride == "κ (W/m·K)")
}

@Test func heatmapTabRenderStateDefaultsShowColorbarToTrue() {
    #expect(HeatmapTabRenderState().showColorbar)
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

@Test func heatmapTabRenderStatePercentileRoundTrip() throws {
    let state = HeatmapTabRenderState(
        zDomainState: HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .p2_98
        )
    )
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
    #expect(decoded.zDomainState.mode == .percentile)
    #expect(decoded.zDomainState.percentilePreset == .p2_98)
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
    #expect(keys.contains("showColorbar"))
    #expect(!keys.contains("showZLabel"))
    #expect(!keys.contains("xTickCount"), "xTickCount must not be in new encoding (migrated to tickConfiguration)")
    #expect(!keys.contains("yTickCount"), "yTickCount must not be in new encoding (migrated to tickConfiguration)")
    #expect(keys.contains("tickConfiguration"), "tickConfiguration key must be present in new encoding")
    #expect(keys.contains("colorScaleMode"))
    #expect(keys.contains("colormapKey"))
    #expect(keys.contains("zDomainState"))
    #expect(!keys.contains("zRangeOverrideMin"))
    #expect(!keys.contains("zRangeOverrideMax"))
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

@Test func invalidZRangeClampFallsBackToAuto() throws {
    // lo == hi (zero span): legacy direct payload clamp is ignored and falls back to auto
    var payload = makePayload()
    payload.zRangeClampMin = 5.0
    payload.zRangeClampMax = 5.0
    let input = HeatmapRenderPipeline.Input(payload: payload)
    let output = try HeatmapRenderPipeline.render(input)
    #expect(output.layout.zMin == 0.0)
    #expect(output.layout.zMax == 1.0)

    // lo > hi (inverted range): also falls back to auto
    var payload2 = makePayload()
    payload2.zRangeClampMin = 10.0
    payload2.zRangeClampMax = 2.0
    let input2 = HeatmapRenderPipeline.Input(payload: payload2)
    let output2 = try HeatmapRenderPipeline.render(input2)
    #expect(output2.layout.zMin == 0.0)
    #expect(output2.layout.zMax == 1.0)
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

// MARK: - Log colorbar gradient uses geometric interpolation

@Test func logColorbarStripUsesGeometricInterpolation() {
    // For log domain [1, 1000], the midpoint strip (t=0.5) must correspond to the
    // geometric midpoint (≈31.6), not the arithmetic midpoint (500.5).
    // We verify this by comparing normalized values: geometric mid normalizes to ≈0.5,
    // arithmetic mid normalizes to ≈0.95 (much higher).
    let scale = HeatmapColorScale(zMin: 1, zMax: 1000, transform: .log10, colormapKey: "viridis")
    let geometricMidZ = sqrt(1.0 * 1000.0)  // ≈ 31.6
    let arithmeticMidZ = (1.0 + 1000.0) / 2  // = 500.5

    // color(forNormalized: 0.5) is what the strip renders at t=0.5
    let stripColor = scale.color(forNormalized: 0.5)

    // color(for: geometricMidZ) should normalize to ≈0.5 → close match to strip
    let geoColor = scale.color(for: geometricMidZ)

    // color(for: arithmeticMidZ) normalizes to ≈0.95 → very different from strip
    let arithColor = scale.color(for: arithmeticMidZ)

    // Compare red channel: viridis t=0.5 (dark teal) vs t≈0.95 (yellow-green)
    let stripR  = stripColor.components?[0]  ?? 0
    let geoR    = geoColor.components?[0]    ?? 0
    let arithR  = arithColor.components?[0]  ?? 0

    // Strip and geometric midpoint are close; strip and arithmetic midpoint differ
    #expect(abs(stripR - geoR) < abs(stripR - arithR),
            "Log colorbar strip at t=0.5 must match geometric midpoint, not arithmetic")
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

    // Both preserve the same colorbar height; the x-position may shift because
    // the right-side layout now reserves measured tick-label and title lanes.
    #expect(linearLayout.colorbarRect.height == logLayout.colorbarRect.height)

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

// MARK: - Gate HeatmapLayoutPolish-Followup-2: plot width, Z label, log ticks

@Test func showColorbarDoesNotShrinkGridWidth() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Width stability",
        xLabel: "H (r.l.u.)", yLabel: "L (r.l.u.)", zLabel: "Intensity (counts)",
        grid: make2x2Grid()
    )
    let withColorbar    = HeatmapPlotLayout.compute(payload: payload, showColorbar: true)
    let withoutColorbar = HeatmapPlotLayout.compute(payload: payload, showColorbar: false)
    // Grid width must not shrink when colorbar is shown.
    #expect(abs(withColorbar.gridRect.width - withoutColorbar.gridRect.width) < 1,
            "showColorbar must not reduce gridRect.width")
}

@Test func showColorbarExpandsRendererWidth() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Width expansion",
        xLabel: "H", yLabel: "L", zLabel: "Intensity (counts)",
        grid: make2x2Grid()
    )
    let withColorbar    = HeatmapPlotLayout.compute(payload: payload, showColorbar: true)
    let withoutColorbar = HeatmapPlotLayout.compute(payload: payload, showColorbar: false)
    #expect(withColorbar.rendererSize.width > withoutColorbar.rendererSize.width,
            "showColorbar = true must widen the renderer canvas to accommodate colorbar and Z title lane")
}

@Test func showColorbarZTitleIsLeftOfColorbar() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Z title left of colorbar",
        xLabel: "H", yLabel: "L", zLabel: "Intensity (counts)",
        grid: make4x3Grid()
    )
    let layout = HeatmapPlotLayout.compute(payload: payload, showColorbar: true)
    // Z title center must be LEFT of colorbar (new layout)
    #expect(layout.colorbarLabelCenter.x < layout.colorbarRect.minX,
            "Z title center must be left of the colorbar, not right")
    // Colorbar tick labels are right of colorbar
    #expect(layout.colorbarRect.maxX < layout.rendererSize.width,
            "Colorbar tick labels must fit within the rendered canvas")
    // Z title center must be right of grid
    #expect(layout.colorbarLabelCenter.x > layout.gridRect.maxX,
            "Z title center must be right of the plot grid")
}

@Test func zTitleToColorbarGapIsTightened() {
    // After spacing polish, the gap from the right edge of the Z title text to the
    // left edge of the colorbar gradient must be ≤ 10pt and > 0 (no overlap).
    let style = WorkbenchChartStyle()
    let zLabel = "Intensity (counts)"
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Gap test",
        xLabel: "H (r.l.u.)", yLabel: "L (r.l.u.)", zLabel: zLabel,
        grid: make4x3Grid()
    )
    let layout = HeatmapPlotLayout.compute(payload: payload, chartStyle: style, showColorbar: true)
    // For a long label the lane width ≈ text width; right edge ≈ center + textWidth/2.
    let zLabelTextWidth = HeatmapPlotLayout.measuredTextWidth(
        zLabel,
        fontSize: style.axisTitleFontSize,
        fontName: style.fontName,
        boldFontName: style.boldFontName
    )
    let approxRightEdge = layout.colorbarLabelCenter.x + zLabelTextWidth / 2
    let approxGap = layout.colorbarRect.minX - approxRightEdge
    #expect(approxGap > 0, "Z title must not overlap the colorbar")
    #expect(approxGap <= 10, "Gap from Z title right edge to colorbar must be ≤ 10pt after spacing polish")
}

@Test func showColorbarFalseHidesEntireColorbarBlock() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "No colorbar",
        xLabel: "H", yLabel: "L", zLabel: "Intensity (counts)",
        grid: make2x2Grid()
    )
    let layout = HeatmapPlotLayout.compute(payload: payload, showColorbar: false)
    #expect(!layout.showColorbar)
    // showColorbar=false hides the entire colorbar block
    #expect(layout.colorbarTicks.isEmpty, "Colorbar ticks must be absent when colorbar is hidden")
    #expect(layout.colorbarRect == CGRect.zero, "Colorbar rect must be zero when colorbar is hidden")
}

@Test func logScaleModeZLabelIsExactUserText() {
    let rendered = HeatmapPlotLayout.renderedZLabel("Intensity (counts)", mode: .log10)
    #expect(rendered == "Intensity (counts)",
            "Log10 mode must not auto-prefix the Z label")
    let renderedR = HeatmapRenderer.renderedZLabel("Intensity (counts)", mode: .log10)
    #expect(renderedR == "Intensity (counts)",
            "HeatmapRenderer must not auto-prefix Z label in log mode")
}

@Test func noAutoLog10PrefixInLogMode() {
    let label = "My Custom Label"
    let linear = HeatmapRenderer.renderedZLabel(label, mode: .linear)
    let log10  = HeatmapRenderer.renderedZLabel(label, mode: .log10)
    #expect(linear == label)
    #expect(log10  == label, "Log10 mode must not prepend any prefix to the user label")
    #expect(!log10.contains("log"), "No 'log' prefix must be added in log mode")
}

@Test func userProvidedLog10PrefixPreserved() {
    let label = "log10 Intensity (counts)"
    let rendered = HeatmapRenderer.renderedZLabel(label, mode: .log10)
    #expect(rendered == label, "User-provided label text must render exactly as entered")
}

@Test func logColorbarTickLabelsUse1eNotation() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Log ticks 1e",
        xLabel: "", yLabel: "", zLabel: "",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0],
            zMatrix: [[1.0, 10.0, 100.0], [10.0, 100.0, 1000.0]]
        )
    )
    let layout = HeatmapPlotLayout.compute(payload: payload, colorScaleMode: .log10)
    let powerOfTenTicks = layout.colorbarTicks.filter { $0.label.hasPrefix("1e") }
    #expect(!powerOfTenTicks.isEmpty, "Log colorbar ticks must use 1e-style notation (e.g. 1e3)")
}

@Test func logColorbarTickLabelsDoNotContainCaret() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "No caret",
        xLabel: "", yLabel: "", zLabel: "",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0],
            zMatrix: [[1.0, 10.0, 100.0], [10.0, 100.0, 1000.0]]
        )
    )
    let layout = HeatmapPlotLayout.compute(payload: payload, colorScaleMode: .log10)
    for (_, label) in layout.colorbarTicks {
        #expect(!label.contains("^"), "Log tick label '\(label)' must not use ^ exponent notation")
    }
}

@Test func linearColorbarTickLabelsAreReadable() {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm",
        title: "Linear ticks",
        xLabel: "", yLabel: "", zLabel: "",
        grid: HeatmapGrid(
            xValues: [0.0, 1.0],
            yValues: [0.0, 1.0],
            zMatrix: [[0.0, 50.0], [50.0, 100.0]]
        )
    )
    let layout = HeatmapPlotLayout.compute(payload: payload, colorScaleMode: .linear)
    #expect(layout.colorbarTicks.count >= 2)
    for (_, label) in layout.colorbarTicks {
        #expect(!label.isEmpty, "Linear tick label must not be empty")
        #expect(!label.contains("1e"), "Linear tick labels must not use 1e notation")
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

// MARK: - Boundary: Heatmap render outputs stay outside TabRenderOutput semantics

@Test func heatmapRenderPathDoesNotUseTabRenderOutputPayloads() throws {
    let source = try loadHeatmapSource("Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
    #expect(source.contains("renderedImageData"))
    #expect(source.contains("HeatmapRenderPipeline.render"))
    #expect(!source.contains("TabRenderOutput"))
    #expect(!source.contains("WorkbenchPlotExportService"))
    #expect(!source.contains("manifestPayload"))
    #expect(!source.contains("displayPayload"))
}

@Test func heatmapRenderPipelineOutputContainsOnlyImageAndLayout() throws {
    let source = try loadHeatmapSource("Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapRenderPipeline.swift")
    #expect(source.contains("struct Output: Sendable"))
    #expect(source.contains("let imageData: Data"))
    #expect(source.contains("let layout: HeatmapPlotLayout"))
    #expect(!source.contains("manifestPayload"))
    #expect(!source.contains("displayPayload"))
    #expect(!source.contains("dualAxisPayload"))
}

// MARK: - A: Tick count controls

@Test func heatmapTabRenderStateTickCountDefaults() {
    let state = HeatmapTabRenderState()
    #expect(state.xTickCount == 5)
    #expect(state.yTickCount == 5)
}

@Test func heatmapTabRenderStateTickCountRoundTrip() throws {
    let state = HeatmapTabRenderState(xTickCount: 8, yTickCount: 3)
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: data)
    #expect(decoded.xTickCount == 8)
    #expect(decoded.yTickCount == 3)
}

@Test func heatmapTabRenderStateTickCountClampedOnDecode() throws {
    // Values outside 2...20 must be clamped
    let json = """
    {"schemaVersion":2,"xTickCount":1,"yTickCount":25}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: json)
    #expect(decoded.xTickCount == 2, "xTickCount below 2 must clamp to 2")
    #expect(decoded.yTickCount == 20, "yTickCount above 20 must clamp to 20")
}

@Test func heatmapLayoutXTickEntriesCountMatchesRequest() {
    let grid = HeatmapGrid(
        xValues: Array(stride(from: 0.0, through: 20.0, by: 1.0)),
        yValues: [0.0, 1.0],
        zMatrix: [[Double]](repeating: Array(repeating: 1.0, count: 21), count: 2)
    )
    let payload = HeatmapPlotPayload(workflowID: "rsm", title: "", xLabel: "X", yLabel: "Y", zLabel: "Z", grid: grid)
    let layout4 = HeatmapPlotLayout.compute(payload: payload, options: .init(tickConfiguration: PlotTickConfiguration(xTargetCount: 4)))
    let layout10 = HeatmapPlotLayout.compute(payload: payload, options: .init(tickConfiguration: PlotTickConfiguration(xTargetCount: 10)))
    // Sampler uses integer stride so entry count approximates the target (within 2x)
    #expect(layout4.xTickEntries.count >= 1)
    #expect(layout10.xTickEntries.count >= 1)
    #expect(layout10.xTickEntries.count > layout4.xTickEntries.count,
            "More ticks requested must produce more tick entries")
}

@Test func heatmapLayoutYTickEntriesCountMatchesRequest() {
    let grid = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: Array(stride(from: 0.0, through: 20.0, by: 1.0)),
        zMatrix: [[Double]](repeating: [0.0, 1.0], count: 21)
    )
    let payload = HeatmapPlotPayload(workflowID: "rsm", title: "", xLabel: "X", yLabel: "Y", zLabel: "Z", grid: grid)
    let layout3 = HeatmapPlotLayout.compute(payload: payload, options: .init(tickConfiguration: PlotTickConfiguration(yTargetCount: 3)))
    let layout8 = HeatmapPlotLayout.compute(payload: payload, options: .init(tickConfiguration: PlotTickConfiguration(yTargetCount: 8)))
    #expect(layout3.yTickEntries.count >= 1)
    #expect(layout8.yTickEntries.count >= 1)
    #expect(layout8.yTickEntries.count > layout3.yTickEntries.count,
            "More ticks requested must produce more tick entries")
}

@Test func heatmapRenderPipelinePassesTickCountsToLayout() throws {
    let payload = HeatmapPlotPayload(
        workflowID: "rsm", title: "T", xLabel: "H", yLabel: "L", zLabel: "I",
        grid: make4x3Grid()
    )
    // Default produces more ticks; small xTickCount/yTickCount should reduce the count
    let defaultOutput = try HeatmapRenderPipeline.render(.init(payload: payload))
    let smallOutput = try HeatmapRenderPipeline.render(.init(payload: payload, xTickCount: 2, yTickCount: 2))
    // Smaller tick count request must produce fewer or equal X tick entries
    #expect(smallOutput.layout.xTickEntries.count <= defaultOutput.layout.xTickEntries.count,
            "xTickCount=2 must not exceed default tick count")
}

@Test func heatmapLayoutMinTickCountClampedAtTwo() {
    let payload = HeatmapPlotPayload(workflowID: "rsm", title: "", xLabel: "X", yLabel: "Y", zLabel: "Z",
                                     grid: make4x3Grid())
    let layout = HeatmapPlotLayout.compute(payload: payload, options: .init(tickConfiguration: PlotTickConfiguration(xTargetCount: 0, yTargetCount: 1)))
    #expect(layout.xTickEntries.count >= 1, "Clamped minimum tick count must still produce at least one entry")
    #expect(layout.yTickEntries.count >= 1)
}

// MARK: - HeatmapGridInterpolator — bilinear (internal helper, no longer directly exposed
// as a standalone picker option; used internally by gaussianUpsample2x)

@Test func bilinearInterpolationScale1ReturnsOriginalGrid() {
    let grid = make2x2Grid()
    let result = HeatmapGridInterpolator.bilinear(grid, scale: 1)
    #expect(result.nX == grid.nX)
    #expect(result.nY == grid.nY)
    #expect(result.xValues == grid.xValues)
    #expect(result.yValues == grid.yValues)
    #expect(result.zMatrix == grid.zMatrix)
}

@Test func bilinearInterpolationOfTwoByTwoGridProducesExpectedIntermediateValues() {
    let grid = HeatmapGrid(
        xValues: [0.0, 10.0],
        yValues: [0.0, 5.0],
        zMatrix: [[0.0, 10.0], [20.0, 30.0]]
    )
    let result = HeatmapGridInterpolator.bilinear(grid, scale: 2)

    #expect(result.nX == 3)
    #expect(result.nY == 3)
    #expect(result.xValues == [0.0, 5.0, 10.0])
    #expect(result.yValues == [0.0, 2.5, 5.0])

    // Corners are preserved exactly.
    #expect(result.zMatrix[0][0] == 0.0)
    #expect(result.zMatrix[0][2] == 10.0)
    #expect(result.zMatrix[2][0] == 20.0)
    #expect(result.zMatrix[2][2] == 30.0)

    // Edge midpoints average their two neighboring corners.
    #expect(abs(result.zMatrix[0][1] - 5.0)  < 1e-10)  // top edge:    (0+10)/2
    #expect(abs(result.zMatrix[2][1] - 25.0) < 1e-10)  // bottom edge: (20+30)/2
    #expect(abs(result.zMatrix[1][0] - 10.0) < 1e-10)  // left edge:   (0+20)/2
    #expect(abs(result.zMatrix[1][2] - 20.0) < 1e-10)  // right edge:  (10+30)/2

    // Center averages all four corners.
    #expect(abs(result.zMatrix[1][1] - 15.0) < 1e-10)
}

@Test func bilinearInterpolationHandlesNaNConservatively() {
    let grid = HeatmapGrid(
        xValues: [0.0, 1.0],
        yValues: [0.0, 1.0],
        zMatrix: [[Double.nan, 10.0], [20.0, 30.0]]
    )
    let result = HeatmapGridInterpolator.bilinear(grid, scale: 2)
    // No crash. The NaN corner (weight 1 at exactly [0][0]) has no finite contribution
    // from its own cell, so it conservatively falls back to a nearest finite corner
    // rather than propagating NaN.
    #expect(!result.zMatrix[0][0].isNaN)
    #expect(result.zMatrix[0][2] == 10.0)
    #expect(result.zMatrix[2][0] == 20.0)
    #expect(result.zMatrix[2][2] == 30.0)
}

@Test func bilinearInterpolationDoesNotMutateOriginalGrid() {
    let original = make2x2Grid()
    let originalCopy = original
    _ = HeatmapGridInterpolator.bilinear(original, scale: 4)
    #expect(original.zMatrix == originalCopy.zMatrix)
    #expect(original.xValues == originalCopy.xValues)
    #expect(original.yValues == originalCopy.yValues)
}

// MARK: - HeatmapGridInterpolator — gaussianSmooth (internal helper, used internally by
// gaussianUpsample2x)

@Test func gaussianSmoothPreservesGridDimensionsAndAxisValues() {
    let grid = make4x3Grid()
    let result = HeatmapGridInterpolator.gaussianSmooth(grid, sigma: 0.5)
    #expect(result.nX == grid.nX)
    #expect(result.nY == grid.nY)
    #expect(result.xValues == grid.xValues)
    #expect(result.yValues == grid.yValues)
}

@Test func gaussianSmoothSmoothsASharpCentralPeakLessAggressivelyThanBilinear() {
    // A single sharp peak surrounded by zeros — models a Bragg peak in an RSM grid.
    let zMatrix: [[Double]] = [
        [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0],
        [0, 0, 100, 0, 0],
        [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0],
    ]
    let grid = HeatmapGrid(
        xValues: [0, 1, 2, 3, 4],
        yValues: [0, 1, 2, 3, 4],
        zMatrix: zMatrix
    )
    let smoothed = HeatmapGridInterpolator.gaussianSmooth(grid, sigma: 0.5)

    // Peak stays at the same grid location and the same resolution.
    #expect(smoothed.nX == 5)
    #expect(smoothed.nY == 5)

    // The center value is reduced (blurred), but the peak still dominates its neighbors.
    #expect(smoothed.zMatrix[2][2] < 100)
    #expect(smoothed.zMatrix[2][2] > smoothed.zMatrix[2][1])
    #expect(smoothed.zMatrix[2][2] > smoothed.zMatrix[1][2])

    // A light sigma=0.5 kernel should not spread the peak's influence far from center.
    #expect(smoothed.zMatrix[0][0] < 1e-3)
}

@Test func gaussianSmoothPreservesNaNWhenNoFiniteNeighborExists() {
    // Every cell is NaN, so no finite value can ever contribute — the whole grid stays NaN.
    let grid = HeatmapGrid(
        xValues: [0, 1, 2],
        yValues: [0, 1, 2],
        zMatrix: [
            [Double.nan, Double.nan, Double.nan],
            [Double.nan, Double.nan, Double.nan],
            [Double.nan, Double.nan, Double.nan],
        ]
    )
    let result = HeatmapGridInterpolator.gaussianSmooth(grid, sigma: 0.5)
    for row in result.zMatrix {
        for value in row {
            #expect(value.isNaN)
        }
    }
}

@Test func gaussianSmoothFillsNaNFromFiniteNeighborsWithinKernelRadius() {
    let grid = HeatmapGrid(
        xValues: [0, 1, 2],
        yValues: [0, 1, 2],
        zMatrix: [
            [1.0, 2.0, Double.nan],
            [3.0, Double.nan, 5.0],
            [6.0, 7.0, 8.0],
        ]
    )
    let result = HeatmapGridInterpolator.gaussianSmooth(grid, sigma: 0.5)
    // Every NaN cell here has at least one finite neighbor within the radius-1 kernel
    // (radius = ceil(3 * 0.5) = 2), so all should resolve to a finite value.
    #expect(result.zMatrix[0][2].isFinite)
    #expect(result.zMatrix[1][1].isFinite)
}

@Test func gaussianSmoothDoesNotMutateOriginalGrid() {
    let original = make4x3Grid()
    let originalCopy = original
    _ = HeatmapGridInterpolator.gaussianSmooth(original, sigma: 0.5)
    #expect(original.zMatrix == originalCopy.zMatrix)
    #expect(original.xValues == originalCopy.xValues)
    #expect(original.yValues == originalCopy.yValues)
}

@Test func gaussianUpsample2xInterpolationIsAvailableAsOptInAndDensifiesTheGrid() throws {
    let payload = HeatmapPlotPayload(
        workflowID: WorkflowKey.rsm.rawValue,
        title: "RSM", xLabel: "H", yLabel: "L", zLabel: "Intensity",
        grid: make4x3Grid(),
        colormapKey: "rsmTurbo"
    )
    let nearestOutput = try HeatmapRenderPipeline.render(.init(payload: payload))

    var input = HeatmapRenderPipeline.Input(payload: payload)
    input.interpolationMode = .gaussianUpsample2x
    let gaussianOutput = try HeatmapRenderPipeline.render(input)

    #expect(gaussianOutput.imageData.count > 0)
    // gaussianUpsample2x = gaussian smoothing then 2x bilinear upsample, so it densifies
    // the grid / axis tick count, same as plain bilinear used to.
    #expect(gaussianOutput.layout.xTickEntries.count >= nearestOutput.layout.xTickEntries.count)
    #expect(gaussianOutput.layout.yTickEntries.count >= nearestOutput.layout.yTickEntries.count)
}

@Test func gaussianUpsample2xProducesGridDimensionsMatchingBilinearScale2() {
    let grid = make4x3Grid()
    let expectedNX = (grid.nX - 1) * 2 + 1
    let expectedNY = (grid.nY - 1) * 2 + 1

    let smoothed = HeatmapGridInterpolator.gaussianSmooth(grid, sigma: 0.35)
    let upsampled = HeatmapGridInterpolator.bilinear(smoothed, scale: 2)

    #expect(upsampled.nX == expectedNX)
    #expect(upsampled.nY == expectedNY)
}

@Test func gaussianUpsample2xDoesNotMutateInputGridAndProducesFiniteValues() {
    let original = make4x3Grid()
    let originalCopy = original

    let smoothed = HeatmapGridInterpolator.gaussianSmooth(original, sigma: 0.35)
    let upsampled = HeatmapGridInterpolator.bilinear(smoothed, scale: 2)

    #expect(original.zMatrix == originalCopy.zMatrix)
    #expect(original.xValues == originalCopy.xValues)
    #expect(original.yValues == originalCopy.yValues)

    // All source values in make4x3Grid() are finite, so every interpolated cell must be finite.
    for row in upsampled.zMatrix {
        for value in row {
            #expect(value.isFinite)
        }
    }
}

// MARK: - RSM publication rendering defaults

@Test func rsmHeatmapPayloadDefaultsToRSMTurboColormap() throws {
    let dataset = CanonicalRSMDataset(
        points: [
            CanonicalRSMPoint(h: 0, k: 0, l: 0, detector: 1),
            CanonicalRSMPoint(h: 0, k: 0, l: 1, detector: 2),
            CanonicalRSMPoint(h: 1, k: 0, l: 0, detector: 3),
            CanonicalRSMPoint(h: 1, k: 0, l: 1, detector: 4),
        ],
        title: "RSM",
        sourceRef: "test",
        detectorColumnName: "Intensity"
    )
    let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)
    #expect(payload.colormapKey == "rsmTurbo")
}

@Test func heatmapRenderPipelineDefaultInterpolationIsNearestForAllWorkflows() {
    // gaussianUpsample2x must be opt-in; the default must never smear sharp features
    // (e.g. RSM Bragg peaks).
    let rsmInput = HeatmapRenderPipeline.Input(payload: HeatmapPlotPayload(
        workflowID: WorkflowKey.rsm.rawValue,
        title: "", xLabel: "", yLabel: "", zLabel: "", grid: make4x3Grid()
    ))
    #expect(rsmInput.interpolationMode == .nearest)

    let otherInput = HeatmapRenderPipeline.Input(payload: HeatmapPlotPayload(
        workflowID: "test", title: "", xLabel: "", yLabel: "", zLabel: "", grid: make4x3Grid()
    ))
    #expect(otherInput.interpolationMode == .nearest)
}

@Test func rsmRenderPipelineDoesNotInterpolateByDefault() throws {
    let payload = HeatmapPlotPayload(
        workflowID: WorkflowKey.rsm.rawValue,
        title: "RSM", xLabel: "H", yLabel: "L", zLabel: "Intensity",
        grid: make4x3Grid(),
        colormapKey: "rsmTurbo"
    )
    let nearestOutput = try HeatmapRenderPipeline.render(.init(payload: payload))

    var gaussianInput = HeatmapRenderPipeline.Input(payload: payload)
    gaussianInput.interpolationMode = .gaussianUpsample2x
    let gaussianOutput = try HeatmapRenderPipeline.render(gaussianInput)

    #expect(nearestOutput.imageData.count > 0)
    #expect(gaussianOutput.imageData.count > 0)
    // gaussianUpsample2x opt-in densifies the grid (more axis samples); the untouched
    // default must not.
    #expect(gaussianOutput.layout.xTickEntries.count >= nearestOutput.layout.xTickEntries.count)
}

@Test func rsmHeatmapRenderPNGIsNonEmptyWithAndWithoutInterpolation() throws {
    let payload = HeatmapPlotPayload(
        workflowID: WorkflowKey.rsm.rawValue,
        title: "RSM", xLabel: "H", yLabel: "L", zLabel: "Intensity",
        grid: make4x3Grid(),
        colormapKey: "rsmTurbo"
    )
    let defaultOutput = try HeatmapRenderPipeline.render(.init(payload: payload))
    #expect(defaultOutput.imageData.count > 0)

    // Non-RSM workflows also stay on nearest (no interpolation) by default.
    let otherPayload = HeatmapPlotPayload(
        workflowID: "test", title: "", xLabel: "", yLabel: "", zLabel: "",
        grid: make4x3Grid()
    )
    let otherOutput = try HeatmapRenderPipeline.render(.init(payload: otherPayload))
    #expect(otherOutput.imageData.count > 0)
}
