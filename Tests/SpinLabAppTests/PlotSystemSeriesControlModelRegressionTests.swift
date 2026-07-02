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

    @MainActor
    @Test("Angle-sweep control model keeps semantic angle labels and distinct identities")
    func angleSweepControlModelKeepsSemanticLabels() throws {
        let payload = makeAngleSweepPayload()
        let output = TabRenderOutput(manifestPayload: payload, displayPayload: payload)
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        manager.setOutput(output, for: .main)

        let model = try #require(manager.output(for: .main).seriesControlModel)
        #expect(model.displayLabels == ["0deg", "150deg", "60deg", "90deg", "180deg", "120deg", "30deg", "0deg"])
        #expect(Set(model.items.map(\.identityKey)).count == model.items.count)
        #expect(model.items.first?.displayLabel == "0deg")
        #expect(model.items.last?.displayLabel == "0deg")
        #expect(model.items.first?.identityKey != model.items.last?.identityKey)
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

    @MainActor
    @Test("Reorder changes order without swapping to raw temperature labels")
    func reorderKeepsSemanticLabels() throws {
        let payload = makeAngleSweepPayload()
        let output = TabRenderOutput(manifestPayload: payload, displayPayload: payload)
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        manager.setOutput(output, for: .main)
        let model = try #require(manager.output(for: .main).seriesControlModel)
        let targetOrder = [model.items[2].identityKey, model.items[0].identityKey, model.items[1].identityKey, model.items[3].identityKey, model.items[4].identityKey, model.items[5].identityKey, model.items[6].identityKey, model.items[7].identityKey]
        manager.updateSeriesOrder(targetOrder)
        manager.setOutput(output, for: .main)

        let rerendered = try #require(manager.output(for: .main).seriesControlModel)
        #expect(rerendered.items.map(\.identityKey) == targetOrder)
        #expect(rerendered.displayLabels == ["60deg", "0deg", "150deg", "90deg", "180deg", "120deg", "30deg", "0deg"])
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

        let threeOmegaRenderer = ThreeOmegaPlotRenderer()
        let sweep1 = ThreeOmegaFieldSweepResult(
            temperatureK: 5,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sweep-1",
            sourceFilePath: "/tmp/3w-1.csv",
            hField: [0, 1],
            r1omega: [0, 1],
            r3omega: [1, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        let sweep2 = ThreeOmegaFieldSweepResult(
            temperatureK: 15,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sweep-2",
            sourceFilePath: "/tmp/3w-2.csv",
            hField: [0, 1],
            r1omega: [1, 2],
            r3omega: [2, 3],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        let threeOmegaPayload1 = try #require(threeOmegaRenderer.makeR1omegaPayload(sweeps: [sweep1, sweep2], device: "0deg"))
        let threeOmegaPayload3 = try #require(threeOmegaRenderer.makeR3omegaPayload(sweeps: [sweep1, sweep2], device: "0deg"))

        for payload in [ivPayload, xyPayload, threeOmegaPayload1, threeOmegaPayload3] {
            let model = SeriesControlModel.fromPayload(payload)
            #expect(model.displayLabels == payload.series.map(\.label))
        }
    }
}
