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
        let original = WorkbenchPlotSeries(label: "A", x: [1.0], y: [0.5], sampleID: "sampleKey-42")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: data)
        #expect(decoded.sampleID == "sampleKey-42")
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
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sourceRef: "/tmp/A.csv", sampleID: "A"),
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sourceRef: "/tmp/B.csv", sampleID: "B")
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
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sourceRef: "/tmp/A.csv", sampleID: "A"),
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sourceRef: "/tmp/B.csv", sampleID: "B")
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
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sourceRef: "/tmp/A.csv", sampleID: "A"),
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sourceRef: "/tmp/B.csv", sampleID: "B")
                ],
                reverseSeriesForLegend: false,
                seriesReorderable: true
            )
        )
        input.seriesOrder = ["/tmp/A.csv", "/tmp/B.csv"]   // matches actual series order
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
                    WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sourceRef: "/tmp/B.csv", sampleID: "B"),  // renderer produced [B, A]
                    WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sourceRef: "/tmp/A.csv", sampleID: "A")
                ],
                reverseSeriesForLegend: false,
                seriesReorderable: true
            )
        )
        input.seriesOrder = ["/tmp/A.csv", "/tmp/B.csv"]   // expected [A, B]
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.warnings.contains { $0.contains("mismatch") },
                "Warning expected when renderer produced wrong order")
        // Pipeline must NOT silently fix the order — series must stay as renderer produced them
        let manifestIDs = output.manifestPayload.series.compactMap(\.sourceRef)
        #expect(manifestIDs == ["/tmp/B.csv", "/tmp/A.csv"],
                "Series order in manifest must be renderer's original [B, A], not silently fixed")
    }

    @Test("Pipeline legend order follows the updated series order")
    func pipelineLegendOrderFollowsUpdatedSeriesOrder() throws {
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test",
                workflowDisplayName: "test",
                title: "T",
                axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
                series: [
                    WorkbenchPlotSeries(label: "Bottom", x: [0, 1], y: [0, 1], sourceRef: "/tmp/bottom.csv", sampleID: "bottom"),
                    WorkbenchPlotSeries(label: "Middle", x: [0, 1], y: [1, 2], sourceRef: "/tmp/middle.csv", sampleID: "middle"),
                    WorkbenchPlotSeries(label: "Top", x: [0, 1], y: [2, 3], sourceRef: "/tmp/top.csv", sampleID: "top")
                ],
                reverseSeriesForLegend: true,
                seriesReorderable: true
            ),
            seriesOrder: ["/tmp/bottom.csv", "/tmp/middle.csv", "/tmp/top.csv"]
        )
        let output = try WorkbenchRenderPipeline.render(input)
        let manifestIDs = output.manifestPayload.series.compactMap(\.sourceRef)
        #expect(manifestIDs == ["/tmp/bottom.csv", "/tmp/middle.csv", "/tmp/top.csv"])
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

    @MainActor
    @Test("R(1ω) field sweep render recalculates stack offsets based on reordered sweep amplitudes")
    func rendererRecalculatesOffsetsAfterReorder() {
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.showGrid = false

        // 3 sweeps with distinct amplitudes: A small, B large, C medium
        let sweepA = makeSweep(sampleID: "A", temperatureK: 100, r1omega: [-0.1, 0.0, 0.1], sourceFilePath: "/tmp/A.csv")  // pp=0.2
        let sweepB = makeSweep(sampleID: "B", temperatureK: 200, r1omega: [-0.5, 0.0, 0.5], sourceFilePath: "/tmp/B.csv")  // pp=1.0
        let sweepC = makeSweep(sampleID: "C", temperatureK: 300, r1omega: [-0.25, 0.0, 0.25], sourceFilePath: "/tmp/C.csv") // pp=0.5

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
        let (data, _, _, _, _) = ThreeOmegaFieldSweepRenderRoute.renderR1omegaViaSharedRoute(
            renderer: renderer,
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

    @Test("Series Order panel displays top-to-bottom visual stack order")
    func seriesOrderPanelDisplaysTopToBottomStackOrder() {
        let internalRows = [
            SeriesOrderRow(identityKey: "0", sampleID: "0", sourceRef: "/tmp/0.csv", label: "0", originalIndex: 0),
            SeriesOrderRow(identityKey: "30", sampleID: "30", sourceRef: "/tmp/30.csv", label: "30", originalIndex: 1),
            SeriesOrderRow(identityKey: "90", sampleID: "90", sourceRef: "/tmp/90.csv", label: "90", originalIndex: 2),
            SeriesOrderRow(identityKey: "120", sampleID: "120", sourceRef: "/tmp/120.csv", label: "120", originalIndex: 3),
            SeriesOrderRow(identityKey: "180", sampleID: "180", sourceRef: "/tmp/180.csv", label: "180", originalIndex: 4)
        ]

        let displayed = WorkbenchSeriesOrderPanel.presentedRows(from: internalRows)
        #expect(displayed.map(\.identityKey) == ["180", "120", "90", "30", "0"])
        #expect(displayed.map(\.label) == ["180", "120", "90", "30", "0"])
    }

    @Test("Series Order panel preserves explicit bottom-to-top order")
    func seriesOrderPanelPreservesExplicitOrder() {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Top label", x: [0], y: [0], sourceRef: "/tmp/top.csv", sampleID: "top"),
                WorkbenchPlotSeries(label: "Middle label", x: [0], y: [0], sourceRef: "/tmp/middle.csv", sampleID: "middle"),
                WorkbenchPlotSeries(label: "Bottom label", x: [0], y: [0], sourceRef: "/tmp/bottom.csv", sampleID: "bottom")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let rows = WorkbenchSeriesOrderPanel.makeRows(
            payload: payload,
            currentSeriesOrder: ["bottom", "middle", "top"]
        )
        #expect(rows.map(\.sampleID) == ["bottom", "middle", "top"])
    }

    @Test("Series Order panel keys duplicate sampleIDs by sourceRef")
    func seriesOrderPanelKeysDuplicateSampleIDsBySourceRef() {
        // payload in bottom-to-top order (matches manifest format after PR127 fix)
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Bottom curve", x: [0], y: [0], sourceRef: "/tmp/bottom.csv", sampleID: "sample-2"),
                WorkbenchPlotSeries(label: "Middle curve", x: [0], y: [0], sourceRef: "/tmp/middle.csv", sampleID: "sample-1"),
                WorkbenchPlotSeries(label: "Top curve", x: [0], y: [0], sourceRef: "/tmp/top.csv", sampleID: "sample-1")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let rows = WorkbenchSeriesOrderPanel.makeRows(payload: payload, currentSeriesOrder: nil)
        #expect(rows.map(\.label) == ["Bottom curve", "Middle curve", "Top curve"])
        #expect(rows.map(\.identityKey) == ["/tmp/bottom.csv", "/tmp/middle.csv", "/tmp/top.csv"])
        #expect(rows.map(\.sourceRef) == ["/tmp/bottom.csv", "/tmp/middle.csv", "/tmp/top.csv"])
        #expect(Set(rows.map(\.identityKey)).count == 3)
    }

    @Test("Series Order panel commits unique identity keys")
    func seriesOrderPanelCommitsUniqueIdentityKeys() {
        // payload in bottom-to-top order (matches manifest format after PR127 fix)
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Bottom curve", x: [0], y: [0], sourceRef: "/tmp/bottom.csv", sampleID: "sample-2"),
                WorkbenchPlotSeries(label: "Middle curve", x: [0], y: [0], sourceRef: "/tmp/middle.csv", sampleID: "sample-1"),
                WorkbenchPlotSeries(label: "Top curve", x: [0], y: [0], sourceRef: "/tmp/top.csv", sampleID: "sample-1")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let rows = WorkbenchSeriesOrderPanel.makeRows(payload: payload, currentSeriesOrder: nil)
        let committedOrder = rows.map(\.identityKey)
        #expect(committedOrder == ["/tmp/bottom.csv", "/tmp/middle.csv", "/tmp/top.csv"])
        #expect(Set(committedOrder).count == committedOrder.count)
    }

    @Test("Series Order panel honors sourceRef order for duplicate sampleIDs")
    func seriesOrderPanelHonorsSourceRefOrderForDuplicateSampleIDs() {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Top curve", x: [0], y: [0], sourceRef: "/tmp/top.csv", sampleID: "sample-1"),
                WorkbenchPlotSeries(label: "Middle curve", x: [0], y: [0], sourceRef: "/tmp/middle.csv", sampleID: "sample-1"),
                WorkbenchPlotSeries(label: "Bottom curve", x: [0], y: [0], sourceRef: "/tmp/bottom.csv", sampleID: "sample-2")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let rows = WorkbenchSeriesOrderPanel.makeRows(
            payload: payload,
            currentSeriesOrder: ["/tmp/middle.csv", "/tmp/top.csv", "/tmp/bottom.csv"]
        )
        #expect(rows.map(\.identityKey) == ["/tmp/middle.csv", "/tmp/top.csv", "/tmp/bottom.csv"])
        #expect(rows.map(\.label) == ["Middle curve", "Top curve", "Bottom curve"])
    }

    @Test("Series Order panel commits visual moves back to bottom-to-top order")
    func seriesOrderPanelCommitsVisualMovesBackToBottomToTopOrder() {
        let internalRows = [
            SeriesOrderRow(identityKey: "0", sampleID: "0", sourceRef: "/tmp/0.csv", label: "0", originalIndex: 0),
            SeriesOrderRow(identityKey: "30", sampleID: "30", sourceRef: "/tmp/30.csv", label: "30", originalIndex: 1),
            SeriesOrderRow(identityKey: "90", sampleID: "90", sourceRef: "/tmp/90.csv", label: "90", originalIndex: 2),
            SeriesOrderRow(identityKey: "120", sampleID: "120", sourceRef: "/tmp/120.csv", label: "120", originalIndex: 3),
            SeriesOrderRow(identityKey: "180", sampleID: "180", sourceRef: "/tmp/180.csv", label: "180", originalIndex: 4)
        ]

        let displayed = WorkbenchSeriesOrderPanel.presentedRows(from: internalRows)
        let movedDisplayed = WorkbenchSeriesOrderPanel.reorderedRows(
            displayed,
            draggedKey: "180",
            targetKey: "120",
            dropLocationX: 0.8
        )
        let committed = WorkbenchSeriesOrderPanel.internalRows(fromPresentedRows: movedDisplayed)
        #expect(committed.map(\.identityKey) == ["0", "30", "90", "180", "120"])
    }

    @Test("Series Order chip drag reorders before or after target")
    func seriesOrderChipDragReordersBeforeOrAfterTarget() {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Bottom curve", x: [0], y: [0], sourceRef: "/tmp/bottom.csv", sampleID: "sample-2"),
                WorkbenchPlotSeries(label: "Middle curve", x: [0], y: [0], sourceRef: "/tmp/middle.csv", sampleID: "sample-1"),
                WorkbenchPlotSeries(label: "Top curve", x: [0], y: [0], sourceRef: "/tmp/top.csv", sampleID: "sample-1")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        // reorderedRows operates on the displayed (visual top-to-bottom) rows — match production usage
        let internalRows = WorkbenchSeriesOrderPanel.makeRows(payload: payload, currentSeriesOrder: nil)
        let displayedRows = WorkbenchSeriesOrderPanel.presentedRows(from: internalRows)

        let dragged = WorkbenchSeriesOrderPanel.reorderedRows(
            displayedRows,
            draggedKey: "/tmp/top.csv",
            targetKey: "/tmp/bottom.csv",
            dropLocationX: 0.2
        )
        #expect(dragged.map(\.identityKey) == ["/tmp/middle.csv", "/tmp/top.csv", "/tmp/bottom.csv"])

        let after = WorkbenchSeriesOrderPanel.reorderedRows(
            displayedRows,
            draggedKey: "/tmp/top.csv",
            targetKey: "/tmp/bottom.csv",
            dropLocationX: 0.8
        )
        #expect(after.map(\.identityKey) == ["/tmp/middle.csv", "/tmp/bottom.csv", "/tmp/top.csv"])
    }

    @Test("Planner-backed field-sweep ordering preserves duplicate sampleIDs distinctly")
    func manifestOrderedFieldSweepsPreservesDuplicateSampleIDsDistinctly() {
        let sweepTop = makeSweep(
            sampleID: "sample-1",
            temperatureK: 300,
            r1omega: [-0.1, 0.0, 0.1],
            sourceFilePath: "/tmp/top.csv"
        )
        let sweepMiddle = makeSweep(
            sampleID: "sample-1",
            temperatureK: 200,
            r1omega: [-0.2, 0.0, 0.2],
            sourceFilePath: "/tmp/middle.csv"
        )
        let sweepBottom = makeSweep(
            sampleID: "sample-2",
            temperatureK: 100,
            r1omega: [-0.3, 0.0, 0.3],
            sourceFilePath: "/tmp/bottom.csv"
        )

        let ordered = ThreeOmegaWorkspaceStore.manifestOrderedFieldSweeps(
            [sweepTop, sweepMiddle, sweepBottom],
            seriesOrder: ["/tmp/middle.csv", "/tmp/top.csv", "/tmp/bottom.csv"]
        )
        #expect(ordered.map(\.sourceFilePath) == ["/tmp/middle.csv", "/tmp/top.csv", "/tmp/bottom.csv"])
        #expect(ordered.map(\.sampleID) == ["sample-1", "sample-1", "sample-2"])
    }

    @Test("WorkbenchRenderPipeline preserves sourceRef order for duplicate sampleIDs")
    func pipelinePreservesSourceRefOrderForDuplicateSampleIDs() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Middle curve", x: [0, 1], y: [1, 2], sourceRef: "/tmp/middle.csv", sampleID: "sample-1"),
                WorkbenchPlotSeries(label: "Top curve", x: [0, 1], y: [0, 1], sourceRef: "/tmp/top.csv", sampleID: "sample-1")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesOrder = ["/tmp/middle.csv", "/tmp/top.csv"]
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.warnings.isEmpty)
        #expect(output.manifestPayload.series.map(\.sourceRef) == ["/tmp/middle.csv", "/tmp/top.csv"])
    }

    @Test("Manifest cache orders reorderable field sweeps to match committed visual order")
    func manifestCacheOrdersFieldSweepsToCommittedOrder() {
        let sweeps = [
            makeSweep(sampleID: "sample-1", temperatureK: 0,   r1omega: [0, 1], sourceFilePath: "/tmp/0.csv"),
            makeSweep(sampleID: "sample-1", temperatureK: 30,  r1omega: [1, 2], sourceFilePath: "/tmp/30.csv"),
            makeSweep(sampleID: "sample-1", temperatureK: 90,  r1omega: [2, 3], sourceFilePath: "/tmp/90.csv"),
            makeSweep(sampleID: "sample-1", temperatureK: 120, r1omega: [3, 4], sourceFilePath: "/tmp/120.csv"),
            makeSweep(sampleID: "sample-1", temperatureK: 180, r1omega: [4, 5], sourceFilePath: "/tmp/180.csv")
        ]

        let ordered = ThreeOmegaWorkspaceStore.manifestOrderedFieldSweeps(
            sweeps,
            seriesOrder: ["/tmp/0.csv", "/tmp/30.csv", "/tmp/90.csv", "/tmp/120.csv", "/tmp/180.csv"]
        )

        // manifest = committed visual order (not reversed)
        #expect(ordered.map(\.sourceFilePath) == ["/tmp/0.csv", "/tmp/30.csv", "/tmp/90.csv", "/tmp/120.csv", "/tmp/180.csv"])
    }

    @MainActor
    @Test("Series order survives tab switches and ignores active payload sequence when explicit order exists")
    func seriesOrderSurvivesTabSwitches() {
        let explicitOrder = ["/tmp/bottom.csv", "/tmp/middle.csv", "/tmp/top.csv"]
        let manager = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: .fieldSweep1omega)
        manager.tabStates[.fieldSweep1omega] = TabRenderState(seriesOrder: explicitOrder)

        let payloadA = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Top", x: [0, 1], y: [2, 3], sourceRef: "/tmp/top.csv", sampleID: "s1"),
                WorkbenchPlotSeries(label: "Middle", x: [0, 1], y: [1, 2], sourceRef: "/tmp/middle.csv", sampleID: "s2"),
                WorkbenchPlotSeries(label: "Bottom", x: [0, 1], y: [0, 1], sourceRef: "/tmp/bottom.csv", sampleID: "s3")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        let payloadB = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Middle", x: [0, 1], y: [1, 2], sourceRef: "/tmp/middle.csv", sampleID: "s2"),
                WorkbenchPlotSeries(label: "Bottom", x: [0, 1], y: [0, 1], sourceRef: "/tmp/bottom.csv", sampleID: "s3"),
                WorkbenchPlotSeries(label: "Top", x: [0, 1], y: [2, 3], sourceRef: "/tmp/top.csv", sampleID: "s1")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let rowsA = WorkbenchSeriesOrderPanel.makeRows(payload: payloadA, currentSeriesOrder: manager.state(for: .fieldSweep1omega).seriesOrder)
        manager.activeTab = .rahe
        manager.activeTab = .fieldSweep1omega
        let rowsB = WorkbenchSeriesOrderPanel.makeRows(payload: payloadB, currentSeriesOrder: manager.state(for: .fieldSweep1omega).seriesOrder)

        #expect(manager.state(for: .fieldSweep1omega).seriesOrder == explicitOrder)
        #expect(rowsA.map(\.identityKey) == explicitOrder)
        #expect(rowsB.map(\.identityKey) == explicitOrder)
        #expect(rowsA.map(\.identityKey) == rowsB.map(\.identityKey))
    }

    @Test("3ω mixed-angle legend labels match manifest series labels by sourceRef")
    func mixedAngleLegendLabelsMatchManifestLabelsBySourceRef() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "R(1ω)",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
            series: [
                WorkbenchPlotSeries(label: "0 K", x: [0, 1], y: [0, 1], sourceRef: "/tmp/0.csv", sampleID: "sample-1", metadata: ["device": "0deg", "temperature": "70"]),
                WorkbenchPlotSeries(label: "30 K", x: [0, 1], y: [1, 2], sourceRef: "/tmp/30.csv", sampleID: "sample-1", metadata: ["device": "30deg", "temperature": "70"]),
                WorkbenchPlotSeries(label: "120 K", x: [0, 1], y: [2, 3], sourceRef: "/tmp/120.csv", sampleID: "sample-1", metadata: ["device": "120deg", "temperature": "70"]),
                WorkbenchPlotSeries(label: "180 K", x: [0, 1], y: [3, 4], sourceRef: "/tmp/180.csv", sampleID: "sample-1", metadata: ["device": "180deg", "temperature": "70"]),
                WorkbenchPlotSeries(label: "90 K", x: [0, 1], y: [4, 5], sourceRef: "/tmp/90.csv", sampleID: "sample-1", metadata: ["device": "90deg", "temperature": "70"])
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let renderInput = WorkbenchRenderPipeline.Input(payload: payload)
        let rendered = try WorkbenchRenderPipeline.render(renderInput)

        var manifestPayload = payload
        _ = WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &manifestPayload)

        let renderedBySourceRef = Dictionary(uniqueKeysWithValues: rendered.manifestPayload.series.compactMap { series in
            series.sourceRef.map { ($0, series.label) }
        })
        let manifestBySourceRef = Dictionary(uniqueKeysWithValues: manifestPayload.series.compactMap { series in
            series.sourceRef.map { ($0, series.label) }
        })

        #expect(rendered.manifestPayload.series.map(\.sourceRef) == manifestPayload.series.map(\.sourceRef))
        #expect(renderedBySourceRef.keys == manifestBySourceRef.keys)
        #expect(Set(renderedBySourceRef.values) == Set(["0 K", "30 K", "90 K", "120 K", "180 K"]))
        #expect(Set(manifestBySourceRef.values) == Set(["0deg", "30deg", "90deg", "120deg", "180deg"]))
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
        let seriesLow  = WorkbenchPlotSeries(label: "Low",  x: [0, 1], y: [0.0, 0.0], sourceRef: "/tmp/low.csv", sampleID: "low")
        let seriesHigh = WorkbenchPlotSeries(label: "High", x: [0, 1], y: [1.0, 1.0], sourceRef: "/tmp/high.csv", sampleID: "high")
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
        let series = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0.5, 0.5], sourceRef: "/tmp/A.csv", sampleID: "A")
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

    @Test("hitTestSeries can grab a visibly stacked curve away from the exact stroke center")
    func hitTestSeriesFindsOffsetStackedCurve() {
        let low = WorkbenchPlotSeries(label: "Low", x: [0, 1], y: [0.0, 0.0], sourceRef: "/tmp/low.csv", sampleID: "low")
        let high = WorkbenchPlotSeries(label: "High", x: [0, 1], y: [1.0, 1.0], sourceRef: "/tmp/high.csv", sampleID: "high")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [low, high],
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: CGFloat(opts.width), height: CGFloat(opts.height))

        let yMin = -0.05
        let ySpan = 1.1
        let lowCGY = layout.plotRect.minY + CGFloat((0.0 - yMin) / ySpan) * layout.plotRect.height
        let lowScreenY = fittedRect.minY + (CGFloat(opts.height) - lowCGY) * (fittedRect.height / CGFloat(opts.height))
        let offsetLocation = CGPoint(x: fittedRect.midX + 9, y: lowScreenY + 6)

        let hit = layout.hitTestSeries(location: offsetLocation, fittedRect: fittedRect, payload: payload, radius: 14)
        #expect(hit?.sampleID == "low", "Visible curve should still be draggable with a small pointer offset")
    }

    @Test("hitTestSeries works when fitted image rect is narrower than the renderer plotRect")
    func hitTestSeriesWorksWithNarrowFittedRect() {
        let low = WorkbenchPlotSeries(label: "Low", x: [0, 1], y: [0.0, 0.0], sourceRef: "/tmp/low.csv", sampleID: "low")
        let high = WorkbenchPlotSeries(label: "High", x: [0, 1], y: [1.0, 1.0], sourceRef: "/tmp/high.csv", sampleID: "high")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [low, high],
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: 629, height: 471.75)

        let yMin = -0.05
        let ySpan = 1.1
        let lowCGY = layout.plotRect.minY + CGFloat((0.0 - yMin) / ySpan) * layout.plotRect.height
        let lowScreenY = fittedRect.minY + (CGFloat(opts.height) - lowCGY) * (fittedRect.height / CGFloat(opts.height))
        let hitLocation = CGPoint(x: fittedRect.midX, y: lowScreenY)

        let hit = layout.hitTestSeries(location: hitLocation, fittedRect: fittedRect, payload: payload, radius: 14)
        #expect(hit?.sampleID == "low", "Hit-testing should use the fitted image rect, not the renderer plotRect width")
    }

    @Test("hitTestSeries can hit a data-space curve spanning x=-3...3 and y around -1...1")
    func hitTestSeriesHitsDataSpaceCurve() {
        let xs = stride(from: -3.0, through: 3.0, by: 1.0).map { $0 }
        let ys = xs.map { sin($0) * 0.9 }
        let series = WorkbenchPlotSeries(label: "Wave", x: xs, y: ys, sourceRef: "/tmp/wave.csv", sampleID: "wave")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "H", yField: "R"),
            series: [series],
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: 629, height: 471.75)

        let xMin = xs.min() ?? 0
        let xMax = xs.max() ?? 1
        let yMin = ys.min() ?? 0
        let yMax = ys.max() ?? 1
        let targetX = 0.0
        let targetY = 0.0
        let cgX = layout.plotRect.minX + CGFloat((targetX - xMin) / (xMax - xMin)) * layout.plotRect.width
        let cgY = layout.plotRect.minY + CGFloat((targetY - yMin) / (yMax - yMin)) * layout.plotRect.height
        let screenX = fittedRect.minX + cgX * (fittedRect.width / CGFloat(opts.width))
        let screenY = fittedRect.minY + (CGFloat(opts.height) - cgY) * (fittedRect.height / CGFloat(opts.height))

        let hit = layout.hitTestSeries(location: CGPoint(x: screenX, y: screenY), fittedRect: fittedRect, payload: payload, radius: 14)
        #expect(hit?.sampleID == "wave")
    }

    @Test("hitTestSeries skips series without sampleID")
    func hitTestSeriesSkipsNilSampleID() {
        let seriesNoID = WorkbenchPlotSeries(label: "NoID", x: [0, 1], y: [0.5, 0.5], sourceRef: "/tmp/noid.csv")
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

    // MARK: - Test case 8: Series identity storage

    @Test("updateSeriesLabel stores override by stable identity key")
    @MainActor
    func updateSeriesLabelStoresByIdentityKey() {
        let manager = TabRenderManager(defaultTab: "tab1")
        manager.updateSeriesLabel(identityKey: "A#300", newLabel: "Custom")
        #expect(manager.tabStates["tab1"]?.seriesLabelOverrides["A#300"] == "Custom")
    }

    @Test("toIndexedOverrides translates sampleID keys to series indices")
    func toIndexedOverridesTranslatesSampleIDKeys() {
        let series = [
            WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: "A#300"),
            WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: "B#300")
        ]
        let result = toIndexedOverrides(["A#300": "Custom"], series: series)
        #expect(result == [0: "Custom"])
    }

    @Test("toIndexedOverrides passes through Int-string keys (AHE/XY fallback)")
    func toIndexedOverridesPassesThroughIntStringKeys() {
        let series: [WorkbenchPlotSeries] = []
        let result = toIndexedOverrides(["0": "CustomA", "1": "CustomB"], series: series)
        #expect(result == [0: "CustomA", 1: "CustomB"])
    }

    @Test("WorkbenchSeriesOrderKeyResolver prefers sourceRef, then sampleID, then index")
    func seriesOrderKeyResolverPrefersSourceRefThenSampleIDThenIndex() {
        let sourceRefSeries = WorkbenchPlotSeries(label: "", x: [], y: [], sourceRef: "/tmp/a.csv", sampleID: "sample-a")
        let sampleIDSeries = WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: "sample-b")
        let indexSeries = WorkbenchPlotSeries(label: "", x: [], y: [])

        #expect(WorkbenchSeriesOrderKeyResolver.resolve(for: sourceRefSeries, originalIndex: 7) == "/tmp/a.csv")
        #expect(WorkbenchSeriesOrderKeyResolver.resolve(for: sampleIDSeries, originalIndex: 7) == "sample-b")
        #expect(WorkbenchSeriesOrderKeyResolver.resolve(for: indexSeries, originalIndex: 7) == "7")
    }

    @Test("migrateStateIfNeeded converts Int-string keys to sampleID")
    func migrateStateConvertsIntKeysToSampleID() {
        var state = TabRenderState(seriesLabelOverrides: ["0": "Custom"])
        let series = [WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: "A#300")]
        migrateStateIfNeeded(&state, series: series)
        #expect(state.seriesLabelOverrides == ["A#300": "Custom"])
    }

    @Test("migrateStateIfNeeded no-ops when keys are already sampleID")
    func migrateStateNoOpsForSampleIDKeys() {
        var state = TabRenderState(seriesLabelOverrides: ["A#300": "Custom"])
        let series = [WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: "A#300")]
        migrateStateIfNeeded(&state, series: series)
        #expect(state.seriesLabelOverrides == ["A#300": "Custom"])
    }

    @Test("migrateStateIfNeeded drops orphaned Int keys when sampleID is nil")
    func migrateStateDropsOrphanedIntKeys() {
        var state = TabRenderState(seriesLabelOverrides: ["0": "Custom"])
        let series = [WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: nil)]
        migrateStateIfNeeded(&state, series: series)
        #expect(state.seriesLabelOverrides.isEmpty)
    }

    @MainActor
    @Test("IVPlotRenderer applies reordered series by sourceRef")
    func ivPlotRendererAppliesSeriesOrderBySourceRef() {
        var renderer = IVPlotRenderer()
        renderer.seriesOrder = [
            "/tmp/b.lvm",
            "/tmp/a.lvm"
        ]

        let sweeps = [
            makeIVSweep(stem: "a", filePath: "/tmp/a.lvm", temperatureK: 100),
            makeIVSweep(stem: "b", filePath: "/tmp/b.lvm", temperatureK: 200)
        ]

        let (_, _, payload, warnings) = IVRenderRoute.renderFirstHarmonicVsCurrentViaSharedRoute(
            renderer: renderer,
            sweeps: sweeps,
            device: "test"
        )
        #expect(warnings == ["Legend: no distinguishing dimension found across selected samples."])
        #expect(payload?.series.map(\.sourceRef) == [
            "/tmp/b.lvm",
            "/tmp/a.lvm"
        ])
    }

    // MARK: - Helpers

    private func alignSeriesOrder(old: [String]?, defaultIDs: [String]) -> [String]? {
        ThreeOmegaWorkspaceStore.alignSeriesOrder(old: old, defaultIDs: defaultIDs)
    }

    private func makeSweep(
        sampleID: String,
        temperatureK: Double,
        r1omega: [Double],
        sourceFilePath: String? = nil
    ) -> ThreeOmegaFieldSweepResult {
        let n = r1omega.count
        return ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: "testDevice",
            sampleMetadata: nil,
            sampleID: sampleID,
            sourceFilePath: sourceFilePath,
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

    private func makeIVSweep(
        stem: String,
        filePath: String,
        temperatureK: Double
    ) -> IVSweep {
        IVSweep(
            stem: stem,
            temperatureK: temperatureK,
            fieldT: 0.5,
            current: [0.0, 1.0],
            ch1X: [1.0, 2.0],
            ch1Y: [2.0, 3.0],
            ch2X: [3.0, 4.0],
            ch2Y: [4.0, 5.0],
            firstR: nil,
            firstTheta: nil,
            secondR: nil,
            secondTheta: nil,
            firstRH: nil,
            frequencyAfter: nil,
            measurementFilePath: filePath,
            sampleMetadata: nil
        )
    }
}
