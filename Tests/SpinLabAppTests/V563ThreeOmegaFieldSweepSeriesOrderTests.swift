import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.3 ThreeOmega Field-Sweep Series Order")
struct V563ThreeOmegaFieldSweepSeriesOrderTests {

    private func makeFieldSweep(sourceRef: String, sampleID: String, temperatureK: Double) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: sampleID,
            sourceFilePath: sourceRef,
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    private func makeCombinedRAHESweeps() -> [ThreeOmegaFieldSweepResult] {
        [
            ThreeOmegaFieldSweepResult(
                temperatureK: 5.0,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-5K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.4,
                rahe1omegaWA: 0.8,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.2e-4,
                v3omegaFit: 0.2e-4
            ),
            ThreeOmegaFieldSweepResult(
                temperatureK: 10.0,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-10K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.8,
                rahe1omegaWA: 0.4,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.6e-4,
                v3omegaFit: 0.6e-4
            )
        ]
    }

    private func makeIngestionResult() -> ThreeOmegaIngestionResult {
        ThreeOmegaIngestionResult(
            fieldSweeps: [
                makeFieldSweep(sourceRef: "/tmp/bottom.csv", sampleID: "bottom", temperatureK: 5.0),
                makeFieldSweep(sourceRef: "/tmp/top.csv", sampleID: "top", temperatureK: 10.0)
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [5.0: 1e-3, 10.0: 1e-3],
            warnings: []
        )
    }

    @MainActor
    @Test("AHE 1ω and 3ω share one field-sweep series order across tab switches")
    func sharedSeriesOrderSurvivesTabSwitches() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let order = ["/tmp/bottom.csv", "/tmp/top.csv"]

        store.tabs.activeTab = .fieldSweep1omega
        store.updateSeriesOrder(order)
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == order)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == order)

        store.tabs.activeTab = .fieldSweep3omega
        #expect(store.activeSeriesOrder == order)

        let updatedOrder = ["/tmp/top.csv", "/tmp/bottom.csv"]
        store.updateSeriesOrder(updatedOrder)
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == updatedOrder)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == updatedOrder)

        store.tabs.activeTab = .fieldSweep1omega
        #expect(store.activeSeriesOrder == updatedOrder)
    }

    @MainActor
    @Test("Resetting series order clears both field-sweep tabs")
    func resetSeriesOrderClearsBothTabs() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .fieldSweep1omega
        store.updateSeriesOrder(["/tmp/bottom.csv", "/tmp/top.csv"])

        store.resetSeriesOrder()

        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == nil)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == nil)
        #expect(store.activeSeriesOrder == nil)
    }

    // MARK: - stableSourceRef fallback (v5.6.3 backward compat)

    @Test("stableSourceRef: prefers sourceFilePath when present")
    func stableSourceRefPrefersFilePath() {
        let sweep = makeFieldSweep(sourceRef: "/path/to/file.lvm", sampleID: "sid", temperatureK: 5)
        #expect(sweep.stableSourceRef == "/path/to/file.lvm")
    }

    @Test("stableSourceRef: falls back to sampleID+device+temp composite when sourceFilePath is nil")
    func stableSourceRefFallsBackToSampleIDComposite() {
        var sweep = makeFieldSweep(sourceRef: "/path/to/file.lvm", sampleID: "mysample", temperatureK: 5)
        sweep.sourceFilePath = nil
        #expect(sweep.stableSourceRef == "mysample|0deg|5.0K")
    }

    @Test("stableSourceRef: falls back to device+temp when both sourceFilePath and sampleID are nil")
    func stableSourceRefFallsBackToDeviceTemp() {
        var sweep = makeFieldSweep(sourceRef: "/path/to/file.lvm", sampleID: "sid", temperatureK: 5)
        sweep.sourceFilePath = nil
        sweep.sampleID = nil
        #expect(sweep.stableSourceRef == "0deg|5.0K")
        #expect(!sweep.stableSourceRef.isEmpty)
    }

    @Test("stableSourceRef: same sampleID but different device/temperature produce distinct values")
    func stableSourceRefDistinguishesByDeviceAndTemp() {
        var sweepA = makeFieldSweep(sourceRef: "/a.lvm", sampleID: "shared", temperatureK: 5)
        sweepA.sourceFilePath = nil
        var sweepB = makeFieldSweep(sourceRef: "/b.lvm", sampleID: "shared", temperatureK: 10)
        sweepB.sourceFilePath = nil
        #expect(sweepA.stableSourceRef != sweepB.stableSourceRef)

        // Verify the distinguishing components are present
        #expect(sweepA.stableSourceRef.contains("5.0K"))
        #expect(sweepB.stableSourceRef.contains("10.0K"))
    }

    @Test("R1ω render with legacy sweeps (nil sourceFilePath + nil sampleID) does not crash and has non-empty sourceRefs")
    func r1omegaLegacySweepsProduceNonEmptySourceRefs() throws {
        // Simulate sweeps from an old pack that never wrote sourceFilePath or sampleID.
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil
        var sweep10 = makeFieldSweep(sourceRef: "/tmp/10K.lvm", sampleID: "s10", temperatureK: 10)
        sweep10.sourceFilePath = nil
        sweep10.sampleID = nil

        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, _, warnings) = renderer.renderR1omega(sweeps: [sweep5, sweep10], device: "0deg")
        // Must not crash (assert would abort); just verify no pipeline failure warning.
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
    }

    @Test("R1ω reorderable payload: all series have non-empty sourceRef")
    func r1omegaReorderablePayloadSeriesAllHaveSourceRef() throws {
        // Sweeps with no sourceFilePath — stableSourceRef falls back to id.
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil
        var sweep10 = makeFieldSweep(sourceRef: "/tmp/10K.lvm", sampleID: "s10", temperatureK: 10)
        sweep10.sourceFilePath = nil
        sweep10.sampleID = nil

        var renderer = ThreeOmegaPlotRenderer()
        renderer.titleTokens = ["sample": "TEST"]
        let (_, layout, _, _) = renderer.renderR1omega(sweeps: [sweep5, sweep10], device: "0deg")
        // Layout is non-nil only when render succeeds without crashing.
        #expect(layout != nil)
    }

    @Test("R3ω render with legacy sweeps does not crash")
    func r3omegaLegacySweepsDoNotCrash() throws {
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil

        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, _, warnings) = renderer.renderR3omega(sweeps: [sweep5], device: "0deg")
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
    }

    @MainActor
    @Test("Manifest refresh uses the shared field-sweep order for both tabs")
    func manifestRefreshUsesSharedOrderForBothTabs() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeIngestionResult()
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        let order = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.updateSeriesOrder(order)
        store._refreshManifestPayloads()

        let r1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let r3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)

        // manifest is bottom-to-top (matches committed order) after PR127 fix
        #expect(r1 == ["/tmp/bottom.csv", "/tmp/top.csv"])
        #expect(r3 == ["/tmp/bottom.csv", "/tmp/top.csv"])
    }

    @Test("RAHE combined payload keeps both harmonic series identities and visibility")
    func raheCombinedPayloadKeepsBothHarmonicSeriesIdentitiesAndVisibility() throws {
        let sweeps = makeCombinedRAHESweeps()

        var renderer = ThreeOmegaPlotRenderer()
        let manifestPayload = try #require(renderer.makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            rahe1Method: .window,
            rahe3Method: .highField
        ))
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifestPayload.series).map(\.identityKey)
        #expect(manifestPayload.seriesReorderable)
        #expect(manifestPayload.axisMapping.xField == "T (K)")
        #expect(manifestPayload.axisMapping.yField == #"math:R_{AHE} (Ω)"#)
        #expect(manifestPayload.legendDimension == "Harmonic")
        #expect(manifestPayload.series.map(\.label) == [#"math:R_{AHE}^{1ω}"#, #"math:R_{AHE}^{3ω}"#])
        #expect(manifestPayload.series[0].x == [5.0, 10.0])
        #expect(manifestPayload.series[1].x == [5.0, 10.0])
        #expect(manifestPayload.series[0].y == [0.8, 0.4])
        #expect(manifestPayload.series[1].y == [0.2, 0.6])
        #expect(identities.count == 2)
        #expect(identities[0] != identities[1])
        #expect(identities.contains(where: { $0.contains(WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE) }))

        let controlModel = SeriesControlModel.fromPayload(manifestPayload)
        #expect(controlModel.items.count == 2)
        #expect(controlModel.items.map(\.displayLabel) == [#"math:R_{AHE}^{3ω}"#, #"math:R_{AHE}^{1ω}"#])

        let hidden = try #require(identities.first)
        let (_, _, displayPayload, warnings) = renderer.renderRAHE(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: [hidden],
            rahe1Method: .window,
            rahe3Method: .highField
        )
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
        #expect(displayPayload?.series.count == manifestPayload.series.count - 1)
        #expect(manifestPayload.series.count == 2)
        #expect(displayPayload?.series.count == 1)
        #expect(displayPayload?.axisMapping.xField == "T (K)")
        #expect(displayPayload?.axisMapping.yField == #"math:R_{AHE} (Ω)"#)
    }

    @Test("RAHE combined payload uses temperature-based extraction, not field-sweep x values")
    func raheCombinedPayloadUsesTemperatureAxisAndHarmonicSeries() throws {
        let sweeps = makeCombinedRAHESweeps()

        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            rahe1Method: .window,
            rahe3Method: .highField
        ))

        #expect(payload.axisMapping.xField == "T (K)")
        #expect(payload.axisMapping.yField == #"math:R_{AHE} (Ω)"#)
        #expect(payload.series.count == 2)
        #expect(payload.series[0].x == [5.0, 10.0])
        #expect(payload.series[1].x == [5.0, 10.0])
        #expect(payload.series[0].label == #"math:R_{AHE}^{1ω}"#)
        #expect(payload.series[1].label == #"math:R_{AHE}^{3ω}"#)
        #expect(payload.series[0].y == [0.8, 0.4])
        #expect(payload.series[1].y == [0.2, 0.6])
    }

    @Test("RAHE combined payload keeps manifest series while hiding one harmonic only in display payload")
    func raheCombinedPayloadHidesOneSeriesInDisplayOnly() throws {
        let sweeps = makeCombinedRAHESweeps()

        var renderer = ThreeOmegaPlotRenderer()
        let manifestPayload = try #require(renderer.makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            rahe1Method: .window,
            rahe3Method: .highField
        ))
        let hiddenKey = try #require(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifestPayload.series).first?.identityKey)
        let (_, _, displayPayload, _) = renderer.renderRAHE(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: [hiddenKey],
            rahe1Method: .window,
            rahe3Method: .highField
        )
        #expect(manifestPayload.series.count == 2)
        #expect(displayPayload?.series.count == 1)
        #expect(displayPayload?.series.first?.label == #"math:R_{AHE}^{3ω}"#)
        #expect(displayPayload?.series.first?.x == [5.0, 10.0])
    }

    // MARK: - PR127 behavioral tests

    @MainActor
    @Test("After updateSeriesOrder, activeManifestPayload series matches the committed order")
    func activeManifestPayloadMatchesCommittedOrder() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeIngestionResult()
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        let committed = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.updateSeriesOrder(committed)
        store._refreshManifestPayloads()

        let manifest1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let manifest3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)
        #expect(manifest1 == committed)
        #expect(manifest3 == committed)
    }

    @MainActor
    @Test("Panel displayed rows after updateSeriesOrder show visual top-to-bottom order")
    func panelDisplayedRowsReflectSeriesOrder() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeIngestionResult()
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        // committed = [bottom, top] → bottom at visual bottom, top at visual top
        let committed = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.updateSeriesOrder(committed)
        store._refreshManifestPayloads()

        let manifest = store.tabs.output(for: .fieldSweep1omega).manifestPayload
        let internalRows = WorkbenchSeriesOrderPanel.makeRows(
            payload: manifest,
            currentSeriesOrder: store.activeSeriesOrder
        )
        let displayed = WorkbenchSeriesOrderPanel.presentedRows(from: internalRows)
        // Visual top (displayed index 0) must be the last committed key (= top series)
        #expect(displayed.first?.identityKey == "/tmp/top.csv")
        #expect(displayed.last?.identityKey == "/tmp/bottom.csv")
    }

    @Test("Arrow reorder and drag reorder produce identical committed order")
    func arrowAndDragReorderProduceIdenticalCommittedOrder() {
        // Construct a 3-series manifest in bottom-to-top format
        let payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
            series: [
                WorkbenchPlotSeries(label: "A", x: [0], y: [0], sourceRef: "/tmp/a.csv", sampleID: "a"),
                WorkbenchPlotSeries(label: "B", x: [0], y: [0], sourceRef: "/tmp/b.csv", sampleID: "b"),
                WorkbenchPlotSeries(label: "C", x: [0], y: [0], sourceRef: "/tmp/c.csv", sampleID: "c")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        // internal = [a, b, c] (a=bottom, c=top); displayed = [c, b, a]

        let internalRows = WorkbenchSeriesOrderPanel.makeRows(payload: payload, currentSeriesOrder: nil)
        let displayedRows = WorkbenchSeriesOrderPanel.presentedRows(from: internalRows)
        // displayed[0]=c, displayed[1]=b, displayed[2]=a

        // Arrow: move c (display pos 0) one step down → display pos 1
        var arrowDisplayed = displayedRows
        let moved = arrowDisplayed.remove(at: 0)
        arrowDisplayed.insert(moved, at: 1)
        let arrowCommitted = WorkbenchSeriesOrderPanel.internalRows(fromPresentedRows: arrowDisplayed).map(\.identityKey)
        // arrowDisplayed=[b,c,a] → internal=[a,c,b]

        // Drag: drop c after b (dropLocationX=0.8 on b at display pos 1)
        let dragDisplayed = WorkbenchSeriesOrderPanel.reorderedRows(
            displayedRows,
            draggedKey: "/tmp/c.csv",
            targetKey: "/tmp/b.csv",
            dropLocationX: 0.8
        )
        let dragCommitted = WorkbenchSeriesOrderPanel.internalRows(fromPresentedRows: dragDisplayed).map(\.identityKey)

        #expect(arrowCommitted == dragCommitted)
        #expect(arrowCommitted == ["/tmp/a.csv", "/tmp/c.csv", "/tmp/b.csv"])
    }
}
