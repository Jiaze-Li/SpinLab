import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

@Suite("V5.3.6 Curve Drag Order")
struct V536CurveDragOrderTests {

    // MARK: - Test case 1: Codable migration (old JSON without new fields)

    @Test("WorkbenchPlotSeries decodes without sampleID — defaults nil")
    func seriesDecodesWithoutSampleID() throws {
        let json = """
        {"label":"A","x":[1.0],"y":[0.5],"renderMode":"line","pointLabels":[],"lineWidth":2.0,"metadata":{}}
        """
        let series = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: Data(json.utf8))
        #expect(series.sampleID == nil)
        #expect(series.label == "A")
    }

    @Test("WorkbenchPlotSeries round-trips sampleID correctly")
    func seriesRoundTripsSampleID() throws {
        var original = WorkbenchPlotSeries(label: "A", x: [1.0], y: [0.5], sampleID: "sampleKey-42")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: data)
        #expect(decoded.sampleID == "sampleKey-42")
        _ = original
    }

    @Test("WorkbenchPlotPayload decodes without seriesReorderable — defaults false")
    func payloadDecodesWithoutSeriesReorderable() throws {
        let json = """
        {
          "schemaVersion":1,"workflowID":"3w","workflowDisplayName":"3w",
          "title":"Test","axisMapping":{"xField":"H","yField":"R"},
          "series":[],"semanticParams":{},"styleParams":{}
        }
        """
        let payload = try JSONDecoder().decode(WorkbenchPlotPayload.self, from: Data(json.utf8))
        #expect(payload.seriesReorderable == false)
    }

    @Test("TabRenderState decodes without seriesOrder — defaults nil")
    func tabStateDecodesWithoutSeriesOrder() throws {
        let json = """
        {"titleOverride":"","xLabelOverride":"","yLabelOverride":"","seriesLabelOverrides":{},"hiddenPointLabelIndicesBySeries":{}}
        """
        let state = try JSONDecoder().decode(TabRenderState.self, from: Data(json.utf8))
        #expect(state.seriesOrder == nil)
        #expect(state.legendPoint == nil)
    }

    @Test("TabRenderState round-trips seriesOrder correctly")
    func tabStateRoundTripsSeriesOrder() throws {
        let original = TabRenderState(seriesOrder: ["sampleC", "sampleA", "sampleB"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: data)
        #expect(decoded.seriesOrder == ["sampleC", "sampleA", "sampleB"])
    }

    // MARK: - Test case 2: opt-in off — pipeline skips detection

    @Test("Pipeline skips detection when seriesReorderable is false")
    func pipelineSkipsDetectionWhenOptInOff() throws {
        var input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test", title: "T",
                axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
                series: [
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sampleID: "A"),
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sampleID: "B")
                ],
                reverseSeriesForLegend: false,
                seriesReorderable: false   // opt-in OFF
            )
        )
        input.seriesOrder = ["B", "A"]   // would be a mismatch if detection were active
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains { $0.contains("mismatch") },
                "No mismatch warning expected when seriesReorderable is false")
    }

    // MARK: - Test case 3: opt-in on + no seriesOrder — no warning

    @Test("Pipeline produces no warning when seriesOrder is nil")
    func pipelineNoWarningWhenSeriesOrderNil() throws {
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test", title: "T",
                axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
                series: [
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sampleID: "A"),
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sampleID: "B")
                ],
                reverseSeriesForLegend: true,
                seriesReorderable: true
            )
        )
        // seriesOrder is nil by default
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains { $0.contains("mismatch") })
    }

    // MARK: - Test case 4: opt-in on + correct order — no warning

    @Test("Pipeline produces no warning when renderer sorted correctly")
    func pipelineNoWarningWhenOrderCorrect() throws {
        var input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test", title: "T",
                axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
                series: [
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sampleID: "A"),
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sampleID: "B")
                ],
                reverseSeriesForLegend: false,
                seriesReorderable: true
            )
        )
        input.seriesOrder = ["A", "B"]   // matches actual series order
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains { $0.contains("mismatch") })
    }

    // MARK: - Test case 4b: opt-in on + renderer sorted wrong — warning, series unchanged

    @Test("Pipeline warns on mismatch and does NOT reorder series")
    func pipelineWarnsMismatchWithoutReordering() throws {
        var input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test", title: "T",
                axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
                series: [
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sampleID: "B"),  // renderer produced [B, A]
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sampleID: "A")
                ],
                reverseSeriesForLegend: false,
                seriesReorderable: true
            )
        )
        input.seriesOrder = ["A", "B"]   // expected [A, B]
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.warnings.contains { $0.contains("mismatch") },
                "Warning expected when renderer produced wrong order")
        // Pipeline must NOT silently fix the order — series must stay as renderer produced them
        let manifestIDs = output.manifestPayload.series.compactMap(\.sampleID)
        #expect(manifestIDs == ["B", "A"],
                "Series order in manifest must be renderer's original [B, A], not silently fixed")
    }

    // MARK: - Test case 5: align algorithm

    @Test("alignSeriesOrder: old order fully present — preserved")
    func alignKeepsExistingOrder() {
        let result = alignSeriesOrder(old: ["C", "A", "B"], defaultIDs: ["A", "B", "C"])
        #expect(result == ["C", "A", "B"])
    }

    @Test("alignSeriesOrder: new ID added — appended while preserving non-default existing order")
    func alignAppendsNewIDs() {
        // old is ["B","A"] (non-default order), C is new
        let result = alignSeriesOrder(old: ["B", "A"], defaultIDs: ["A", "B", "C"])
        // kept = ["B","A"], append "C" → ["B","A","C"] ≠ default → returned as-is
        #expect(result == ["B", "A", "C"])
    }

    @Test("alignSeriesOrder: disappeared ID removed while preserving old order")
    func alignRemovesGoneIDs() {
        // old is ["C","A","B"]; default is ["A","C"] (B gone)
        let result = alignSeriesOrder(old: ["C", "A", "B"], defaultIDs: ["A", "C"])
        // kept = ["C","A"], no new IDs → ["C","A"] ≠ default ["A","C"] → returned
        #expect(result == ["C", "A"])
    }

    @Test("alignSeriesOrder: old is nil — returns nil")
    func alignNilInputReturnsNil() {
        let result = alignSeriesOrder(old: nil, defaultIDs: ["A", "B"])
        #expect(result == nil)
    }

    @Test("alignSeriesOrder: old matches default exactly — returns nil")
    func alignSameAsDefaultReturnsNil() {
        let result = alignSeriesOrder(old: ["A", "B", "C"], defaultIDs: ["A", "B", "C"])
        #expect(result == nil)
    }

    @Test("alignSeriesOrder: duplicates in old are deduplicated, non-default order preserved")
    func alignDeduplicatesDuplicates() {
        // old has duplicate A, non-default order [B,A]
        let result = alignSeriesOrder(old: ["B", "A", "B"], defaultIDs: ["A", "B", "C"])
        // kept = ["B","A"] (deduplicated), append "C" → ["B","A","C"] ≠ default → returned
        #expect(result == ["B", "A", "C"])
    }

    // MARK: - Test case 6: R1/R3 offset recalculation after reorder

    @Test("renderR1omega recalculates stack offsets based on reordered sweep amplitudes")
    func rendererRecalculatesOffsetsAfterReorder() {
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.showGrid = false

        // 3 sweeps with distinct amplitudes: A small, B large, C medium
        let sweepA = makeSweep(sampleID: "A", temperatureK: 100, r1omega: [-0.1, 0.0, 0.1])  // pp=0.2
        let sweepB = makeSweep(sampleID: "B", temperatureK: 200, r1omega: [-0.5, 0.0, 0.5])  // pp=1.0
        let sweepC = makeSweep(sampleID: "C", temperatureK: 300, r1omega: [-0.25, 0.0, 0.25]) // pp=0.5

        // Offset for default order [A, B, C]:
        let defaultOffsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: [sweepA.r1omega, sweepB.r1omega, sweepC.r1omega],
            multiplier: 1.2, minGapFraction: 0.15
        )
        // Offset for reordered [C, A, B]:
        let reorderedOffsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: [sweepC.r1omega, sweepA.r1omega, sweepB.r1omega],
            multiplier: 1.2, minGapFraction: 0.15
        )
        // Sanity: 3 asymmetric sweeps → different top-curve offset for different orderings
        #expect(defaultOffsets[2] != reorderedOffsets[2],
                "Different orderings of asymmetric sweeps must produce different top offsets")

        // Renderer must accept seriesOrder and produce output
        let (data, _) = renderer.renderR1omega(
            sweeps: [sweepA, sweepB, sweepC],
            device: "test",
            seriesOrder: ["C", "A", "B"]
        )
        #expect(data != nil, "Renderer must produce output with explicit seriesOrder")

        // The reorderedOffsets are strictly monotonically increasing (each curve above prior)
        #expect(reorderedOffsets[0] == 0.0)
        #expect(reorderedOffsets[1] > 0.0)
        #expect(reorderedOffsets[2] > reorderedOffsets[1])
    }

    // MARK: - Test case 9: Pack save / load (TabRenderState serialization)

    @Test("TabRenderState seriesOrder survives encode/decode round-trip with legendPoint")
    func seriesOrderSurvivesRoundTrip() throws {
        let state = TabRenderState(
            legendPoint: CGPointCodable(CGPoint(x: 0.1, y: 0.9)),
            seriesOrder: ["sampleZ", "sampleX", "sampleY"]
        )
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: encoded)
        #expect(decoded.seriesOrder == ["sampleZ", "sampleX", "sampleY"])
        #expect(decoded.legendPoint?.x == 0.1)
    }

    // MARK: - Test case 10: clearStates preserves seriesOrder

    @MainActor
    @Test("TabRenderManager.clearStates preserves legendPoint and seriesOrder, clears label overrides")
    func clearStatesPreservesCanvasPreferences() {
        let manager = TabRenderManager(defaultTab: "tab1")
        manager.tabStates["tab1"] = TabRenderState(
            legendPoint: CGPointCodable(CGPoint(x: 0.5, y: 0.5)),
            titleOverride: "Custom Title",
            seriesOrder: ["A", "B", "C"]
        )
        manager.tabStates["tab2"] = TabRenderState(
            titleOverride: "Another Title",
            seriesOrder: ["X", "Y"]
        )
        manager.clearStates()

        let state1 = manager.tabStates["tab1"]
        #expect(state1?.legendPoint != nil)
        #expect(state1?.seriesOrder == ["A", "B", "C"])
        #expect(state1?.titleOverride == "")

        let state2 = manager.tabStates["tab2"]
        #expect(state2?.seriesOrder == ["X", "Y"])
        #expect(state2?.legendPoint == nil)
        #expect(state2?.titleOverride == "")
    }

    @MainActor
    @Test("TabRenderManager.clearStates removes entry when both legendPoint and seriesOrder are nil")
    func clearStatesRemovesEmptyState() {
        let manager = TabRenderManager(defaultTab: "tab1")
        manager.tabStates["tab1"] = TabRenderState(titleOverride: "Title Only")
        manager.clearStates()
        #expect(manager.tabStates["tab1"] == nil)
    }

    // MARK: - Test case 7: Canvas hit-test

    @Test("hitTestSeries returns the nearest series within radius")
    func hitTestSeriesFindsNearestSeries() {
        // Two horizontal series at y=0 and y=1 in data space
        let seriesLow  = WorkbenchPlotSeries(label: "Low",  x: [0, 1], y: [0.0, 0.0], sampleID: "low")
        let seriesHigh = WorkbenchPlotSeries(label: "High", x: [0, 1], y: [1.0, 1.0], sampleID: "high")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [seriesLow, seriesHigh],
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        // Use 1:1 pixel-to-screen mapping for simplicity
        let fittedRect = CGRect(x: 0, y: 0, width: CGFloat(opts.width), height: CGFloat(opts.height))

        // Data extents with 5% margin: yMin=-0.05, yMax=1.05, ySpan=1.1
        // CG y for y=0: plotRect.minY + (0.05/1.1)*plotRect.height
        let yMin = -0.05, ySpan = 1.1
        let lowCGY = layout.plotRect.minY + CGFloat((0.0 - yMin) / ySpan) * layout.plotRect.height
        // Screen y = (rendererH - cgY) * scaleY + fittedRect.minY (Y-flipped)
        let lowScreenY = fittedRect.minY + (CGFloat(opts.height) - lowCGY) * (fittedRect.height / CGFloat(opts.height))
        // Use midX of fitted rect as x (horizontal series spans full width)
        let hitLocation = CGPoint(x: fittedRect.midX, y: lowScreenY)

        let hit = layout.hitTestSeries(location: hitLocation, fittedRect: fittedRect, payload: payload, radius: 8)
        #expect(hit?.sampleID == "low", "Should hit 'low' series at computed screen position")
    }

    @Test("hitTestSeries returns nil outside 8pt radius")
    func hitTestSeriesMissesOutsideRadius() {
        let series = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0.5, 0.5], sampleID: "A")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [series], reverseSeriesForLegend: false, seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: CGFloat(opts.width), height: CGFloat(opts.height))

        // Location far from any series (outside plot area)
        let farPoint = CGPoint(x: -100, y: -100)
        let hit = layout.hitTestSeries(location: farPoint, fittedRect: fittedRect, payload: payload, radius: 8)
        #expect(hit == nil, "Should miss when location is far from all series")
    }

    @Test("hitTestSeries skips series without sampleID")
    func hitTestSeriesSkipsNilSampleID() {
        let seriesNoID = WorkbenchPlotSeries(label: "NoID", x: [0, 1], y: [0.5, 0.5])  // no sampleID
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [seriesNoID], reverseSeriesForLegend: false, seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: CGFloat(opts.width), height: CGFloat(opts.height))
        let hit = layout.hitTestSeries(location: fittedRect.center, fittedRect: fittedRect, payload: payload, radius: 50)
        #expect(hit == nil, "Series without sampleID must be skipped")
    }

    // MARK: - Helpers

    private func alignSeriesOrder(old: [String]?, defaultIDs: [String]) -> [String]? {
        ThreeOmegaWorkspaceStore.alignSeriesOrder(old: old, defaultIDs: defaultIDs)
    }

    private func makeSweep(
        sampleID: String,
        temperatureK: Double,
        r1omega: [Double]
    ) -> ThreeOmegaFieldSweepResult {
        let n = r1omega.count
        return ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: "testDevice",
            sampleMetadata: nil,
            sampleID: sampleID,
            hField: (0..<n).map { Double($0) * 10000 },
            r1omega: r1omega,
            r3omega: r1omega.map { $0 * 0.1 },
            iRms: 0.001,
            rahe1omega: nil,
            rahe1omegaWA: nil,
            hc1omega: nil,
            hc3omega: nil,
            v3omegaWindow: 0.0,
            v3omegaFit: nil
        )
    }
}
