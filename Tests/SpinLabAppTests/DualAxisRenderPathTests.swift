import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Helpers

private let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
private let identityPointToScreen: (Double, Double) -> CGPoint = { x, y in
    CGPoint(x: x, y: y)
}

private func makePayload(
    leftSeries: [DualAxisPlotSeries] = [],
    rightSeries: [DualAxisPlotSeries] = []
) -> DualAxisPlotPayload {
    DualAxisPlotPayload(
        workflowID: "test",
        workflowDisplayName: "Test",
        title: "Dual Axis Test",
        xLabel: "X",
        leftYLabel: "Left Y",
        rightYLabel: "Right Y",
        leftSeries: leftSeries,
        rightSeries: rightSeries
    )
}

private func makeLineSeries(label: String, xRange: ClosedRange<Double> = 0...10, yScale: Double = 1.0) -> DualAxisPlotSeries {
    let x = stride(from: xRange.lowerBound, through: xRange.upperBound, by: 1.0).map { $0 }
    let y = x.map { $0 * yScale }
    return DualAxisPlotSeries(label: label, x: x, y: y)
}

// MARK: - DualAxisPlotPayload Codable round-trip

@Test func dualAxisPayloadCodableRoundTrip() throws {
    let left = DualAxisPlotSeries(
        label: "Resistance",
        x: [1.0, 2.0, 3.0],
        y: [10.0, 11.0, 12.0],
        renderMode: .line,
        lineWidth: 2.5
    )
    let right = DualAxisPlotSeries(
        label: "Temperature",
        x: [1.0, 2.0, 3.0],
        y: [300.0, 310.0, 305.0],
        renderMode: .scatter
    )
    let original = DualAxisPlotPayload(
        schemaVersion: 1,
        workflowID: "wf-a",
        workflowDisplayName: "Workflow A",
        title: "R vs T",
        xLabel: "Field (Oe)",
        leftYLabel: "R (Ω)",
        rightYLabel: "T (K)",
        leftSeries: [left],
        rightSeries: [right],
        semanticParams: ["key": "val"],
        styleParams: ["lineWidth": "2"]
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DualAxisPlotPayload.self, from: data)

    #expect(decoded.schemaVersion == original.schemaVersion)
    #expect(decoded.workflowID == original.workflowID)
    #expect(decoded.workflowDisplayName == original.workflowDisplayName)
    #expect(decoded.title == original.title)
    #expect(decoded.xLabel == original.xLabel)
    #expect(decoded.leftYLabel == original.leftYLabel)
    #expect(decoded.rightYLabel == original.rightYLabel)
    #expect(decoded.leftSeries.count == 1)
    #expect(decoded.rightSeries.count == 1)
    #expect(decoded.leftSeries[0].label == "Resistance")
    #expect(decoded.leftSeries[0].renderMode == .line)
    #expect(decoded.rightSeries[0].label == "Temperature")
    #expect(decoded.rightSeries[0].renderMode == .scatter)
    #expect(decoded.semanticParams == original.semanticParams)
}

// MARK: - DualAxis display-state snapshot

@Test func dualAxisDisplayStateSnapshotCodableRoundTrip() throws {
    let snapshot = DualAxisDisplayStateSnapshot(
        titleOverride: "Title",
        xLabelOverride: "T (K)",
        leftYLabelOverride: "Left",
        rightYLabelOverride: "Right",
        axisRangeOverride: DualAxisAxisRangeOverride(
            xMin: 10,
            xMax: 300,
            leftYMin: -1,
            leftYMax: 1,
            rightYMin: 0,
            rightYMax: 100
        ),
        leftSeriesStyle: DualAxisSeriesVisualStyle(
            linePattern: .solid,
            markerShape: .square,
            markerFill: .open,
            colorRole: .leftAxisBlue
        ),
        rightSeriesStyle: DualAxisSeriesVisualStyle(
            linePattern: .dashed,
            markerShape: .circle,
            markerFill: .filled,
            colorRole: .rightAxisRed
        ),
        axisColorPolicy: .templatePaired
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(DualAxisDisplayStateSnapshot.self, from: data)

    #expect(decoded == snapshot)
    #expect(decoded.axisRangeOverride?.leftYMin == -1)
    #expect(decoded.leftSeriesStyle.markerShape == .square)
    #expect(decoded.rightSeriesStyle.linePattern == .dashed)
}

@Test func dualAxisDisplayStateAppliesLabelOverrides() {
    let payload = makePayload(leftSeries: [makeLineSeries(label: "L")])
    let snapshot = DualAxisDisplayStateSnapshot(
        titleOverride: "Override Title",
        xLabelOverride: "Override X",
        leftYLabelOverride: "Override Left",
        rightYLabelOverride: "Override Right"
    )

    let patched = snapshot.applying(to: payload)

    #expect(patched.title == "Override Title")
    #expect(patched.xLabel == "Override X")
    #expect(patched.leftYLabel == "Override Left")
    #expect(patched.rightYLabel == "Override Right")
}

@Test func dualAxisDefaultTemplateStylesArePaired() {
    let snapshot = DualAxisDisplayState().snapshot()

    #expect(snapshot.axisColorPolicy == .templatePaired)
    #expect(snapshot.leftSeriesStyle.colorRole == .leftAxisBlue)
    #expect(snapshot.rightSeriesStyle.colorRole == .rightAxisRed)
    #expect(snapshot.leftSeriesStyle.markerShape == .square)
    #expect(snapshot.leftSeriesStyle.markerFill == .open)
    #expect(snapshot.rightSeriesStyle.markerShape == .circle)
    #expect(snapshot.rightSeriesStyle.markerFill == .filled)
    #expect(snapshot.rightSeriesStyle.linePattern == .dashed)
}

@Test func dualAxisRangeReducerSetsClearsAndDropsEmptyState() {
    var range: DualAxisAxisRangeOverride? = nil

    range = dualAxisRangeOverrideByUpdating(range, bound: .xMin, value: -1)
    range = dualAxisRangeOverrideByUpdating(range, bound: .xMax, value: 11)
    range = dualAxisRangeOverrideByUpdating(range, bound: .leftYMin, value: -2)
    range = dualAxisRangeOverrideByUpdating(range, bound: .leftYMax, value: 12)

    #expect(range?.xMin == -1)
    #expect(range?.xMax == 11)
    #expect(range?.leftYMin == -2)
    #expect(range?.leftYMax == 12)

    range = dualAxisRangeOverrideByUpdating(range, bound: .xMin, value: nil)
    range = dualAxisRangeOverrideByUpdating(range, bound: .xMax, value: nil)
    range = dualAxisRangeOverrideByUpdating(range, bound: .leftYMin, value: nil)
    range = dualAxisRangeOverrideByUpdating(range, bound: .leftYMax, value: nil)

    #expect(range == nil)
}

@Test func dualAxisRangeReducerRejectsInvalidPairsAndNonFiniteValues() {
    let valid = DualAxisAxisRangeOverride(xMin: 0, xMax: 10, leftYMin: -1, leftYMax: 1)

    let invalidX = dualAxisRangeOverrideByUpdating(valid, bound: .xMax, value: -5)
    let invalidLeft = dualAxisRangeOverrideByUpdating(valid, bound: .leftYMin, value: 2)
    let nonFinite = dualAxisRangeOverrideByUpdating(valid, bound: .rightYMin, value: .infinity)

    #expect(invalidX == valid)
    #expect(invalidLeft == valid)
    #expect(nonFinite == valid)
}

// MARK: - DualAxisPlotLayout: independent left/right Y ranges

@Test func dualAxisLayoutIndependentYRanges() {
    let leftSeries = DualAxisPlotSeries(label: "Left", x: [0, 1, 2], y: [0, 1, 2])
    let rightSeries = DualAxisPlotSeries(label: "Right", x: [0, 1, 2], y: [100, 200, 300])
    let payload = makePayload(leftSeries: [leftSeries], rightSeries: [rightSeries])
    let layout = DualAxisPlotLayout.compute(payload: payload)

    #expect(layout.axisLeftYMax < 10, "Left Y max must be near 2, not mixed with right axis")
    #expect(layout.axisRightYMin > 50, "Right Y min must be near 100, not mixed with left axis")
    #expect(layout.axisLeftYMax < layout.axisRightYMin)
}

@Test func dualAxisLayoutAppliesManualRangesFromSnapshot() {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L")],
        rightSeries: [makeLineSeries(label: "R", yScale: 10)]
    )
    let snapshot = DualAxisDisplayStateSnapshot(
        axisRangeOverride: DualAxisAxisRangeOverride(
            xMin: -5,
            xMax: 15,
            leftYMin: -2,
            leftYMax: 20,
            rightYMin: 10,
            rightYMax: 200
        )
    )
    let layout = DualAxisPlotLayout.compute(payload: payload, displayState: snapshot)

    #expect(layout.axisXMin == -5)
    #expect(layout.axisXMax == 15)
    #expect(layout.axisLeftYMin == -2)
    #expect(layout.axisLeftYMax == 20)
    #expect(layout.axisRightYMin == 10)
    #expect(layout.axisRightYMax == 200)
}

@Test func dualAxisLayoutRejectsInvalidManualRangeByFallingBackToAuto() {
    let payload = makePayload(leftSeries: [makeLineSeries(label: "L")])
    let snapshot = DualAxisDisplayStateSnapshot(
        axisRangeOverride: DualAxisAxisRangeOverride(xMin: 10, xMax: 0)
    )
    let layout = DualAxisPlotLayout.compute(payload: payload, displayState: snapshot)

    #expect(layout.axisXMin == 0)
    #expect(layout.axisXMax == 10)
}

@Test func dualAxisLayoutOnlyLeftSeries() {
    let series = makeLineSeries(label: "L", yScale: 2.0)
    let payload = makePayload(leftSeries: [series], rightSeries: [])
    let layout = DualAxisPlotLayout.compute(payload: payload)

    #expect(layout.axisRightYMin == 0)
    #expect(layout.axisRightYMax == 1)
    #expect(layout.axisLeftYMin < layout.axisLeftYMax)
}

@Test func dualAxisLayoutOnlyRightSeries() {
    let series = makeLineSeries(label: "R", xRange: 0...5, yScale: 10.0)
    let payload = makePayload(leftSeries: [], rightSeries: [series])
    let layout = DualAxisPlotLayout.compute(payload: payload)

    #expect(layout.axisLeftYMin == 0)
    #expect(layout.axisLeftYMax == 1)
    #expect(layout.axisRightYMin < layout.axisRightYMax)
}

@Test func dualAxisLayoutPlotRectIsPositive() {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L")],
        rightSeries: [makeLineSeries(label: "R", yScale: 5)]
    )
    let layout = DualAxisPlotLayout.compute(payload: payload)

    #expect(layout.plotRect.width > 0)
    #expect(layout.plotRect.height > 0)
    #expect(layout.rendererSize.width > layout.plotRect.width)
    #expect(layout.rendererSize.height > layout.plotRect.height)
}

@Test func dualAxisLayoutTicksGeneratedForBothAxes() {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L", yScale: 1)],
        rightSeries: [makeLineSeries(label: "R", yScale: 100)]
    )
    let layout = DualAxisPlotLayout.compute(payload: payload)

    #expect(layout.xTicks.count >= 2)
    #expect(layout.leftYTicks.count >= 2)
    #expect(layout.rightYTicks.count >= 2)

    for tick in layout.leftYTicks {
        #expect(tick.value >= layout.axisLeftYMin - 1e-6)
        #expect(tick.value <= layout.axisLeftYMax + 1e-6)
    }
    for tick in layout.rightYTicks {
        #expect(tick.value >= layout.axisRightYMin - 1e-6)
        #expect(tick.value <= layout.axisRightYMax + 1e-6)
    }
}

// MARK: - DualAxisChartRenderer: PNG output

@Test func dualAxisRendererProducesNonEmptyPNGOneLeftOneRight() throws {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "Resistance", yScale: 1)],
        rightSeries: [makeLineSeries(label: "Temperature", yScale: 50)]
    )
    let data = try DualAxisChartRenderer().renderPNG(payload: payload)

    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func dualAxisRendererProducesNonEmptyPNGLeftOnly() throws {
    let payload = makePayload(leftSeries: [makeLineSeries(label: "L")])
    let data = try DualAxisChartRenderer().renderPNG(payload: payload)
    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func dualAxisRendererProducesNonEmptyPNGRightOnly() throws {
    let payload = makePayload(rightSeries: [makeLineSeries(label: "R", yScale: 100)])
    let data = try DualAxisChartRenderer().renderPNG(payload: payload)
    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func dualAxisPolylineSubpathsSplitOnMiddleNonFinitePoint() {
    let x: [Double] = [0, 1, 2, 3, 4]
    let y: [Double] = [0, 1, .nan, 3, 4]
    let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: identityPointToScreen)

    #expect(subpaths.count == 2)
    #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
    #expect(subpaths[1] == [CGPoint(x: 3, y: 3), CGPoint(x: 4, y: 4)])
}

@Test func dualAxisPolylineSubpathsTreatConsecutiveNonFiniteAsOneGap() {
    let x: [Double] = [0, 1, .nan, .nan, 4, 5]
    let y: [Double] = [0, 1, .nan, .nan, 4, 5]
    let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: identityPointToScreen)

    #expect(subpaths.count == 2)
    #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
    #expect(subpaths[1] == [CGPoint(x: 4, y: 4), CGPoint(x: 5, y: 5)])
}

@Test func dualAxisPolylineSubpathsTreatInfinityLikeNaN() {
    let x: [Double] = [0, 1, .infinity, 3, -.infinity, 5]
    let y: [Double] = [0, 1, 2, 3, 4, 5]
    let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: identityPointToScreen)

    #expect(subpaths.count == 3)
    #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
    #expect(subpaths[1] == [CGPoint(x: 3, y: 3)])
    #expect(subpaths[2] == [CGPoint(x: 5, y: 5)])
}

@Test func dualAxisPolylineSubpathsKeepAllFinitePointsTogether() {
    let x: [Double] = [0, 1, 2, 3]
    let y: [Double] = [0, 1, 2, 3]
    let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: identityPointToScreen)

    #expect(subpaths.count == 1)
    #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)])
}

@Test func dualAxisRendererHandlesNaNInSeriesGracefully() throws {
    let series = DualAxisPlotSeries(label: "NaN mix", x: [1, 2, 3, 4], y: [1, .nan, 3, 4])
    let payload = makePayload(leftSeries: [series])
    let data = try DualAxisChartRenderer().renderPNG(payload: payload)
    #expect(data.count > 0)
}

@Test func dualAxisRendererHandlesNaNGapWithoutBridging() throws {
    let left = DualAxisPlotSeries(label: "Left", x: [0, 1, 2, 3, 4], y: [0, 1, .nan, 3, 4])
    let right = makeLineSeries(label: "Right", yScale: 10)
    let data = try DualAxisChartRenderer().renderPNG(payload: makePayload(leftSeries: [left], rightSeries: [right]))

    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func dualAxisRendererHandlesInfiniteValuesWithoutBridging() throws {
    let left = DualAxisPlotSeries(label: "Left", x: [0, 1, .infinity, 3, -.infinity, 5], y: [0, 1, 2, 3, 4, 5])
    let right = makeLineSeries(label: "Right", yScale: 10)
    let data = try DualAxisChartRenderer().renderPNG(payload: makePayload(leftSeries: [left], rightSeries: [right]))

    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func dualAxisRendererHandlesScatterNaNGracefully() throws {
    let scatter = DualAxisPlotSeries(label: "Scatter", x: [0, 1, 2, 3], y: [0, .nan, 2, 3], renderMode: .scatter)
    let payload = makePayload(leftSeries: [scatter], rightSeries: [makeLineSeries(label: "Right", yScale: 10)])
    let data = try DualAxisChartRenderer().renderPNG(payload: payload)

    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

@Test func dualAxisRendererAcceptsTemplateSnapshotStyles() throws {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L")],
        rightSeries: [makeLineSeries(label: "R", yScale: 10)]
    )
    let snapshot = DualAxisDisplayStateSnapshot(
        leftSeriesStyle: DualAxisSeriesVisualStyle(linePattern: .solid, markerShape: .square, markerFill: .open, colorRole: .leftAxisBlue),
        rightSeriesStyle: DualAxisSeriesVisualStyle(linePattern: .dashed, markerShape: .circle, markerFill: .filled, colorRole: .rightAxisRed),
        axisColorPolicy: .templatePaired
    )

    let data = try DualAxisChartRenderer().renderPNG(payload: payload, displayState: snapshot)

    #expect(data.count > 0)
    #expect([UInt8](data.prefix(8)) == pngSignature)
}

// MARK: - DualAxisRenderPipeline: validation and warnings

@Test func dualAxisPipelineProducesOutputWithValidSeries() throws {
    let input = DualAxisRenderPipeline.Input(
        payload: makePayload(
            leftSeries: [makeLineSeries(label: "L")],
            rightSeries: [makeLineSeries(label: "R", yScale: 20)]
        )
    )
    let output = try DualAxisRenderPipeline.render(input)
    #expect(output.imageData.count > 0)
    #expect([UInt8](output.imageData.prefix(8)) == pngSignature)
    #expect(output.layout.plotRect.width > 0)
    #expect(output.warnings.isEmpty)
}

@Test func dualAxisPipelineWarnsAndSkipsXYCountMismatch() throws {
    let badSeries = DualAxisPlotSeries(label: "bad", x: [1, 2, 3], y: [1, 2])
    let goodSeries = makeLineSeries(label: "good", yScale: 1)
    let input = DualAxisRenderPipeline.Input(
        payload: makePayload(leftSeries: [badSeries], rightSeries: [goodSeries])
    )
    let output = try DualAxisRenderPipeline.render(input)

    #expect(output.warnings.contains(where: { $0.contains("bad") && $0.contains("skipped") }))
    #expect(output.imageData.count > 0)
}

@Test func dualAxisPipelineWarnsOnAllNonFiniteValues() throws {
    let infSeries = DualAxisPlotSeries(label: "inf", x: [.infinity, .infinity], y: [1, 2])
    let input = DualAxisRenderPipeline.Input(payload: makePayload(leftSeries: [infSeries]))
    let output = try DualAxisRenderPipeline.render(input)
    #expect(output.warnings.contains(where: { $0.contains("inf") && $0.contains("skipped") }))
}

@Test func dualAxisPipelineReadsDisplayStateSnapshot() throws {
    let snapshot = DualAxisDisplayStateSnapshot(
        titleOverride: "Snapshot Title",
        xLabelOverride: "Snapshot X",
        leftYLabelOverride: "Snapshot Left",
        rightYLabelOverride: "Snapshot Right",
        axisRangeOverride: DualAxisAxisRangeOverride(xMin: -1, xMax: 11, leftYMin: -2, leftYMax: 12)
    )
    let input = DualAxisRenderPipeline.Input(
        payload: makePayload(
            leftSeries: [makeLineSeries(label: "L")],
            rightSeries: [makeLineSeries(label: "R", yScale: 5)]
        ),
        displayState: snapshot
    )

    let output = try DualAxisRenderPipeline.render(input)

    #expect(output.imageData.count > 0)
    #expect(output.layout.axisXMin == -1)
    #expect(output.layout.axisXMax == 11)
    #expect(output.layout.axisLeftYMin == -2)
    #expect(output.layout.axisLeftYMax == 12)
}

@Test func dualAxisPipelineEmptyPayloadWarns() throws {
    let input = DualAxisRenderPipeline.Input(payload: makePayload())
    let output = try DualAxisRenderPipeline.render(input)
    #expect(output.warnings.contains(where: { $0.contains("no series") || $0.contains("empty") }))
    #expect(output.imageData.count > 0)
}

// MARK: - DualAxisPlotLayout: formatTick

@Test func dualAxisLayoutFormatTickZeroReturns0() {
    #expect(DualAxisPlotLayout.formatTick(0, step: 1) == "0")
    #expect(DualAxisPlotLayout.formatTick(1e-16, step: 1) == "0")
}

@Test func dualAxisLayoutFormatTickLargeStep() {
    let label = DualAxisPlotLayout.formatTick(50000, step: 10000)
    #expect(!label.isEmpty)
}

// MARK: - DualAxisPlotLayout: dataRange

@Test func dualAxisLayoutDataRangeFallsBackForEmpty() {
    let (lo, hi) = DualAxisPlotLayout.dataRange(from: [])
    #expect(lo == 0)
    #expect(hi == 1)
}

@Test func dualAxisLayoutDataRangeFiltersNaN() {
    let (lo, hi) = DualAxisPlotLayout.dataRange(from: [.nan, 2.0, .infinity, 5.0, -.infinity])
    #expect(lo == 2.0)
    #expect(hi == 5.0)
}

@Test func dualAxisLayoutDataRangeSingleValue() {
    let (lo, hi) = DualAxisPlotLayout.dataRange(from: [3.0])
    #expect(lo < hi)
}

// MARK: - TabRenderOutput: Temperature Dependence field contract

@Test func temperatureDependenceOutputHasDualAxisKindAndNilXYPayloads() {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L")],
        rightSeries: [makeLineSeries(label: "R", yScale: 10)]
    )
    let layout = DualAxisPlotLayout.compute(payload: payload)
    let output = TabRenderOutput(
        imageData: Data([0xAB]),
        renderKind: .dualAxis,
        layout: nil,
        manifestPayload: nil,
        displayPayload: nil,
        dualAxisLayout: layout,
        dualAxisPayload: payload
    )

    #expect(output.renderKind == .dualAxis)
    #expect(output.manifestPayload == nil)
    #expect(output.displayPayload == nil)
    #expect(output.dualAxisPayload != nil)
    #expect(output.dualAxisLayout != nil)
}

@Test func temperatureDependenceEmptyOutputHasDualAxisKindAndNilPayloads() {
    let output = TabRenderOutput(
        renderKind: .dualAxis,
        manifestPayload: nil,
        displayPayload: nil
    )

    #expect(output.renderKind == .dualAxis)
    #expect(output.manifestPayload == nil)
    #expect(output.displayPayload == nil)
    #expect(output.dualAxisPayload == nil)
}

// MARK: - Temperature Dependence store-level render path

@MainActor
private func makeTDScalingReadyStore() -> ThreeOmegaWorkspaceStore {
    let store = ThreeOmegaWorkspaceStore(workflowID: "3omega")
    store.ingestionResult = ThreeOmegaIngestionResult(
        fieldSweeps: [
            ThreeOmegaFieldSweepResult(
                temperatureK: 5.0, device: "0deg", sampleMetadata: nil, sampleID: "a",
                sourceFilePath: "/tmp/a.lvm", hField: [-1, 0, 1], r1omega: [-1, 0, 1],
                r3omega: [0, 0, 0], iRms: 1e-3, rahe1omega: 1.0, rahe1omegaWA: 1.0,
                hc1omega: nil, hc3omega: nil, v3omegaWindow: 2e-5, v3omegaFit: 2e-5
            ),
            ThreeOmegaFieldSweepResult(
                temperatureK: 10.0, device: "0deg", sampleMetadata: nil, sampleID: "a",
                sourceFilePath: "/tmp/b.lvm", hField: [-1, 0, 1], r1omega: [-1, 0, 1],
                r3omega: [0, 0, 0], iRms: 1e-3, rahe1omega: 1.2, rahe1omegaWA: 1.2,
                hc1omega: nil, hc3omega: nil, v3omegaWindow: 2.5e-5, v3omegaFit: 2.5e-5
            )
        ],
        rtResult: ThreeOmegaRTResult(device: "0deg", temperatureK: [5.0, 10.0], rxx: [100.0, 90.0]),
        device: "0deg",
        iRmsValues: [5.0: 1e-3, 10.0: 1e-3]
    )
    store.geometry = ThreeOmegaGeometry(lxx: 26, lxy: 21, dNm: 30)
    return store
}

@MainActor
private func waitForTDPayload(_ store: ThreeOmegaWorkspaceStore, attempts: Int = 40) async {
    for _ in 0..<attempts {
        if store.tabs.output(for: .temperatureDependence).dualAxisPayload != nil { return }
        try? await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitForDualAxisLegendLayout(
    _ store: ThreeOmegaWorkspaceStore,
    context: CoordinateContext,
    expectedPreviewRect: CGRect,
    attempts: Int = 80
) async {
    for _ in 0..<attempts {
        if let layout = store.tabs.output(for: .temperatureDependence).dualAxisLayout,
           let boxRect = layout.legendBoxRect {
            let renderedBoxRect = context.rendererToScreen(boxRect)
            if abs(renderedBoxRect.minX - expectedPreviewRect.minX) < 0.5,
               abs(renderedBoxRect.minY - expectedPreviewRect.minY) < 0.5,
               abs(renderedBoxRect.width - expectedPreviewRect.width) < 0.5,
               abs(renderedBoxRect.height - expectedPreviewRect.height) < 0.5 {
                return
            }
        }
        try? await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
@Test func temperatureDependenceOutputManifestPayloadIsNilWhenComplete() async {
    let store = makeTDScalingReadyStore()
    store.refreshTransportDerivedPlots(reason: "test")
    await waitForTDPayload(store)

    let out = store.tabs.output(for: .temperatureDependence)
    #expect(out.renderKind == .dualAxis)
    #expect(out.manifestPayload == nil)
    #expect(out.displayPayload == nil)
    #expect(out.dualAxisPayload != nil)
}

@MainActor
@Test func temperatureDependenceRightYLabelOverrideUpdatesRenderOutput() async {
    let store = makeTDScalingReadyStore()
    store.temperatureDependenceDisplayState.rightYLabelOverride = "Custom σxx"
    store.refreshTransportDerivedPlots(reason: "test")
    await waitForTDPayload(store)

    let payload = store.tabs.output(for: .temperatureDependence).dualAxisPayload
    #expect(payload?.rightYLabel == "Custom σxx")
    #expect(store.tabs.output(for: .temperatureDependence).manifestPayload == nil)
    #expect(store.tabs.output(for: .temperatureDependence).displayPayload == nil)
}

@MainActor
@Test func temperatureDependenceManualRangesUpdateDualAxisLayout() async {
    let store = makeTDScalingReadyStore()
    store.temperatureDependenceDisplayState.axisRangeOverride = DualAxisAxisRangeOverride(xMin: 5, xMax: 12)
    store.refreshTransportDerivedPlots(reason: "test")
    await waitForTDPayload(store)

    let layout = store.tabs.output(for: .temperatureDependence).dualAxisLayout
    #expect(layout?.axisXMin == 5)
    #expect(layout?.axisXMax == 12)
}

@MainActor
@Test func temperatureDependenceActiveRerenderDoesNotDropDualAxisDisplayState() async {
    let store = makeTDScalingReadyStore()
    store.tabs.activeTab = .temperatureDependence
    store.refreshTransportDerivedPlots(reason: "setup")
    await waitForTDPayload(store)

    store.temperatureDependenceDisplayState.rightYLabelOverride = "Preserved Label"
    store.tabs.setOutput(
        TabRenderOutput(renderKind: .dualAxis, manifestPayload: nil, displayPayload: nil),
        for: .temperatureDependence
    )
    store._rerenderActiveTab()
    await waitForTDPayload(store)

    let payload = store.tabs.output(for: .temperatureDependence).dualAxisPayload
    #expect(payload?.rightYLabel == "Preserved Label")
    #expect(store.temperatureDependenceDisplayState.rightYLabelOverride == "Preserved Label")
    #expect(store.tabs.output(for: .temperatureDependence).manifestPayload == nil)
    #expect(store.tabs.output(for: .temperatureDependence).displayPayload == nil)
}

@MainActor
@Test func temperatureDependenceLayoutCarriesLegendGeometry() async throws {
    let store = makeTDScalingReadyStore()
    store.tabs.activeTab = .temperatureDependence
    store.refreshTransportDerivedPlots(reason: "test")
    await waitForTDPayload(store)

    let layout = try #require(store.tabs.output(for: .temperatureDependence).dualAxisLayout)
    #expect(layout.legendBoxRect != nil)
    #expect(layout.legendOriginCG != nil)
}

@Test func dualAxisLegendPointUsesPlotRectOriginContract() throws {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L")],
        rightSeries: [makeLineSeries(label: "R")]
    )
    let legendPoint = CGPoint(x: 0.25, y: 0.75)
    let layout = DualAxisPlotLayout.compute(payload: payload, legendPoint: legendPoint)
    let expectedOrigin = CGPoint(
        x: layout.plotRect.minX + legendPoint.x * layout.plotRect.width,
        y: layout.plotRect.minY + legendPoint.y * layout.plotRect.height
    )
    let origin = try #require(layout.legendOriginCG)

    #expect(layout.legendBoxRect != nil)
    #expect(abs(origin.x - expectedOrigin.x) < 0.5)
    #expect(abs(origin.y - expectedOrigin.y) < 0.5)
}

@Test func dualAxisLegendPointRoundTripsThroughPlotRectNormalization() throws {
    let payload = makePayload(
        leftSeries: [makeLineSeries(label: "L")],
        rightSeries: [makeLineSeries(label: "R")]
    )
    let legendPoint = CGPoint(x: 0.25, y: 0.75)
    let layout = DualAxisPlotLayout.compute(payload: payload, legendPoint: legendPoint)
    let origin = try #require(layout.legendOriginCG)
    let normalized = CGPoint(
        x: (origin.x - layout.plotRect.minX) / layout.plotRect.width,
        y: (origin.y - layout.plotRect.minY) / layout.plotRect.height
    )

    #expect(abs(normalized.x - legendPoint.x) < 0.0001)
    #expect(abs(normalized.y - legendPoint.y) < 0.0001)
}

@MainActor
@Test func temperatureDependenceLegendDragUpdatesStateAndRerenderKeepsPosition() async throws {
    let store = makeTDScalingReadyStore()
    store.tabs.activeTab = .temperatureDependence
    store.refreshTransportDerivedPlots(reason: "test")
    await waitForTDPayload(store)

    let initialLayout = try #require(store.tabs.output(for: .temperatureDependence).dualAxisLayout)
    let geometry = try #require(initialLayout.legendDragGeometry)
    let context = CoordinateContext(
        rendererSize: geometry.rendererSize,
        displayRect: CGRect(x: 0, y: 0, width: 640, height: 480)
    )

    let start = context.rendererToScreen(geometry.currentLegendOriginCG)
    let current = CGPoint(x: start.x + 120, y: start.y - 50)
    let drag = try #require(PlotLegendDragEngine.dragStep(
        start: start,
        current: current,
        geometry: geometry,
        coordinateContext: context
    ))

    store.tabs.updateLegendPoint(drag.adjustedLegendPoint)
    store.rerenderTemperatureDependenceForDualAxisControlChange()
    await waitForTDPayload(store)
    await waitForDualAxisLegendLayout(store, context: context, expectedPreviewRect: drag.previewRect)

    let state = store.tabs.state(for: .temperatureDependence)
    #expect(state.legendPoint?.cgPoint == drag.adjustedLegendPoint)

    let layout = try #require(store.tabs.output(for: .temperatureDependence).dualAxisLayout)
    let boxRect = try #require(layout.legendBoxRect)
    let renderedBoxRect = context.rendererToScreen(boxRect)
    #expect(abs(renderedBoxRect.minX - drag.previewRect.minX) < 0.5)
    #expect(abs(renderedBoxRect.minY - drag.previewRect.minY) < 0.5)
    #expect(abs(renderedBoxRect.width - drag.previewRect.width) < 0.5)
    #expect(abs(renderedBoxRect.height - drag.previewRect.height) < 0.5)
    #expect(store.tabs.output(for: .temperatureDependence).imageData != nil)
    #expect(store.tabs.output(for: .temperatureDependence).pdfData != nil)
}
