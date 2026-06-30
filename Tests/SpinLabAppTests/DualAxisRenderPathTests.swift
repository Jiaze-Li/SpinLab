import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Helpers

private let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

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

@Test func dualAxisRendererHandlesNaNInSeriesGracefully() throws {
    let series = DualAxisPlotSeries(label: "NaN mix", x: [1, 2, 3, 4], y: [1, .nan, 3, 4])
    let payload = makePayload(leftSeries: [series])
    let data = try DualAxisChartRenderer().renderPNG(payload: payload)
    #expect(data.count > 0)
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
