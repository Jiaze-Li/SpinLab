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

    private func makeOrderConflictSweep(
        sourceRef: String,
        sampleID: String,
        temperatureK: Double,
        meanY: Double
    ) -> ThreeOmegaFieldSweepResult {
        let y = [meanY - 1.0, meanY, meanY + 1.0]
        return ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: sampleID,
            sourceFilePath: sourceRef,
            hField: [-1000, 0, 1000],
            r1omega: y,
            r3omega: y,
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    private func makeOrderConflictIngestionResult() -> ThreeOmegaIngestionResult {
        let temperatures: [Double] = [10, 30, 50, 70, 90, 110]
        let fieldSweeps = temperatures.map { temperatureK in
            makeOrderConflictSweep(
                sourceRef: "/tmp/\(Int(temperatureK))K.csv",
                sampleID: "\(Int(temperatureK))K",
                temperatureK: temperatureK,
                meanY: -temperatureK
            )
        }
        return ThreeOmegaIngestionResult(
            fieldSweeps: fieldSweeps,
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: Dictionary(uniqueKeysWithValues: temperatures.map { ($0, 1e-3) }),
            warnings: []
        )
    }

    private func meanYOrder(for series: [WorkbenchPlotSeries]) -> [String] {
        series
            .map { series in
                let mean = series.y.isEmpty ? .nan : series.y.reduce(0.0, +) / Double(series.y.count)
                return (
                    identity: WorkbenchSeriesOrderKeyResolver.resolve(for: series, originalIndex: 0),
                    mean: mean
                )
            }
            .sorted { $0.mean > $1.mean }
            .map(\.identity)
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
    private func waitForOutput(
        _ store: ThreeOmegaWorkspaceStore,
        tab: ThreeOmegaWorkbenchTab,
        timeoutMS: UInt64 = 5_000
    ) async -> WorkbenchPlotLayout? {
        let deadline = timeoutMS * 1_000_000
        let sleepNS: UInt64 = 50_000_000
        var elapsed: UInt64 = 0
        while elapsed <= deadline {
            if let layout = store.tabs.output(for: tab).layout {
                return layout
            }
            try? await Task.sleep(nanoseconds: sleepNS)
            elapsed += sleepNS
        }
        return nil
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

    @MainActor
    @Test("R1ω render with legacy sweeps (nil sourceFilePath + nil sampleID) does not crash and has non-empty sourceRefs")
    func r1omegaLegacySweepsProduceNonEmptySourceRefs() throws {
        // Simulate sweeps from an old pack that never wrote sourceFilePath or sampleID.
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil
        var sweep10 = makeFieldSweep(sourceRef: "/tmp/10K.lvm", sampleID: "s10", temperatureK: 10)
        sweep10.sourceFilePath = nil
        sweep10.sampleID = nil

        let renderer = ThreeOmegaPlotRenderer()
        let (_, _, _, _, warnings) = ThreeOmegaFieldSweepRenderRoute.renderR1omegaViaSharedRoute(renderer: renderer, sweeps: [sweep5, sweep10], device: "0deg")
        // Must not crash (assert would abort); just verify no pipeline failure warning.
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
    }

    @MainActor
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
        let (_, _, layout, _, _) = ThreeOmegaFieldSweepRenderRoute.renderR1omegaViaSharedRoute(renderer: renderer, sweeps: [sweep5, sweep10], device: "0deg")
        // Layout is non-nil only when render succeeds without crashing.
        #expect(layout != nil)
    }

    @MainActor
    @Test("R3ω render with legacy sweeps does not crash")
    func r3omegaLegacySweepsDoNotCrash() throws {
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil

        let renderer = ThreeOmegaPlotRenderer()
        let (_, _, _, _, warnings) = ThreeOmegaFieldSweepRenderRoute.renderR3omegaViaSharedRoute(renderer: renderer, sweeps: [sweep5], device: "0deg")
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

    @MainActor
    @Test("Fresh analysis with no manual reorder caches the render path's default visual order")
    func manifestRefreshFallsBackToDefaultVisualOrderWhenUnset() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let ingestion = makeIngestionResult()
        store.ingestionResult = ingestion
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        // No updateSeriesOrder call — this is the fresh-analysis path.
        store._refreshManifestPayloads()

        let expectedOrder = ThreeOmegaWorkspaceStore.defaultFieldSweepVisualSeriesOrder(
            from: ingestion.fieldSweeps,
            workflowID: WorkflowKey.threeOmega.rawValue,
            tab: .fieldSweep1omega
        )
        let rawOrder = ingestion.fieldSweeps.map(\.stableSourceRef)
        let r1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let r3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)

        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == nil, "Precondition: no manual reorder committed")
        #expect(r1 == expectedOrder)
        #expect(r3 == expectedOrder)
        #expect(r1 != rawOrder, "Manifest cache must not fall back to raw sweep input order once a render-path default order exists")
    }

    @MainActor
    @Test("Field-sweep stacked render keeps requested visual order even when raw means conflict")
    func fieldSweepStackedRenderKeepsRequestedVisualOrder() async {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeOrderConflictIngestionResult()
        store.cachedInputFiles = [
            "/tmp/10K.csv",
            "/tmp/30K.csv",
            "/tmp/50K.csv",
            "/tmp/70K.csv",
            "/tmp/90K.csv",
            "/tmp/110K.csv"
        ]
        store.tabs.activeTab = .fieldSweep1omega

        let requestedVisualOrder = [
            "/tmp/110K.csv",
            "/tmp/90K.csv",
            "/tmp/10K.csv",
            "/tmp/70K.csv",
            "/tmp/50K.csv",
            "/tmp/30K.csv"
        ]

        func assertOrder(for tab: ThreeOmegaWorkbenchTab) {
            let output = store.tabs.output(for: tab)
            guard let layout = output.layout,
                  let manifest = output.manifestPayload,
                  let display = output.displayPayload,
                  let seriesModel = output.seriesControlModel else {
                Issue.record("missing render output for \(tab.rawValue)")
                return
            }

            let expectedLegend = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(requestedVisualOrder, series: manifest.series)
            let stackedMeans = meanYOrder(for: display.series)
            let displayIdentityOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display.series).map(\.identityKey)

            #expect(manifest.reverseSeriesForLegend == false)
            #expect(display.reverseSeriesForLegend == false)
            #expect(layout.legendRows.map(\.identityKey) == expectedLegend)
            #expect(layout.legendRows.map(\.identityKey) == displayIdentityOrder)
            #expect(seriesModel.items.map(\.identityKey) == expectedLegend)
            #expect(manifest.series.map(\.sourceRef) == requestedVisualOrder)
            #expect(display.series.map(\.sourceRef) == requestedVisualOrder)
            #expect(display.series.map(\.sourceRef) == manifest.series.map(\.sourceRef))
            #expect(stackedMeans == expectedLegend)
        }

        store.setFieldSweepSeriesOrder(requestedVisualOrder)

        store.tabs.clearOutputs()
        store.stackOffsetMultiplier = 0.8
        store.rerenderFieldSweepTabs()
        guard await waitForFieldSweepOutputs(store) else {
            Issue.record("Timed out waiting for field-sweep rerender at stackOffsetMultiplier = 0.8")
            return
        }
        assertOrder(for: .fieldSweep1omega)
        assertOrder(for: .fieldSweep3omega)

        store.tabs.clearOutputs()
        store.stackOffsetMultiplier = 1.4
        store.rerenderFieldSweepTabs()
        guard await waitForFieldSweepOutputs(store) else {
            Issue.record("Timed out waiting for field-sweep rerender at stackOffsetMultiplier = 1.4")
            return
        }
        assertOrder(for: .fieldSweep1omega)
        assertOrder(for: .fieldSweep3omega)
    }

    @MainActor
    @Test("Field-sweep stacked render consumes full identity keys in requested visual order")
    func fieldSweepStackedRenderConsumesFullIdentityKeys() async throws {
        let sweeps = makeOrderConflictIngestionResult().fieldSweeps
        let baselineR1Payload = try #require(ThreeOmegaPlotRenderer().makeR1omegaPayload(
            sweeps: sweeps,
            device: "0deg"
        ))
        let baselineR3Payload = try #require(ThreeOmegaPlotRenderer().makeR3omegaPayload(
            sweeps: sweeps,
            device: "0deg"
        ))
        let fullIdentityOrder1 = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: baselineR1Payload.series).map(\.identityKey)
        let fullIdentityOrder3 = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: baselineR3Payload.series).map(\.identityKey)
        let requestedVisualOrder1 = [
            fullIdentityOrder1[5],
            fullIdentityOrder1[4],
            fullIdentityOrder1[2],
            fullIdentityOrder1[3],
            fullIdentityOrder1[1],
            fullIdentityOrder1[0]
        ]
        let requestedVisualOrder3 = [
            fullIdentityOrder3[5],
            fullIdentityOrder3[4],
            fullIdentityOrder3[2],
            fullIdentityOrder3[3],
            fullIdentityOrder3[1],
            fullIdentityOrder3[0]
        ]

        let renderer1 = ThreeOmegaPlotRenderer()
        let render1 = ThreeOmegaFieldSweepRenderRoute.renderR1omegaViaSharedRoute(
            renderer: renderer1,
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedVisualOrder1,
            hiddenSeriesKeys: []
        )
        let layout1 = try #require(render1.2)
        let display1 = try #require(render1.3)
        #expect(!render1.4.contains(where: { $0.contains("seriesOrder mismatch") }))
        #expect(display1.reverseSeriesForLegend == false)
        #expect(layout1.legendRows.map(\.identityKey) == requestedVisualOrder1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display1.series).map(\.identityKey) == requestedVisualOrder1)
        #expect(meanYOrder(for: display1.series) == requestedVisualOrder1)

        let renderer3 = ThreeOmegaPlotRenderer()
        let render3 = ThreeOmegaFieldSweepRenderRoute.renderR3omegaViaSharedRoute(
            renderer: renderer3,
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedVisualOrder3,
            hiddenSeriesKeys: []
        )
        let layout3 = try #require(render3.2)
        let display3 = try #require(render3.3)
        #expect(!render3.4.contains(where: { $0.contains("seriesOrder mismatch") }))
        #expect(display3.reverseSeriesForLegend == false)
        #expect(layout3.legendRows.map(\.identityKey) == requestedVisualOrder3)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display3.series).map(\.identityKey) == requestedVisualOrder3)
        #expect(meanYOrder(for: display3.series) == requestedVisualOrder3)
    }

    @MainActor
    @Test("RAHE combined payload keeps both harmonic series identities and visibility")
    func raheCombinedPayloadKeepsBothHarmonicSeriesIdentitiesAndVisibility() throws {
        let sweeps = makeCombinedRAHESweeps()

        let renderer = ThreeOmegaPlotRenderer()
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
        let (_, _, layout, _, warnings) = ThreeOmegaSharedRenderRoute.render(
            payload: manifestPayload,
            tab: .rahe,
            hiddenSeriesKeys: [hidden]
        )
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
        let visibleRows = try #require(layout).legendRows
        #expect(visibleRows.count == manifestPayload.series.count - 1)
        #expect(manifestPayload.series.count == 2)
        #expect(visibleRows.count == 1)
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

    @MainActor
    @Test("RAHE combined payload keeps manifest series while hiding one harmonic only in display payload")
    func raheCombinedPayloadHidesOneSeriesInDisplayOnly() throws {
        let sweeps = makeCombinedRAHESweeps()

        let renderer = ThreeOmegaPlotRenderer()
        let manifestPayload = try #require(renderer.makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            rahe1Method: .window,
            rahe3Method: .highField
        ))
        let hiddenKey = try #require(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifestPayload.series).first?.identityKey)
        let (_, _, layout, _, _) = ThreeOmegaSharedRenderRoute.render(
            payload: manifestPayload,
            tab: .rahe,
            hiddenSeriesKeys: [hiddenKey]
        )
        let visibleRows = try #require(layout).legendRows
        #expect(manifestPayload.series.count == 2)
        #expect(visibleRows.count == 1)
        #expect(visibleRows.first?.originalLabel == #"math:R_{AHE}^{3ω}"#)
        #expect(manifestPayload.series.last?.x == [5.0, 10.0])
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

    @MainActor
    @Test("R3ω stacked render: legend and chip order both match canonical visual series order")
    func r3omegaLegendAndChipOrderMatchCanonicalVisualOrder() throws {
        let sweepA = makeFieldSweep(sourceRef: "/tmp/A.csv", sampleID: "A", temperatureK: 5)
        let sweepB = makeFieldSweep(sourceRef: "/tmp/B.csv", sampleID: "B", temperatureK: 10)
        let sweepC = makeFieldSweep(sourceRef: "/tmp/C.csv", sampleID: "C", temperatureK: 15)
        let sweeps = [sweepA, sweepB, sweepC]

        // Canonical visual (chip/legend top-to-bottom) order — deliberately not the sweeps'
        // natural temperature order.
        let visualOrder = ["/tmp/B.csv", "/tmp/A.csv", "/tmp/C.csv"]

        var renderer = ThreeOmegaPlotRenderer()
        renderer.canonicalVisualSeriesOrder = visualOrder
        let (_, _, renderedLayout, renderedPayload, warnings) = ThreeOmegaFieldSweepRenderRoute.renderR3omegaViaSharedRoute(
            renderer: renderer,
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: visualOrder
        )
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
        let manifestPayload = try #require(renderedPayload)
        let layout = try #require(renderedLayout)

        let expectedOrder = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualOrder, series: manifestPayload.series)
        #expect(expectedOrder.count == 3)
        #expect(manifestPayload.reverseSeriesForLegend == false)
        #expect(manifestPayload.series.compactMap(\.sourceRef) == visualOrder)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifestPayload.series).map(\.identityKey) == expectedOrder)

        #expect(layout.legendRows.map(\.identityKey) == expectedOrder,
                "legend top-to-bottom order must follow canonical visual order")

        let chipModel = SeriesControlModel.fromPayload(manifestPayload, currentSeriesOrder: visualOrder)
        #expect(chipModel.items.map(\.identityKey) == expectedOrder,
                "control chip order must match legend order")
    }

    @MainActor
    @Test("Field-sweep manifest cache keeps complete visual order while display applies hidden filtering")
    func fieldSweepManifestCacheKeepsCompleteOrderWhileDisplayFiltersHiddenSeries() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweeps = [
            makeFieldSweep(sourceRef: "/tmp/100K.csv", sampleID: "100K", temperatureK: 100),
            makeFieldSweep(sourceRef: "/tmp/200K.csv", sampleID: "200K", temperatureK: 200),
            makeFieldSweep(sourceRef: "/tmp/300K.csv", sampleID: "300K", temperatureK: 300)
        ]
        let visualOrder = ["/tmp/300K.csv", "/tmp/200K.csv", "/tmp/100K.csv"]
        let hiddenKey = "3w:r1omega-vs-h:sweep:/tmp/200K.csv"

        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: sweeps,
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100.0: 1e-3, 200.0: 1e-3, 300.0: 1e-3],
            warnings: []
        )
        store.setFieldSweepSeriesOrder(visualOrder)
        store.tabs.activeTab = .fieldSweep1omega
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            hiddenSeriesKeys: [hiddenKey],
            seriesOrder: visualOrder
        )
        store.tabs.tabStates[.fieldSweep3omega] = TabRenderState(seriesOrder: visualOrder)

        store.rerenderFieldSweepTabs()
        guard await waitForFieldSweepOutputs(store) else {
            Issue.record("Timed out waiting for 3ω field-sweep rerender with hidden series")
            return
        }

        let out1 = try #require(store.tabs.output(for: .fieldSweep1omega))
        let out3 = try #require(store.tabs.output(for: .fieldSweep3omega))
        let manifest1 = try #require(out1.manifestPayload)
        let manifest3 = try #require(out3.manifestPayload)
        let display1 = try #require(out1.displayPayload)
        let display3 = try #require(out3.displayPayload)
        let expected1 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualOrder, series: manifest1.series)
        let expected3 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualOrder, series: manifest3.series)
        let hiddenExpected1 = expected1.filter { $0 != hiddenKey }

        #expect(manifest1.series.compactMap(\.sourceRef) == visualOrder)
        #expect(manifest3.series.compactMap(\.sourceRef) == visualOrder)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifest1.series).map(\.identityKey) == expected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifest3.series).map(\.identityKey) == expected3)
        #expect(manifest1.series.count == sweeps.count)
        #expect(manifest3.series.count == sweeps.count)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display1.series).map(\.identityKey) == hiddenExpected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display3.series).map(\.identityKey) == expected3)
        #expect(display1.series.count == sweeps.count - 1)
        #expect(display3.series.count == sweeps.count)
    }

    @MainActor
    @Test("3ω pack restore preserves manifest/display alignment under explicit field-sweep order")
    func packRestorePreservesManifestDisplayAlignment() async throws {
        let sweeps = [
            makeFieldSweep(sourceRef: "/tmp/100K.csv", sampleID: "100K", temperatureK: 100),
            makeFieldSweep(sourceRef: "/tmp/200K.csv", sampleID: "200K", temperatureK: 200),
            makeFieldSweep(sourceRef: "/tmp/300K.csv", sampleID: "300K", temperatureK: 300)
        ]
        let visualOrder = ["/tmp/300K.csv", "/tmp/200K.csv", "/tmp/100K.csv"]
        let hiddenKey = "3w:r1omega-vs-h:sweep:/tmp/200K.csv"

        let ingestion = ThreeOmegaIngestionResult(
            fieldSweeps: sweeps,
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100.0: 1e-3, 200.0: 1e-3, 300.0: 1e-3],
            warnings: []
        )
        let config = ThreeOmegaPackConfig(
            device: "0deg",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey,
            titleTemplate: "#tab #device #sample",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            seriesRenderMode: .line,
            tabStates: [
                ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey: TabRenderState(
                    hiddenSeriesKeys: [hiddenKey],
                    seriesOrder: visualOrder
                ),
                ThreeOmegaWorkbenchTab.fieldSweep3omega.stableKey: TabRenderState(seriesOrder: visualOrder)
            ]
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ingestion,
            scalingResult: nil
        )
        let pack = try AnalysisPack(
            label: "3ω Field Sweep Pack",
            workflowID: WorkflowKey.threeOmega.rawValue,
            filePaths: sweeps.compactMap(\.sourceFilePath),
            sampleKeys: ["100K", "200K", "300K"],
            config: config,
            result: result
        )

        let restored = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        restored.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        guard await waitForFieldSweepOutputs(restored) else {
            Issue.record("Timed out waiting for 3ω pack restore outputs")
            return
        }

        let out1 = try #require(restored.tabs.output(for: .fieldSweep1omega))
        let out3 = try #require(restored.tabs.output(for: .fieldSweep3omega))
        let manifest1 = try #require(out1.manifestPayload)
        let manifest3 = try #require(out3.manifestPayload)
        let display1 = try #require(out1.displayPayload)
        let display3 = try #require(out3.displayPayload)
        let expected1 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualOrder, series: manifest1.series)
        let expected3 = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualOrder, series: manifest3.series)
        let hiddenExpected1 = expected1.filter { $0 != hiddenKey }

        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifest1.series).map(\.identityKey) == expected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifest3.series).map(\.identityKey) == expected3)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display1.series).map(\.identityKey) == hiddenExpected1)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display3.series).map(\.identityKey) == expected3)
        #expect(manifest1.series.count == sweeps.count)
        #expect(manifest3.series.count == sweeps.count)
        #expect(display1.series.count == sweeps.count - 1)
        #expect(display3.series.count == sweeps.count)
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

    // MARK: - PR143 review bug: composite identity keys from one tab must drive the other tab's order

    @Test("bareFieldSweepSourceRefToken strips the workflowID:tabKey:seriesRole: composite prefix")
    func bareFieldSweepSourceRefTokenStripsCompositePrefix() {
        #expect(ThreeOmegaWorkspaceStore.bareFieldSweepSourceRefToken(
            "3w:r1omega-vs-h:sweep:/tmp/A.csv", workflowID: "3w"
        ) == "/tmp/A.csv")
        #expect(ThreeOmegaWorkspaceStore.bareFieldSweepSourceRefToken(
            "3w:r3omega-vs-h:sweep:/tmp/A.csv", workflowID: "3w"
        ) == "/tmp/A.csv")
        // Already-bare tokens and unrelated composite keys (e.g. RAHE) pass through unchanged.
        #expect(ThreeOmegaWorkspaceStore.bareFieldSweepSourceRefToken(
            "/tmp/A.csv", workflowID: "3w"
        ) == "/tmp/A.csv")
        #expect(ThreeOmegaWorkspaceStore.bareFieldSweepSourceRefToken(
            "3w:rahe:rahe-1omega:rahe-1omega", workflowID: "3w"
        ) == "3w:rahe:rahe-1omega:rahe-1omega")
    }

    @MainActor
    @Test("Reordering on r1omega-vs-h with composite identity keys carries to r3omega-vs-h")
    func compositeKeysFromR1omegaDriveR3omegaOrder() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [
                makeFieldSweep(sourceRef: "/tmp/A.csv", sampleID: "A", temperatureK: 5),
                makeFieldSweep(sourceRef: "/tmp/B.csv", sampleID: "B", temperatureK: 10)
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [5.0: 1e-3, 10.0: 1e-3],
            warnings: []
        )
        store.cachedInputFiles = ["/tmp/A.csv", "/tmp/B.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        // Rows committed by WorkbenchSeriesOrderPanel carry the active tab's full
        // composite identityKey, not a bare sourceRef.
        let committed = [
            "3w:r1omega-vs-h:sweep:/tmp/B.csv",
            "3w:r1omega-vs-h:sweep:/tmp/A.csv"
        ]
        store.updateSeriesOrder(committed)
        store._refreshManifestPayloads()

        let expectedBareOrder = ["/tmp/B.csv", "/tmp/A.csv"]
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == expectedBareOrder)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == expectedBareOrder)

        let manifest1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let manifest3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)
        #expect(manifest1 == expectedBareOrder)
        #expect(manifest3 == expectedBareOrder)
    }

    @MainActor
    @Test("Reordering on r3omega-vs-h with composite identity keys carries to r1omega-vs-h")
    func compositeKeysFromR3omegaDriveR1omegaOrder() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [
                makeFieldSweep(sourceRef: "/tmp/A.csv", sampleID: "A", temperatureK: 5),
                makeFieldSweep(sourceRef: "/tmp/B.csv", sampleID: "B", temperatureK: 10)
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [5.0: 1e-3, 10.0: 1e-3],
            warnings: []
        )
        store.cachedInputFiles = ["/tmp/A.csv", "/tmp/B.csv"]
        store.tabs.activeTab = .fieldSweep3omega

        let committed = [
            "3w:r3omega-vs-h:sweep:/tmp/B.csv",
            "3w:r3omega-vs-h:sweep:/tmp/A.csv"
        ]
        store.updateSeriesOrder(committed)
        store._refreshManifestPayloads()

        let expectedBareOrder = ["/tmp/B.csv", "/tmp/A.csv"]
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == expectedBareOrder)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == expectedBareOrder)

        let manifest1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let manifest3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)
        #expect(manifest1 == expectedBareOrder)
        #expect(manifest3 == expectedBareOrder)
    }

    // MARK: - Tick override propagation (v5.5.5)

    /// Regression for a bug where WorkbenchTabDisplayStateSnapshot.with(seriesOrder:) silently
    /// dropped tickOverride, so changing tick count on fieldSweep1omega/3omega never affected
    /// the rendered plot (the field-sweep tabs are the only callers of that method).
    @MainActor
    @Test("Changing tick count on fieldSweep1omega affects the rendered x-tick count")
    func fieldSweep1omegaTickOverrideAffectsRenderedTicks() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeIngestionResult()
        store.tabs.activeTab = .fieldSweep1omega

        store.tabs.clearOutputs()
        store.updateTickCount(axis: .x, count: 3)
        guard let layout3 = await waitForOutput(store, tab: .fieldSweep1omega) else {
            Issue.record("Timed out waiting for fieldSweep1omega render at tick count 3")
            return
        }
        let xTicks3 = layout3.xTicks.count

        store.tabs.clearOutputs()
        store.updateTickCount(axis: .x, count: 15)
        guard let layout15 = await waitForOutput(store, tab: .fieldSweep1omega) else {
            Issue.record("Timed out waiting for fieldSweep1omega render at tick count 15")
            return
        }
        let xTicks15 = layout15.xTicks.count

        #expect(xTicks3 != xTicks15,
                "tickOverride.x=3 vs 15 must produce a visibly different rendered x-tick count on fieldSweep1omega")
    }
}
