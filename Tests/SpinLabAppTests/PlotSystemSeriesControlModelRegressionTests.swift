import CoreGraphics
import Testing
@testable import SpinLabApp

@Suite("PlotSystem Series Control Model Regression")
struct PlotSystemSeriesControlModelRegressionTests {

    private enum TestTab: String, Hashable, Sendable {
        case main
    }

    private func makeAngleSweepPayload() -> WorkbenchPlotPayload {
        let angles = ["0deg", "150deg", "60deg", "90deg", "180deg", "120deg", "30deg", "0deg"]
        let series = zip(angles.indices, angles).map { index, angle in
            WorkbenchPlotSeries(
                label: "70 K",
                x: [0, 1, 2],
                y: [Double(index), Double(index + 1), Double(index + 2)],
                sourceRef: "/tmp/angle-\(index).csv",
                sampleID: "sample-\(index)",
                metadata: [
                    "device": angle
                ]
            )
        }

        return WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Angle sweep",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R (Ω)"),
            series: series,
            semanticParams: ["deviceMode": "angleSweep", "tabKey": "fieldSweep1omega"],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
    }

    private func makeVisualFieldSweepPayload() -> WorkbenchPlotPayload {
        let angles = ["0deg", "150deg", "60deg", "180deg", "30deg", "120deg", "90deg"]
        let series = zip(angles.indices, angles).map { index, angle in
            WorkbenchPlotSeries(
                label: "70 K",
                x: [0, 1, 2],
                y: [Double(index), Double(index + 1), Double(index + 2)],
                sourceRef: "/tmp/field-\(index).csv",
                sampleID: "field-\(index)",
                metadata: [
                    "device": angle
                ]
            )
        }

        return WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Field sweep",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R (Ω)"),
            series: series,
            semanticParams: ["deviceMode": "angleSweep", "tabKey": "fieldSweep1omega"],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
    }

    private func makeNormalSeriesPayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "iv",
            workflowDisplayName: "IV",
            title: "IV",
            axisMapping: WorkbenchAxisMapping(xField: "I", yField: "V"),
            series: [
                WorkbenchPlotSeries(label: "1ω", x: [0, 1], y: [0, 1], sourceRef: "/tmp/iv-1.csv", sampleID: "iv-1"),
                WorkbenchPlotSeries(label: "2ω", x: [0, 1], y: [1, 2], sourceRef: "/tmp/iv-2.csv", sampleID: "iv-2")
            ],
            seriesReorderable: true
        )
    }

    @Test("Model-provided rows preserve legend top-to-bottom order")
    func modelProvidedRowsPreserveVisualOrder() {
        let controlModel = SeriesControlModel(items: [
            SeriesControlItem(identityKey: "/tmp/90.csv", displayLabel: "90deg", sourceRef: "/tmp/90.csv", sampleID: "90", originalIndex: 0, isVisible: true, canRename: true, canReorder: true),
            SeriesControlItem(identityKey: "/tmp/120.csv", displayLabel: "120deg", sourceRef: "/tmp/120.csv", sampleID: "120", originalIndex: 1, isVisible: true, canRename: true, canReorder: true),
            SeriesControlItem(identityKey: "/tmp/30.csv", displayLabel: "30deg", sourceRef: "/tmp/30.csv", sampleID: "30", originalIndex: 2, isVisible: true, canRename: true, canReorder: true)
        ])

        let rows = WorkbenchSeriesOrderPanel.makeRows(
            controlModel: controlModel,
            payload: nil,
            currentSeriesOrder: nil,
            hiddenSeriesKeys: []
        )
        let displayed = WorkbenchSeriesOrderPanel.presentedRows(from: rows, source: .model)

        #expect(displayed.map(\.displayLabel) == ["90deg", "120deg", "30deg"])
        #expect(displayed.map(\.identityKey) == ["/tmp/90.csv", "/tmp/120.csv", "/tmp/30.csv"])
    }

    @Test("Model-provided commit order matches visual chip order")
    func modelProvidedCommitOrderMatchesVisualOrder() {
        let visualRows = [
            SeriesOrderRow(identityKey: "/tmp/90.csv", displayLabel: "90deg", sourceRef: "/tmp/90.csv", sampleID: "90", originalIndex: 0, isVisible: true, canRename: true, canReorder: true),
            SeriesOrderRow(identityKey: "/tmp/120.csv", displayLabel: "120deg", sourceRef: "/tmp/120.csv", sampleID: "120", originalIndex: 1, isVisible: true, canRename: true, canReorder: true),
            SeriesOrderRow(identityKey: "/tmp/30.csv", displayLabel: "30deg", sourceRef: "/tmp/30.csv", sampleID: "30", originalIndex: 2, isVisible: true, canRename: true, canReorder: true)
        ]
        let moved = WorkbenchSeriesOrderPanel.reorderedRows(
            visualRows,
            draggedKey: "/tmp/30.csv",
            targetKey: "/tmp/90.csv",
            dropLocationX: 0.8
        )
        let committed = WorkbenchSeriesOrderPanel.internalRows(fromPresentedRows: moved, source: .model)
        #expect(committed.map(\.identityKey) == moved.map(\.identityKey))
    }

    @Test("Angle-sweep control model keeps semantic angle labels and distinct identities")
    func angleSweepControlModelKeepsSemanticLabels() throws {
        let payload = makeVisualFieldSweepPayload()
        let model = SeriesControlModel.fromPayload(payload)

        // fromPayload ignores reverseSeriesForLegend when no explicit currentSeriesOrder is
        // supplied (Stage 2A-2 fix for double-reversal/mirrored-legend), so the natural chip
        // order matches the payload's own series order: ["0deg", "150deg", "60deg", "180deg",
        // "30deg", "120deg", "90deg"] — see "fromPayload ignores reverseSeriesForLegend when
        // building chip order" in this suite for the documented baseline behavior.
        #expect(model.displayLabels == ["0deg", "150deg", "60deg", "180deg", "30deg", "120deg", "90deg"])
        #expect(Set(model.items.map(\.identityKey)).count == model.items.count)
        #expect(model.items.first?.displayLabel == "0deg")
        #expect(model.items.last?.displayLabel == "90deg")
    }

    @Test("fromPayload preserves provided canonical visual order")
    func fromPayloadPreservesProvidedVisualOrder() throws {
        let payload = makeNormalSeriesPayload()
        let model = SeriesControlModel.fromPayload(
            payload,
            currentSeriesOrder: ["/tmp/iv-2.csv", "/tmp/iv-1.csv"]
        )

        #expect(model.items.map(\.identityKey) == ["/tmp/iv-2.csv", "/tmp/iv-1.csv"])
        #expect(model.displayLabels == ["2ω", "1ω"])
    }

    @Test("fromPayload ignores reverseSeriesForLegend when building chip order")
    func fromPayloadIgnoresReverseSeriesForLegend() throws {
        var payload = makeNormalSeriesPayload()
        payload.reverseSeriesForLegend = true

        let model = SeriesControlModel.fromPayload(payload)

        #expect(model.items.map(\.identityKey) == ["/tmp/iv-1.csv", "/tmp/iv-2.csv"])
        #expect(model.displayLabels == ["1ω", "2ω"])
    }

    @Test("fromPayload preserves label and visibility behavior")
    func fromPayloadPreservesLabelAndVisibilityBehavior() throws {
        var payload = makeNormalSeriesPayload()
        payload.reverseSeriesForLegend = true

        let model = SeriesControlModel.fromPayload(
            payload,
            hiddenSeriesKeys: ["/tmp/iv-2.csv"]
        )

        #expect(model.items.map(\.identityKey) == ["/tmp/iv-1.csv", "/tmp/iv-2.csv"])
        #expect(model.items.map(\.displayLabel) == ["1ω", "2ω"])
        #expect(model.items.map(\.isVisible) == [true, false])
        #expect(model.items.first?.canMoveUp == false)
        #expect(model.items.first?.canMoveDown == true)
        #expect(model.items.last?.canMoveUp == true)
        #expect(model.items.last?.canMoveDown == false)
    }

    @Test("3ω legend order matches chip order for canonical visual series order")
    func threeOmegaLegendOrderMatchesChipOrder() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3ω",
            title: "Canonical visual order",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R (Ω)"),
            series: [
                WorkbenchPlotSeries(label: "A", x: [0, 1], y: [1, 2], sourceRef: "/tmp/a.csv", sampleID: "a"),
                WorkbenchPlotSeries(label: "B", x: [0, 1], y: [2, 3], sourceRef: "/tmp/b.csv", sampleID: "b")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        let canonicalOrder = ["/tmp/b.csv", "/tmp/a.csv"]

        let chipModel = SeriesControlModel.fromPayload(payload, currentSeriesOrder: canonicalOrder)

        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesOrder = canonicalOrder
        let output = try WorkbenchRenderPipeline.render(input)

        #expect(chipModel.items.map(\.identityKey) == canonicalOrder)
        #expect(output.layout.legendRows.map(\.identityKey) == canonicalOrder)
        #expect(output.layout.legendRows.map(\.identityKey) == chipModel.items.map(\.identityKey))
    }

    @MainActor
    @Test("Legend drag rerender keeps the same series control model")
    func legendDragKeepsSeriesControlModel() throws {
        let payload = makeAngleSweepPayload()
        let output = TabRenderOutput(manifestPayload: payload, displayPayload: payload)
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        manager.setOutput(output, for: .main)
        let initial = try #require(manager.output(for: .main).seriesControlModel)

        manager.updateLegendPoint(CGPoint(x: 0.2, y: 0.7))
        manager.setOutput(output, for: .main)

        let rerendered = try #require(manager.output(for: .main).seriesControlModel)
        #expect(rerendered.displayLabels == initial.displayLabels)
        #expect(rerendered.signature == initial.signature)
    }

    @MainActor
    @Test("Rename only updates the existing identity override")
    func renameKeepsModelLabelsStable() throws {
        let payload = makeAngleSweepPayload()
        let output = TabRenderOutput(manifestPayload: payload, displayPayload: payload)
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        manager.setOutput(output, for: .main)
        let model = try #require(manager.output(for: .main).seriesControlModel)
        let target = try #require(model.items.first(where: { $0.displayLabel == "60deg" }))

        manager.updateSeriesLabel(identityKey: target.identityKey, newLabel: "Renamed 60deg")
        manager.setOutput(output, for: .main)

        let rerendered = try #require(manager.output(for: .main).seriesControlModel)
        #expect(rerendered.displayLabels == model.displayLabels)
        #expect(manager.state(for: .main).seriesLabelOverrides == [target.identityKey: "Renamed 60deg"])
        #expect(rerendered.items.first(where: { $0.identityKey == target.identityKey })?.displayLabel == "60deg")
    }

    @Test("Reorder changes order without swapping to raw temperature labels")
    func reorderKeepsSemanticLabels() throws {
        let payload = makeVisualFieldSweepPayload()
        let model = SeriesControlModel.fromPayload(payload)
        let targetOrder = [model.items[2].identityKey, model.items[0].identityKey, model.items[1].identityKey, model.items[3].identityKey, model.items[4].identityKey, model.items[5].identityKey, model.items[6].identityKey]
        let reordered = SeriesControlModel(items: targetOrder.compactMap { key in model.items.first(where: { $0.identityKey == key }) })

        // Natural (unreversed) baseline order is ["0deg","150deg","60deg","180deg","30deg","120deg","90deg"];
        // moving item[2] ("60deg") to the front yields:
        #expect(reordered.displayLabels == ["60deg", "0deg", "150deg", "180deg", "30deg", "120deg", "90deg"])
        let sweeps = payload.series.enumerated().map { index, series in
            ThreeOmegaFieldSweepResult(
                temperatureK: Double(index),
                device: series.metadata["device"] ?? "",
                sampleMetadata: series.metadata,
                sampleID: series.sampleID,
                sourceFilePath: series.sourceRef,
                hField: [0, 1],
                r1omega: [0, 1],
                r3omega: [0, 1],
                iRms: 1e-3,
                rahe1omega: nil,
                rahe1omegaWA: nil,
                hc1omega: nil,
                hc3omega: nil,
                v3omegaWindow: 0,
                v3omegaFit: nil
            )
        }
        let visualOrder = reordered.items.map(\.identityKey)
        let orderedSweeps = ThreeOmegaWorkspaceStore.manifestOrderedFieldSweeps(sweeps, seriesOrder: visualOrder)
        #expect(orderedSweeps.compactMap(\.sourceFilePath) == visualOrder)
    }

    @Test("Panel prefers series control model over payload inference")
    func panelPrefersSeriesControlModel() {
        let controlModel = SeriesControlModel(items: [
            SeriesControlItem(identityKey: "angle-a", displayLabel: "0deg", sourceRef: "/tmp/a.csv", sampleID: "a", originalIndex: 0, isVisible: true, canRename: true, canReorder: true),
            SeriesControlItem(identityKey: "angle-b", displayLabel: "30deg", sourceRef: "/tmp/b.csv", sampleID: "b", originalIndex: 1, isVisible: true, canRename: true, canReorder: true)
        ])
        let payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Angle sweep",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R (Ω)"),
            series: [
                WorkbenchPlotSeries(label: "70 K", x: [0, 1], y: [0, 1], sourceRef: "/tmp/a.csv", sampleID: "a"),
                WorkbenchPlotSeries(label: "70 K", x: [0, 1], y: [1, 2], sourceRef: "/tmp/b.csv", sampleID: "b")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        let rows = WorkbenchSeriesOrderPanel.makeRows(
            controlModel: controlModel,
            payload: payload,
            currentSeriesOrder: nil,
            hiddenSeriesKeys: []
        )

        #expect(rows.map { $0.displayLabel } == ["0deg", "30deg"])
        #expect(rows.map { $0.identityKey } == ["angle-a", "angle-b"])
    }

    @Test("Normal series plots still resolve labels from their payload series")
    func normalSeriesPlotsStillUsePayloadLabels() throws {
        let ivPayload = makeNormalSeriesPayload()
        let xyPayload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY",
            title: "XY",
            axisMapping: WorkbenchAxisMapping(xField: "φ (deg)", yField: "Rxx (Ω)"),
            series: [
                WorkbenchPlotSeries(label: "10 K", x: [0, 1], y: [0, 1], sourceRef: "/tmp/xy-1.csv", sampleID: "xy-1"),
                WorkbenchPlotSeries(label: "20 K", x: [0, 1], y: [1, 2], sourceRef: "/tmp/xy-2.csv", sampleID: "xy-2")
            ],
            seriesReorderable: true
        )

        for payload in [ivPayload, xyPayload] {
            let model = SeriesControlModel.fromPayload(payload)
            #expect(model.displayLabels == payload.series.map(\.label))
        }
    }

    @MainActor
    @Test("3ω field-sweep render order uses stable identities from the control model")
    func threeOmegaFieldSweepIdentityMappingUsesStableKeys() throws {
        let payload = makeVisualFieldSweepPayload()
        let model = SeriesControlModel.fromPayload(payload)
        let visualKeys = model.items.map(\.identityKey)

        let sweeps = payload.series.enumerated().map { index, series in
            ThreeOmegaFieldSweepResult(
                temperatureK: Double(index),
                device: series.metadata["device"] ?? "",
                sampleMetadata: series.metadata,
                sampleID: series.sampleID,
                sourceFilePath: series.sourceRef,
                hField: [0, 1],
                r1omega: [0, 1],
                r3omega: [0, 1],
                iRms: 1e-3,
                rahe1omega: nil,
                rahe1omegaWA: nil,
                hc1omega: nil,
                hc3omega: nil,
                v3omegaWindow: 0,
                v3omegaFit: nil
            )
        }
        let orderedSweeps = ThreeOmegaWorkspaceStore.manifestOrderedFieldSweeps(sweeps, seriesOrder: visualKeys)
        #expect(Set(visualKeys).count == visualKeys.count)
        #expect(orderedSweeps.compactMap(\.sourceFilePath) == visualKeys)

        let reorderedVisualKeys = Array([visualKeys[1], visualKeys[0]] + Array(visualKeys.dropFirst(2)))
        let reorderedSweeps = ThreeOmegaWorkspaceStore.manifestOrderedFieldSweeps(sweeps, seriesOrder: reorderedVisualKeys)
        #expect(reorderedSweeps.compactMap(\.sourceFilePath) == reorderedVisualKeys)
    }

    @MainActor
    @Test("IV visual chip order matches the legend order")
    func ivVisualOrderMatchesLegendOrder() throws {
        let payload = makeNormalSeriesPayload()
        let model = SeriesControlModel.fromPayload(payload)
        #expect(model.displayLabels == ["1ω", "2ω"])

        let rows = WorkbenchSeriesOrderPanel.makeRows(
            controlModel: model,
            payload: payload,
            currentSeriesOrder: nil,
            hiddenSeriesKeys: []
        )
        #expect(rows.map(\.displayLabel) == ["1ω", "2ω"])
        #expect(rows.map(\.identityKey) == ["/tmp/iv-1.csv", "/tmp/iv-2.csv"])
    }
}
