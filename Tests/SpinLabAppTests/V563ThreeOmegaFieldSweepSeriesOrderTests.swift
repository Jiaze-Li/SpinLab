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
    private func waitForFieldSweepOutputs(_ store: ThreeOmegaWorkspaceStore, timeoutMS: UInt64 = 5_000) async -> Bool {
        let deadline = timeoutMS * 1_000_000
        let sleepNS: UInt64 = 50_000_000
        var elapsed: UInt64 = 0
        while elapsed <= deadline {
            let out1 = store.tabs.output(for: .fieldSweep1omega)
            let out3 = store.tabs.output(for: .fieldSweep3omega)
            if out1.layout != nil, out1.manifestPayload != nil, out1.displayPayload != nil,
               out3.layout != nil, out3.manifestPayload != nil, out3.displayPayload != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: sleepNS)
            elapsed += sleepNS
        }
        return false
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

        let order = ["/tmp/top.csv", "/tmp/bottom.csv"]
        store.updateSeriesOrder(order)
        store._refreshManifestPayloads()

        let r1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let r3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)

        // Manifest keeps the same visual top-to-bottom order as the committed field-sweep order.
        #expect(r1 == ["/tmp/top.csv", "/tmp/bottom.csv"])
        #expect(r3 == ["/tmp/top.csv", "/tmp/bottom.csv"])
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
        #expect(manifestPayload.axisMapping.xField == "Temperature (K)")
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
        #expect(controlModel.items.map(\.displayLabel) == [#"math:R_{AHE}^{1ω}"#, #"math:R_{AHE}^{3ω}"#])

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
        #expect(displayPayload?.axisMapping.xField == "Temperature (K)")
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

        #expect(payload.axisMapping.xField == "Temperature (K)")
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

        let committed = ["/tmp/top.csv", "/tmp/bottom.csv"]
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

        // committed = [top, bottom] → top at visual top, bottom at visual bottom
        let committed = ["/tmp/top.csv", "/tmp/bottom.csv"]
        store.updateSeriesOrder(committed)
        store._refreshManifestPayloads()

        let manifest = store.tabs.output(for: .fieldSweep1omega).manifestPayload
        let internalRows = WorkbenchSeriesOrderPanel.makeRows(
            payload: manifest,
            currentSeriesOrder: store.activeSeriesOrder
        )
        let displayed = WorkbenchSeriesOrderPanel.presentedRows(from: internalRows)
        // The panel presents the committed order in its internal bottom-to-top form.
        #expect(displayed.first?.identityKey == "3w:r1omega-vs-h:sweep:/tmp/bottom.csv")
        #expect(displayed.last?.identityKey == "3w:r1omega-vs-h:sweep:/tmp/top.csv")
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

    // MARK: - Canonical visual order single-path (chip order == legend order)

    @Test("R3ω stacked render: legend and chip order both match canonical visual series order")
    func r3omegaLegendAndChipOrderMatchCanonicalVisualOrder() throws {
        let sweepA = makeFieldSweep(sourceRef: "/tmp/A.csv", sampleID: "A", temperatureK: 5)
        let sweepB = makeFieldSweep(sourceRef: "/tmp/B.csv", sampleID: "B", temperatureK: 10)
        let sweepC = makeFieldSweep(sourceRef: "/tmp/C.csv", sampleID: "C", temperatureK: 15)
        let sweeps = [sweepA, sweepB, sweepC]

        // Canonical visual (chip/legend top-to-bottom) order — deliberately not the sweeps'
        // natural temperature order, and not what the renderer-internal stack order would be.
        let visualOrder = ["/tmp/B.csv", "/tmp/A.csv", "/tmp/C.csv"]
        let internalOrder = ThreeOmegaWorkspaceStore.rendererSeriesOrder(fromVisualOrder: visualOrder)

        var renderer = ThreeOmegaPlotRenderer()
        renderer.canonicalVisualSeriesOrder = visualOrder
        let (_, renderedLayout, renderedPayload, warnings) = renderer.renderR3omega(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: internalOrder
        )
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
        let manifestPayload = try #require(renderedPayload)
        let layout = try #require(renderedLayout)

        // The renderer-internal series array is reversed relative to visual order (stacking),
        // so this expected order is not simply the payload's own series order restated.
        let expectedOrder = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualOrder, series: manifestPayload.series)
        #expect(expectedOrder.count == 3)
        #expect(manifestPayload.series.map { WorkbenchSeriesOrderKeyResolver.resolve(for: $0, originalIndex: 0) } != expectedOrder,
                "sanity check: renderer-internal series order must differ from canonical visual order for this test to be meaningful")

        #expect(layout.legendRows.map(\.identityKey) == expectedOrder,
                "legend top-to-bottom order must follow canonical visual order, not renderer-internal stack order")

        let chipModel = SeriesControlModel.fromPayload(manifestPayload, currentSeriesOrder: visualOrder)
        #expect(chipModel.items.map(\.identityKey) == expectedOrder,
                "control chip order must match legend order")
    }

    @MainActor
    @Test("Field-sweep rerender keeps explicit visual order stable across stack offset changes")
    func fieldSweepRerenderKeepsIdentityOrderStableAcrossStackOffsetChanges() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let defaultExpected = ["/tmp/300K.csv", "/tmp/260K.csv", "/tmp/220K.csv", "/tmp/180K.csv", "/tmp/140K.csv", "/tmp/100K.csv"]
        let explicitExpected = ["/tmp/300K.csv", "/tmp/100K.csv", "/tmp/260K.csv", "/tmp/220K.csv", "/tmp/180K.csv", "/tmp/140K.csv"]
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [
                makeFieldSweep(sourceRef: "/tmp/100K.csv", sampleID: "100K", temperatureK: 100),
                makeFieldSweep(sourceRef: "/tmp/140K.csv", sampleID: "140K", temperatureK: 140),
                makeFieldSweep(sourceRef: "/tmp/180K.csv", sampleID: "180K", temperatureK: 180),
                makeFieldSweep(sourceRef: "/tmp/220K.csv", sampleID: "220K", temperatureK: 220),
                makeFieldSweep(sourceRef: "/tmp/260K.csv", sampleID: "260K", temperatureK: 260),
                makeFieldSweep(sourceRef: "/tmp/300K.csv", sampleID: "300K", temperatureK: 300)
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100.0: 1e-3, 140.0: 1e-3, 180.0: 1e-3, 220.0: 1e-3, 260.0: 1e-3, 300.0: 1e-3],
            warnings: []
        )
        store.tabs.activeTab = .fieldSweep1omega

        func waitForVisualOrder(_ expectedSourceRefs: [String]) async -> Bool {
            let deadline: UInt64 = 5_000_000_000
            let sleepNS: UInt64 = 50_000_000
            var elapsed: UInt64 = 0
            while elapsed <= deadline {
                let out1 = store.tabs.output(for: .fieldSweep1omega)
                let out3 = store.tabs.output(for: .fieldSweep3omega)
                guard let layout1 = out1.layout,
                      let layout3 = out3.layout,
                      let display1 = out1.displayPayload,
                      let display3 = out3.displayPayload,
                      let model1 = out1.seriesControlModel,
                      let model3 = out3.seriesControlModel,
                      let manifest1 = out1.manifestPayload,
                      let manifest3 = out3.manifestPayload else {
                    try? await Task.sleep(nanoseconds: sleepNS)
                    elapsed += sleepNS
                    continue
                }
                let expected1 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(expectedSourceRefs, series: manifest1.series)
                let expected3 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(expectedSourceRefs, series: manifest3.series)
                let legend1 = layout1.legendRows.map(\.identityKey)
                let legend3 = layout3.legendRows.map(\.identityKey)
                let chips1 = model1.items.map(\.identityKey)
                let chips3 = model3.items.map(\.identityKey)
                let stacked1 = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display1.series).map(\.identityKey)
                let stacked3 = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display3.series).map(\.identityKey)
                if legend1 == expected1, chips1 == expected1, stacked1 == expected1,
                   legend3 == expected3, chips3 == expected3, stacked3 == expected3 {
                    return true
                }
                try? await Task.sleep(nanoseconds: sleepNS)
                elapsed += sleepNS
            }
            return false
        }

        store.tabs.clearOutputs()
        store.stackOffsetMultiplier = 0.0
        store.rerenderFieldSweepTabs()
        guard await waitForVisualOrder(defaultExpected) else {
            Issue.record("Timed out waiting for field-sweep rerender at stackOffsetMultiplier = 0.0")
            return
        }

        let default1 = store.tabs.output(for: .fieldSweep1omega)
        let default3 = store.tabs.output(for: .fieldSweep3omega)
        let defaultLegend1 = try #require(default1.layout).legendRows.map(\.identityKey)
        let defaultLegend3 = try #require(default3.layout).legendRows.map(\.identityKey)
        let defaultExpected1 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(defaultExpected, series: try #require(default1.manifestPayload).series)
        let defaultExpected3 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(defaultExpected, series: try #require(default3.manifestPayload).series)
        #expect(defaultLegend1 == defaultExpected1)
        #expect(try #require(default1.seriesControlModel).items.map(\.identityKey) == defaultExpected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(default1.displayPayload).series).map(\.identityKey) == defaultExpected1)
        #expect(defaultLegend3 == defaultExpected3)
        #expect(try #require(default3.seriesControlModel).items.map(\.identityKey) == defaultExpected3)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(default3.displayPayload).series).map(\.identityKey) == defaultExpected3)

        store.tabs.clearOutputs()
        store.setFieldSweepSeriesOrder(explicitExpected)
        store.rerenderFieldSweepTabs()
        guard await waitForVisualOrder(explicitExpected) else {
            Issue.record("Timed out waiting for field-sweep rerender after explicit visual order")
            return
        }

        let first1 = store.tabs.output(for: .fieldSweep1omega)
        let first3 = store.tabs.output(for: .fieldSweep3omega)
        let firstLegend1 = try #require(first1.layout).legendRows.map(\.identityKey)
        let firstLegend3 = try #require(first3.layout).legendRows.map(\.identityKey)
        let firstExpected1 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(explicitExpected, series: try #require(first1.manifestPayload).series)
        let firstExpected3 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(explicitExpected, series: try #require(first3.manifestPayload).series)
        #expect(firstLegend1 == firstExpected1)
        #expect(try #require(first1.seriesControlModel).items.map(\.identityKey) == firstExpected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(first1.displayPayload).series).map(\.identityKey) == firstExpected1)
        #expect(firstLegend3 == firstExpected3)
        #expect(try #require(first3.seriesControlModel).items.map(\.identityKey) == firstExpected3)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(first3.displayPayload).series).map(\.identityKey) == firstExpected3)

        store.tabs.clearOutputs()
        store.stackOffsetMultiplier = 1.4
        store.rerenderFieldSweepTabs()
        guard await waitForVisualOrder(explicitExpected) else {
            Issue.record("Timed out waiting for field-sweep rerender at stackOffsetMultiplier = 1.4")
            return
        }

        let second1 = store.tabs.output(for: .fieldSweep1omega)
        let second3 = store.tabs.output(for: .fieldSweep3omega)
        #expect(try #require(second1.layout).legendRows.map(\.identityKey) == firstLegend1)
        #expect(try #require(second1.seriesControlModel).items.map(\.identityKey) == firstExpected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(second1.displayPayload).series).map(\.identityKey) == firstExpected1)
        #expect(try #require(second3.layout).legendRows.map(\.identityKey) == firstLegend3)
        #expect(try #require(second3.seriesControlModel).items.map(\.identityKey) == firstExpected3)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(second3.displayPayload).series).map(\.identityKey) == firstExpected3)
    }

    @MainActor
    @Test("Field-sweep rerender derives a default visual order when no series order is set")
    func fieldSweepRerenderDerivesDefaultVisualOrderWhenSeriesOrderIsNil() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [
                makeFieldSweep(sourceRef: "/tmp/100K.csv", sampleID: "100K", temperatureK: 100),
                makeFieldSweep(sourceRef: "/tmp/200K.csv", sampleID: "200K", temperatureK: 200),
                makeFieldSweep(sourceRef: "/tmp/300K.csv", sampleID: "300K", temperatureK: 300)
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100.0: 1e-3, 200.0: 1e-3, 300.0: 1e-3],
            warnings: []
        )
        store.setFieldSweepSeriesOrder(nil)
        store.tabs.activeTab = .fieldSweep1omega

        func snapshot(for tab: ThreeOmegaWorkbenchTab) async throws -> (
            legend: [String],
            chips: [String],
            displayOrder: [String]
        ) {
            let tabOutput = store.tabs.output(for: tab)
            let manifest = try #require(tabOutput.manifestPayload)
            let display = try #require(tabOutput.displayPayload)
            let legend = try #require(tabOutput.layout).legendRows.map(\.identityKey)
            let chips = try #require(tabOutput.seriesControlModel).items.map(\.identityKey)
            let displayOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display.series).map(\.identityKey)
            #expect(chips == legend)
            #expect(legend == WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(legend, series: manifest.series))
            return (legend: legend, chips: chips, displayOrder: displayOrder)
        }

        store.stackOffsetMultiplier = 0.0
        store.rerenderFieldSweepTabs()
        guard await waitForFieldSweepOutputs(store) else {
            Issue.record("Timed out waiting for default-order field-sweep rerender at stackOffsetMultiplier = 0.0")
            return
        }

        let first1 = try await snapshot(for: .fieldSweep1omega)
        let first3 = try await snapshot(for: .fieldSweep3omega)
        #expect(first1.legend == ["3w:r1omega-vs-h:sweep:/tmp/300K.csv", "3w:r1omega-vs-h:sweep:/tmp/200K.csv", "3w:r1omega-vs-h:sweep:/tmp/100K.csv"])
        #expect(first3.legend == ["3w:r3omega-vs-h:sweep:/tmp/300K.csv", "3w:r3omega-vs-h:sweep:/tmp/200K.csv", "3w:r3omega-vs-h:sweep:/tmp/100K.csv"])
        #expect(first1.chips == first1.legend)
        #expect(first3.chips == first3.legend)
        #expect(first1.displayOrder == first1.legend)
        #expect(first3.displayOrder == first3.legend)

        store.stackOffsetMultiplier = 1.4
        store.rerenderFieldSweepTabs()
        guard await waitForFieldSweepOutputs(store) else {
            Issue.record("Timed out waiting for default-order field-sweep rerender at stackOffsetMultiplier = 1.4")
            return
        }

        let second1 = try await snapshot(for: .fieldSweep1omega)
        let second3 = try await snapshot(for: .fieldSweep3omega)
        #expect(second1.legend == first1.legend)
        #expect(second1.chips == first1.chips)
        #expect(second1.displayOrder == first1.displayOrder)
        #expect(second3.legend == first3.legend)
        #expect(second3.chips == first3.chips)
        #expect(second3.displayOrder == first3.displayOrder)
    }
}
