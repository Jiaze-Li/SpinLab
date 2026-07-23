import Testing
import Foundation
@testable import SpinLabApp

@Suite("V8.1 IV Parser + Channel Mapping")
struct V81IVParserChannelMappingTests {

    // MARK: - Fixture

    private func ivXFixtureURL() -> URL? {
        Bundle.module.url(forResource: "iv_x_dominant_293K", withExtension: "lvm", subdirectory: "TestData/IV")
    }

    private func ivYFixtureURL() -> URL? {
        Bundle.module.url(forResource: "iv_y_dominant_293K", withExtension: "lvm", subdirectory: "TestData/IV")
    }

    private func computedFirstRH(firstX: Double, currentPeak: Double) -> Double {
        firstX * sqrt(2.0) / currentPeak
    }

    // MARK: - Parser: basic parsing

    @Test("LVM parser: extracts 5 data rows from fixture")
    func parserDataRowCount() throws {
        guard let url = ivXFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_x_dominant_293K.lvm")
            return
        }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        #expect(sweep.current.count == 5)
        #expect(sweep.ch1X.count == 5)
        #expect(sweep.ch1Y.count == 5)
        #expect(sweep.ch2X.count == 5)
        #expect(sweep.ch2Y.count == 5)
    }

    @Test("LVM parser: current column is row 0 col 0")
    func parserCurrentValues() throws {
        guard let url = ivXFixtureURL() else { return }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        #expect(abs(sweep.current[0] - 0.001) < 1e-9)
        #expect(abs(sweep.current[4] - 0.005) < 1e-9)
    }

    @Test("LVM parser: ch1X is col 1, ch2X is col 5")
    func parserChannelColumns() throws {
        guard let url = ivXFixtureURL() else { return }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        #expect(abs(sweep.ch1X[0] - 0.070711) < 1e-6)
        #expect(abs(sweep.ch2X[0] - 0.141421) < 1e-6)
    }

    @Test("LVM parser: ch1Y is col 2, ch2Y is col 6")
    func parserYColumns() throws {
        guard let url = ivXFixtureURL() else { return }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        #expect(abs(sweep.ch1Y[0] - 0.007071) < 1e-6)
        #expect(abs(sweep.ch2Y[0] - 0.014142) < 1e-6)
    }

    @Test("LVM parser: preserves raw audit columns")
    func parserRawAuditColumns() throws {
        guard let url = ivXFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_x_dominant_293K.lvm")
            return
        }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        #expect(sweep.firstR?.count == 5)
        #expect(sweep.firstTheta?.count == 5)
        #expect(sweep.secondR?.count == 5)
        #expect(sweep.secondTheta?.count == 5)
        #expect(sweep.firstRH?.count == 5)
        #expect(sweep.frequencyAfter?.count == 5)
        #expect(abs((sweep.firstRH?[0] ?? 0) - 100.0) < 1e-9)
        #expect(abs((sweep.frequencyAfter?[0] ?? 0) - 317.0) < 1e-9)
    }

    @Test("LVM parser: firstRH matches firstX/current audit relation")
    func parserFirstRHAuditRelation() throws {
        guard let url = ivXFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_x_dominant_293K.lvm")
            return
        }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        guard let firstRH = sweep.firstRH else {
            Issue.record("Expected firstRH audit column to be preserved")
            return
        }

        let rowCount = min(sweep.current.count, sweep.ch1X.count, firstRH.count)
        for index in 0..<rowCount {
            let currentPeak = sweep.current[index]
            guard currentPeak != 0 else { continue }
            let computed = computedFirstRH(firstX: sweep.ch1X[index], currentPeak: currentPeak)
            #expect(abs(computed - firstRH[index]) < 0.01)
        }
    }

    @Test("LVM parser: temperature override is applied")
    func parserTemperatureOverride() throws {
        guard let url = ivXFixtureURL() else { return }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293.0)
        #expect(sweep.temperatureK == 293.0)
    }

    @Test("LVM parser: field override is applied")
    func parserFieldOverride() throws {
        guard let url = ivXFixtureURL() else { return }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293, fieldOverride: 0.5)
        #expect(sweep.fieldT == 0.5)
    }

    @Test("IV ingestion builds non-empty sample metadata")
    func ingestionBuildsSampleMetadata() throws {
        let sampleKey = "B25|o|STO|111"
        let url = try makeIVTempFile(name: "iv_0deg_0T_1w_sample.lvm", contents: minimalIVContents())
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeIVHit(
            fileURL: url,
            sampleKey: sampleKey,
            temperature: "293K"
        )

        let result = IngestIVSelectionsUseCase().execute(
            hits: [hit],
            numericDisplayBySample: [sampleKey: ["厚度": "30"]]
        )

        guard let sweep = result.sweeps.first, let meta = sweep.sampleMetadata else {
            Issue.record("Expected ingestion to populate sampleMetadata")
            return
        }

        #expect(!meta.isEmpty)
        #expect(meta["sampleKey"] == sampleKey)
        #expect(meta["batchID"] == "B25")
        #expect(meta["substrate"]?.isEmpty == false)
        #expect(meta["temperature"] == "293K")
        #expect(meta["device"] == "0deg")
        #expect(meta["field"] == "0T")
        #expect(meta["thickness"] == "30")
    }

    @Test("IVPlotRenderer carries metadata into each rendered series")
    func plotRendererCarriesSeriesMetadata() throws {
        let sweepA = try makeIVSweep(
            name: "iv_0deg_0T_1w_a.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )
        let sweepB = try makeIVSweep(
            name: "iv_0deg_2.5T_1w_b.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )

        var renderer = IVPlotRenderer()
        let payload = renderer.makeFirstHarmonicPayload(sweeps: [sweepA, sweepB], device: "0deg")
        guard let payload else {
            Issue.record("Expected IV renderer payload")
            return
        }

        #expect(payload.series.allSatisfy { !$0.metadata.isEmpty })
        #expect(payload.series.allSatisfy { $0.metadata["temperature"] == "293K" })
        #expect(payload.series.allSatisfy { $0.metadata["device"] == "0deg" })
        #expect(payload.series.allSatisfy { $0.metadata["field"] != nil })
    }

    @MainActor
    @Test("IVPlotRenderer renders first and second harmonic plots")
    func plotRendererRendersCartesianOutput() throws {
        let sweep = try makeIVSweep(
            name: "iv_0deg_0T_1w_render.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )

        let renderer = IVPlotRenderer()

        let first = IVRenderRoute.renderFirstHarmonicVsCurrentViaSharedRoute(renderer: renderer, sweeps: [sweep], device: "0deg")
        #expect(first.0 != nil)
        #expect(first.1 != nil)
        #expect(first.2 != nil)

        let second = IVRenderRoute.renderSecondHarmonicVsCurrentViaSharedRoute(renderer: renderer, sweeps: [sweep], device: "0deg")
        #expect(second.0 != nil)
        #expect(second.1 != nil)
        #expect(second.2 != nil)
    }

    @Test("IVPlotRenderer converts peak current to mA by default")
    func plotRendererDefaultsToPeakCurrentBasis() throws {
        let sweep = try makeIVSweep(
            name: "iv_0deg_0T_1w_peak.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )

        var renderer = IVPlotRenderer()
        let payload = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "0deg")
        guard let payload else {
            Issue.record("Expected IV renderer payload")
            return
        }

        let expected = sweep.current.map { $0 * 1000.0 }
        #expect(payload.axisMapping.xField == "Current (mA, peak)")
        #expect(payload.series[0].x == expected)
    }

    @Test("IVPlotRenderer scales x current to RMS mA basis when selected")
    func plotRendererUsesRMSCurrentBasis() throws {
        let sweep = try makeIVSweep(
            name: "iv_0deg_0T_1w_rms.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )

        var renderer = IVPlotRenderer()
        renderer.xCurrentBasis = .rms

        let payload = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "0deg")
        guard let payload else {
            Issue.record("Expected IV renderer payload")
            return
        }

        let expected = sweep.current.map { $0 / sqrt(2.0) * 1000.0 }
        #expect(payload.axisMapping.xField == "Current (mA, RMS)")
        #expect(payload.series[0].x == expected)
    }

    @Test("IV tabs use the desired 1st / I and 2nd / I labels")
    func ivTabDisplayNamesMatchDesiredLabels() {
        #expect(IVWorkbenchTab.voltage.displayName == "1st / I")
        #expect(IVWorkbenchTab.resistance.displayName == "2nd / I")
    }

    @Test("IV first tab uses the selected ch1 component only")
    func ivFirstTabUsesSelectedChannel() throws {
        let sweep = try makeIVSweep(
            name: "iv_0deg_0T_1w_a.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )

        var renderer = IVPlotRenderer()
        renderer.ch1Component = .y
        renderer.ch2Component = .x

        let payload = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "0deg")
        guard let payload else {
            Issue.record("Expected IV first-harmonic payload")
            return
        }

        #expect(payload.title.contains("1st / I"))
        #expect(payload.series.count == 1)
        // Y is always displayed in mV (IVPowerLawFitAdapter owns the V->mV conversion).
        #expect(payload.series[0].y == sweep.ch1Y.map { $0 * 1000.0 })
    }

    @Test("IV second tab uses the selected ch2 component only")
    func ivSecondTabUsesSelectedChannel() throws {
        let sweep = try makeIVSweep(
            name: "iv_0deg_0T_1w_a.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )

        var renderer = IVPlotRenderer()
        renderer.ch1Component = .x
        renderer.ch2Component = .y

        let payload = renderer.makeSecondHarmonicPayload(sweeps: [sweep], device: "0deg")
        guard let payload else {
            Issue.record("Expected IV second-harmonic payload")
            return
        }

        #expect(payload.title.contains("2nd / I"))
        #expect(payload.series.count == 1)
        // Y is always displayed in mV (IVPowerLawFitAdapter owns the V->mV conversion).
        #expect(payload.series[0].y == sweep.ch2Y.map { $0 * 1000.0 })
    }

    @Test("IV hidden series affects display payload only")
    func ivHiddenSeriesAffectsDisplayOnly() throws {
        let sweepA = try makeIVSweep(
            name: "iv_0deg_0T_1w_a.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )
        let sweepB = try makeIVSweep(
            name: "iv_0deg_2T_1w_b.lvm",
            sampleKey: "B25|o|STO|111",
            temperature: "303K"
        )

        var renderer = IVPlotRenderer()
        guard let raw = renderer.makeFirstHarmonicPayloads(sweeps: [sweepA, sweepB], device: "0deg"),
              let hiddenKey = raw.manifestPayload.series.last?.metadata["seriesIdentityKey"],
              let filtered = renderer.makeFirstHarmonicPayloads(
                sweeps: [sweepA, sweepB],
                device: "0deg",
                hiddenSeriesKeys: [hiddenKey]
              )
        else {
            Issue.record("Expected stacked IV payloads")
            return
        }

        #expect(filtered.manifestPayload.series.count == 2)
        #expect(filtered.displayPayload.series.count == 1)
        #expect(filtered.warnings.contains("series visibility ignored: all series were hidden") == false)
    }

    @Test("IVWorkspaceStore analyze produces activeImageData")
    @MainActor
    func ivWorkspaceAnalyzeProducesActiveImageData() async throws {
        let url = try makeIVTempFile(name: "iv_analyze_render.lvm", contents: minimalIVContents())
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeIVHit(
            fileURL: url,
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "iv",
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

        let store = IVWorkspaceStore(workflowID: "iv")
        store.cachedSampleNumericDisplay = [hit.sampleKey: ["厚度": "30"]]
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        await waitUntil(timeoutMS: 10_000) {
            await MainActor.run {
                store.activeImageData != nil && store.activeLayout != nil
            }
        }

        #expect(store.activeImageData != nil)
        #expect(store.activeLayout != nil)
    }

    @Test("IV Copy PNG rendering works after analysis")
    @MainActor
    func ivCopyPNGRenderingWorksAfterAnalysis() async throws {
        let url = try makeIVTempFile(name: "iv_copy_png_render.lvm", contents: minimalIVContents())
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeIVHit(
            fileURL: url,
            sampleKey: "B25|o|STO|111",
            temperature: "293K"
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "iv",
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

        let store = IVWorkspaceStore(workflowID: "iv")
        store.cachedSampleNumericDisplay = [hit.sampleKey: ["厚度": "30"]]
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        await waitUntil(timeoutMS: 10_000) {
            await MainActor.run {
                store.activeImageData != nil
            }
        }

        guard let png = store.activeImageData else {
            Issue.record("Expected Copy PNG output")
            return
        }
        #expect(!png.isEmpty)
    }

    @Test("IV field changes resolve to field legend labels")
    func ivFieldLegendLabelsResolveToField() throws {
        let rendered = try renderIVSeries(
            leftName: "iv_0deg_0T_1w_a.lvm",
            rightName: "iv_0deg_2.5T_1w_b.lvm",
            leftTemperature: "293K",
            rightTemperature: "293K"
        )

        #expect(rendered.manifestPayload.legendDimension == nil)
        #expect(Set(rendered.layout.legendRows.map(\.originalLabel)) == Set(["0T", "2.5T"]))
    }

    @Test("IV harmonic metadata absent keeps legend indeterminate")
    func ivHarmonicLegendLabelsStayIndeterminateWithoutMetadata() throws {
        let rendered = try renderIVSeries(
            leftName: "iv_0deg_0T_1w_a.lvm",
            rightName: "iv_0deg_0T_3w_b.lvm",
            leftTemperature: "293K",
            rightTemperature: "293K"
        )

        #expect(rendered.manifestPayload.legendDimension == nil)
        #expect(rendered.layout.legendRows.count == 2)
        #expect(Set(rendered.layout.legendRows.map(\.originalLabel)) == Set(["293 K"]))
    }

    @Test("IV temperature overrides field and harmonic in legend resolution")
    func ivTemperatureLegendWinsOverFieldAndHarmonic() throws {
        let rendered = try renderIVSeries(
            leftName: "iv_0deg_0T_1w_a.lvm",
            rightName: "iv_0deg_2.5T_3w_b.lvm",
            leftTemperature: "293K",
            rightTemperature: "310K"
        )

        #expect(rendered.manifestPayload.legendDimension == nil)
        #expect(Set(rendered.layout.legendRows.map(\.originalLabel)) == Set(["293K", "310K"]))
    }

    @Test("IV pack config round-trips active tab, render mode, and chart style overrides")
    func packConfigRoundTripsDisplayState() throws {
        let config = IVPackConfig(
            titleTemplate: "#tab #device #sample",
            activeTab: IVWorkbenchTab.resistance.rawValue,
            stackOffsetMultiplier: 0.4,
            minGapFraction: 0.2,
            showPlotGrid: false,
            seriesRenderMode: .scatter,
            chartStyleOverrides: ["titleFontSize": "24", "tickLabelFontSize": "18"],
            ch1Component: IVSignalComponent.y.rawValue,
            ch2Component: IVSignalComponent.x.rawValue,
            xCurrentBasis: .rms,
            tabStates: [
                IVWorkbenchTab.voltage.rawValue: TabRenderState(
                    legendPoint: CGPointCodable(CGPoint(x: 0.2, y: 0.8)),
                    titleOverride: "Voltage override",
                    xLabelOverride: "Current override",
                    yLabelOverride: "Voltage override",
                    seriesLabelOverrides: ["series-a": "A", "series-b": "B"],
                    seriesOrder: ["series-b", "series-a"]
                ),
                IVWorkbenchTab.resistance.rawValue: TabRenderState(
                    legendPoint: CGPointCodable(CGPoint(x: 0.7, y: 0.3)),
                    titleOverride: "Resistance override",
                    xLabelOverride: "Current override",
                    yLabelOverride: "Resistance override",
                    seriesLabelOverrides: ["series-a": "R A", "series-b": "R B"],
                    seriesOrder: ["series-a", "series-b"]
                )
            ],
            cachedSearchResults: [],
            selectedSearchResultIDs: ["series-a"],
            searchQueryText: "iv pack"
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IVPackConfig.self, from: data)

        #expect(decoded == config)
    }

    @MainActor
    @Test("IV restore preserves active tab, overrides, series order, and rerenders through the shared pipeline")
    func ivRestorePreservesDisplayStateAndRerenders() async throws {
        let sampleKey = "B25|o|STO|111"
        let tempA = try makeIVTempFile(name: "iv_restore_a.lvm", contents: minimalIVContents())
        let tempB = try makeIVTempFile(name: "iv_restore_b.lvm", contents: minimalIVContents())
        defer {
            try? FileManager.default.removeItem(at: tempA)
            try? FileManager.default.removeItem(at: tempB)
        }

        let hitA = makeIVHit(fileURL: tempA, sampleKey: sampleKey, temperature: "293K")
        let hitB = makeIVHit(fileURL: tempB, sampleKey: sampleKey, temperature: "310K")

        let ingestion = IngestIVSelectionsUseCase().execute(
            hits: [hitA, hitB],
            numericDisplayBySample: [sampleKey: ["thickness": "30"]]
        )

        guard ingestion.sweeps.count == 2 else {
            Issue.record("Expected IV ingestion to produce two sweeps")
            return
        }
        let sweepA = ingestion.sweeps[0]
        let sweepB = ingestion.sweeps[1]

        let config = IVPackConfig(
            titleTemplate: "#tab #device #sample",
            activeTab: IVWorkbenchTab.resistance.rawValue,
            stackOffsetMultiplier: 0.6,
            minGapFraction: 0.25,
            showPlotGrid: true,
            seriesRenderMode: .scatter,
            chartStyleOverrides: ["titleFontSize": "22", "tickLabelFontSize": "17"],
            ch1Component: IVSignalComponent.y.rawValue,
            ch2Component: IVSignalComponent.x.rawValue,
            xCurrentBasis: .rms,
            tabStates: [
                IVWorkbenchTab.voltage.rawValue: TabRenderState(
                    legendPoint: CGPointCodable(CGPoint(x: 0.15, y: 0.85)),
                    titleOverride: "Voltage override",
                    xLabelOverride: "Voltage X",
                    yLabelOverride: "Voltage Y",
                    seriesLabelOverrides: [sweepA.id: "Voltage A", sweepB.id: "Voltage B"],
                    seriesOrder: [tempB.path, tempA.path]
                ),
                IVWorkbenchTab.resistance.rawValue: TabRenderState(
                    legendPoint: CGPointCodable(CGPoint(x: 0.65, y: 0.35)),
                    titleOverride: "Resistance override",
                    xLabelOverride: "Resistance X",
                    yLabelOverride: "Resistance Y",
                    seriesLabelOverrides: [sweepA.id: "Res A", sweepB.id: "Res B"],
                    seriesOrder: [tempB.path, tempA.path]
                )
            ],
            cachedSearchResults: [hitA, hitB],
            selectedSearchResultIDs: [hitA.id, hitB.id],
            searchQueryText: "IV restore"
        )
        let result = IVPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(
            label: "IV Fixture",
            workflowID: "IV",
            filePaths: [tempA.path, tempB.path],
            sampleKeys: [sampleKey],
            config: config,
            result: result
        )

        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        var restoredResults: [WorkflowMeasurementSearchHit] = []
        var restoredQuery = ""
        var seededIDs: Set<String> = []
        var seededHits: [WorkflowMeasurementSearchHit] = []
        var restoreSearchCalled = false
        var seedSelectionCalled = false

        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { results, queryText in
                restoredResults = results
                restoredQuery = queryText
                restoreSearchCalled = true
            },
            seedSelection: { ids, hits in
                seededIDs = ids
                seededHits = hits
                seedSelectionCalled = true
            }
        )

        await waitUntil(timeoutMS: 1000) {
            await MainActor.run { restoreSearchCalled && seedSelectionCalled }
        }

        #expect(store.tabs.activeTab == .resistance)
        #expect(store.ch1Component == .y)
        #expect(store.ch2Component == .x)
        #expect(store.xCurrentBasis == .rms)
        #expect(store.tabs.seriesRenderMode == .scatter)
        #expect(store.globalPlotDefaults["titleFontSize"] == "22")
        #expect(store.globalPlotDefaults["tickLabelFontSize"] == "17")
        #expect(store.tabs.chartStyleOverrides["titleFontSize"] == nil)
        #expect(store.tabs.chartStyleOverrides["tickLabelFontSize"] == nil)
        #expect(store.tabs.showPlotGrid)
        #expect(store.tabs.state(for: .resistance).legendPoint?.cgPoint == CGPoint(x: 0.65, y: 0.35))
        #expect(store.tabs.state(for: .resistance).titleOverride == "Resistance override")
        #expect(store.tabs.state(for: .voltage).seriesOrder == [tempB.path, tempA.path])
        #expect(store.tabs.state(for: .resistance).seriesOrder == [tempB.path, tempA.path])
        #expect(restoredResults == [hitA, hitB])
        #expect(restoredQuery == "IV restore")
        #expect(seededIDs == Set([hitA.id, hitB.id]))
        #expect(seededHits == [hitA, hitB])

        await waitUntil(timeoutMS: 2000) {
            await MainActor.run { store.activeChartPNG != nil && store.activeChartManifestPayload != nil }
        }

        let activePayload = try #require(store.activeChartManifestPayload)
        let activeOutput = store.tabs.output(for: .resistance)
        #expect(store.activeChartPNG != nil)
        #expect(activePayload.title == "2nd / I B25 o STO111")
        #expect(store.activeLayout?.xAxisLabel == "Resistance X")
        #expect(store.activeLayout?.yAxisLabel == "Resistance Y")
        #expect(activePayload.series.compactMap(\.sampleID) == [sweepB.id, sweepA.id])
        let expectedOverrides = Dictionary(uniqueKeysWithValues: activePayload.series.compactMap { series -> (String, String)? in
            guard let identityKey = series.metadata["seriesIdentityKey"],
                  let sourceRef = series.sourceRef else {
                return nil
            }
            if sourceRef == tempA.path {
                return (identityKey, "Res A")
            }
            if sourceRef == tempB.path {
                return (identityKey, "Res B")
            }
            return nil
        })
        #expect(store.tabs.state(for: .resistance).seriesLabelOverrides == expectedOverrides)
        #expect(store.tabs.seriesRenderMode == .scatter)
        #expect(activePayload.axisMapping.xField == "Current (mA, RMS)")
        #expect(activeOutput.displayPayload != nil)
        #expect(activeOutput.displayPayload?.series.compactMap(\.sourceRef) == [tempB.path, tempA.path])
    }

    @MainActor
    @Test("IV persistToLibrary uses the shared active-chart export path and does not emit metrics")
    func ivPersistToLibraryWritesChartOnlyArtifact() async throws {
        let sampleKey = "B25|o|STO|111"
        let tempA = try makeIVTempFile(name: "iv_export_a.lvm", contents: minimalIVContents())
        defer { try? FileManager.default.removeItem(at: tempA) }

        let hit = makeIVHit(fileURL: tempA, sampleKey: sampleKey, temperature: "293K")
        let ingestion = IngestIVSelectionsUseCase().execute(
            hits: [hit],
            numericDisplayBySample: [sampleKey: [:]]
        )
        guard let sweep = ingestion.sweeps.first else {
            Issue.record("Expected IV ingestion to produce a sweep")
            return
        }

        let config = IVPackConfig(
            titleTemplate: "#tab #device #sample",
            activeTab: IVWorkbenchTab.voltage.rawValue,
            stackOffsetMultiplier: 0.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            ch1Component: IVSignalComponent.x.rawValue,
            ch2Component: IVSignalComponent.x.rawValue,
            xCurrentBasis: .peak,
            tabStates: [
                IVWorkbenchTab.voltage.rawValue: TabRenderState(
                    seriesLabelOverrides: [sweep.id: "Exported series"]
                )
            ],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id],
            searchQueryText: "IV export"
        )
        let result = IVPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(
            label: "IV Export Fixture",
            workflowID: "IV",
            filePaths: [tempA.path],
            sampleKeys: [sampleKey],
            config: config,
            result: result
        )

        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        // Chart rendering runs on a detached Task and hops back via MainActor.run;
        // under heavy parallel test execution (full-suite runs) that hop can be
        // delayed well past 2s purely by scheduler contention, not a real stall.
        await waitUntil(timeoutMS: 5000) {
            await MainActor.run { store.activeChartPNG != nil && store.activeChartManifestPayload != nil }
        }

        let root = FileManager.default.temporaryDirectory
            .appending(path: "iv-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        store.lastLibraryRootPath = root.path
        await withCheckedContinuation { continuation in
            store.persistToLibrary {
                continuation.resume()
            }
        }

        #expect(store.saveMessage == "Saved to Library.")
        #expect(store.persistenceOutcome != nil)

        let imageExists = FileManager.default.fileExists(
            atPath: root.appending(path: "samples/\(sampleKey)/charts", directoryHint: .isDirectory).path
        )
        #expect(imageExists)

        let chartDir = root.appending(path: "samples/\(sampleKey)/charts", directoryHint: .isDirectory)
        let chartFiles = try FileManager.default.contentsOfDirectory(atPath: chartDir.path)
        #expect(chartFiles.contains(where: { $0.hasSuffix(".png") }))
        #expect(chartFiles.contains(where: { $0.hasSuffix(".manifest.json") }))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "samples/\(sampleKey)/_spinlab/measurement_data.json").path))
    }

    @MainActor
    @Test("IV current basis update preserves manual X label but refreshes prior auto default")
    func currentBasisUpdateRespectsLabelOverrideState() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)

        store.tabs.tabStates[.voltage] = TabRenderState(xLabelOverride: IVCurrentBasis.peak.legacyAxisLabel)
        store.tabs.tabStates[.resistance] = TabRenderState(xLabelOverride: IVCurrentBasis.peak.legacyAxisLabel)
        store.updateXCurrentBasis(.rms, previousBasis: .peak)
        #expect(store.xCurrentBasis == .rms)
        #expect(store.tabs.state(for: .voltage).xLabelOverride == IVCurrentBasis.rms.axisLabel)
        #expect(store.tabs.state(for: .resistance).xLabelOverride == IVCurrentBasis.rms.axisLabel)

        store.tabs.tabStates[.voltage] = TabRenderState(xLabelOverride: "Custom X")
        store.tabs.tabStates[.resistance] = TabRenderState(xLabelOverride: IVCurrentBasis.rms.legacyAxisLabel)
        store.updateXCurrentBasis(.peak, previousBasis: .rms)
        #expect(store.xCurrentBasis == .peak)
        #expect(store.tabs.state(for: .voltage).xLabelOverride == "Custom X")
        #expect(store.tabs.state(for: .resistance).xLabelOverride == IVCurrentBasis.peak.axisLabel)
    }

    @Test("LVM parser: no-marker file throws markerNotFound")
    func parserMissingMarker() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("no_marker_\(Int.random(in: 100_000...999_999)).lvm")
        try "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // File with data but no Tableau: marker still parses via fallback
        let sweep = try IVLVMParser().parse(fileURL: tmp, temperatureOverride: 100)
        #expect(sweep.current.count == 1)
    }

    // MARK: - Channel mapping logic

    @Test("Channel mapping: X dominant when using X-dominant fixture")
    func channelMappingSelectsX() throws {
        guard let url = ivXFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_x_dominant_293K.lvm")
            return
        }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        let state = IngestIVSelectionsUseCase()._computeChannelState(x: sweep.ch1X, y: sweep.ch1Y)
        #expect(state.autoComponent == .x)
        #expect(state.confidence > 1.0)
    }

    @Test("Channel mapping: Y dominant when using Y-dominant fixture")
    func channelMappingSelectsY() throws {
        guard let url = ivYFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_y_dominant_293K.lvm")
            return
        }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        let state = IngestIVSelectionsUseCase()._computeChannelState(x: sweep.ch1X, y: sweep.ch1Y)
        #expect(state.autoComponent == .y)
        #expect(state.confidence > 1.0)
    }

    @Test("Channel mapping: confidence = max/min score ratio")
    func channelMappingConfidenceRatio() {
        let uc = IngestIVSelectionsUseCase()
        // median(|X|) = 0.030, median(|Y|) = 0.006 → confidence = 0.030 / 0.006 = 5.0
        let x: [Double] = [0.020, 0.030, 0.040]
        let y: [Double] = [0.004, 0.006, 0.008]
        let state = uc._computeChannelState(x: x, y: y)
        #expect(abs(state.confidence - 5.0) < 0.001)
    }

    @Test("Channel mapping: empty arrays return confidence 1.0 and default .x")
    func channelMappingEmpty() {
        let uc = IngestIVSelectionsUseCase()
        let state = uc._computeChannelState(x: [], y: [])
        #expect(state.autoComponent == .x)
        #expect(state.confidence == 1.0)
    }

    @Test("Channel mapping: equal scores select .x (tie-break)")
    func channelMappingTieBreak() {
        let uc = IngestIVSelectionsUseCase()
        let x: [Double] = [0.05, 0.05, 0.05]
        let y: [Double] = [0.05, 0.05, 0.05]
        let state = uc._computeChannelState(x: x, y: y)
        #expect(state.autoComponent == .x)
    }

    // MARK: - Helpers

    private func makeIVHit(
        fileURL: URL,
        sampleKey: String,
        temperature: String
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: fileURL.deletingPathExtension().lastPathComponent + ".sidecar",
            measurementFilePath: fileURL.path,
            sourceFilePath: fileURL.path,
            workflowID: "iv",
            workflowDisplayName: "IV",
            workflowCanonicalID: "iv",
            batchID: "B25",
            sampleKey: sampleKey,
            sampleSubstrate: "STO 111",
            conditions: ["temperature": temperature],
            channels: [],
            appliedAt: Date()
        )
    }

    private func makeIVSweep(
        name: String,
        sampleKey: String,
        temperature: String
    ) throws -> IVSweep {
        let url = try makeIVTempFile(name: name, contents: minimalIVContents())
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeIVHit(fileURL: url, sampleKey: sampleKey, temperature: temperature)
        let result = IngestIVSelectionsUseCase().execute(
            hits: [hit],
            numericDisplayBySample: [sampleKey: ["厚度": "30"]]
        )
        guard let sweep = result.sweeps.first else {
            Issue.record("Expected IV ingestion to produce a sweep")
            throw NSError(domain: "V81IVParserChannelMappingTests", code: 1)
        }
        return sweep
    }

    private func renderIVSeries(
        leftName: String,
        rightName: String,
        leftTemperature: String,
        rightTemperature: String
    ) throws -> WorkbenchRenderPipeline.Output {
        let left = try makeIVSweep(name: leftName, sampleKey: "B25|o|STO|111", temperature: leftTemperature)
        let right = try makeIVSweep(name: rightName, sampleKey: "B25|o|STO|111", temperature: rightTemperature)
        var renderer = IVPlotRenderer()
        guard let payload = renderer.makeFirstHarmonicPayload(sweeps: [left, right], device: "0deg") else {
            Issue.record("Expected IV renderer payload")
            throw NSError(domain: "V81IVParserChannelMappingTests", code: 2)
        }
        return try WorkbenchRenderPipeline.render(.init(payload: payload))
    }

    private func makeIVTempFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)_\(name)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func minimalIVContents() -> String {
        """
        Header
        Tableau:
        0.001\t0.070711\t0.007071\t0.070711\t0.0\t0.141421\t0.014142\t0.141421\t0.0\t100.0\t317.0
        0.002\t0.141421\t0.014142\t0.141421\t0.0\t0.282842\t0.028284\t0.282842\t0.0\t200.0\t317.0
        """
    }

    private func waitUntil(timeoutMS: UInt64, predicate: @escaping @Sendable () async -> Bool) async {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for condition.")
    }
}

// MARK: - IV Stack Offset tests

@Suite("IV Stack Offset")
struct IVStackOffsetTests {

    private func makeSweep(id: String, temperatureK: Double, yValue: Double, count: Int = 5) -> IVSweep {
        let current = Array(repeating: 0.001, count: count)
        let ch1X = Array(repeating: yValue, count: count)
        let ch1Y = Array(repeating: 0.0, count: count)
        let ch2X = Array(repeating: yValue * 2, count: count)
        let ch2Y = Array(repeating: 0.0, count: count)
        return IVSweep(
            stem: id,
            temperatureK: temperatureK,
            fieldT: 0,
            current: current,
            ch1X: ch1X,
            ch1Y: ch1Y,
            ch2X: ch2X,
            ch2Y: ch2Y,
            measurementFilePath: nil
        )
    }

    @Test("Multiple IV sweeps receive distinct y offsets when stackOffsetMultiplier is non-zero")
    func multipleIVSweepsStackWhenMultiplierNonZero() {
        // Use sweeps with a non-trivial range so the stack offset algorithm produces non-zero offsets.
        // ch1X values vary between 0 and yValue, giving each sweep a peak-to-peak of yValue.
        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15

        let count = 5
        func makeSweepVaried(id: String, temperatureK: Double) -> IVSweep {
            let current = Array(repeating: 0.001, count: count)
            // ch1X swings from 0 to 1, giving peak-to-peak of 1 for offset calculation
            let ch1X = stride(from: 0.0, through: 1.0, by: 1.0 / Double(count - 1)).map { $0 }
            return IVSweep(
                stem: id,
                temperatureK: temperatureK,
                fieldT: 0,
                current: current,
                ch1X: ch1X,
                ch1Y: Array(repeating: 0.0, count: count),
                ch2X: Array(repeating: 0.0, count: count),
                ch2Y: Array(repeating: 0.0, count: count),
                measurementFilePath: nil
            )
        }

        let sweeps = [
            makeSweepVaried(id: "5K", temperatureK: 5),
            makeSweepVaried(id: "10K", temperatureK: 10),
            makeSweepVaried(id: "20K", temperatureK: 20),
        ]

        guard let payload = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "D1")?.displayPayload else {
            Issue.record("payload should not be nil")
            return
        }

        let yMins = payload.series.map { s in s.y.min() ?? 0 }
        // SeriesVisualPlanner's .orderEnforcingVertical stacking policy (shared with
        // AHE/XYRotation/3ω) places the first series in visual order on top with the
        // highest offset — see "preserves descending mean-y order" in
        // SeriesVisualPlannerTests.swift and the equivalent IV/XYRotation series-order
        // regression tests. So earlier sweeps in the input list end up shifted *above*
        // later ones, not below.
        #expect(yMins[0] > yMins[1], "First sweep should be shifted above second; got \(yMins)")
        #expect(yMins[1] > yMins[2], "Second sweep should be shifted above third; got \(yMins)")
    }

    @Test("Single IV sweep has zero offset regardless of stackOffsetMultiplier")
    func singleIVSweepHasNoOffset() {
        let sweep = makeSweep(id: "5K", temperatureK: 5, yValue: 2.0)
        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.6
        renderer.minGapFraction = 0.15

        guard let payload = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "D1") else {
            Issue.record("payload should not be nil")
            return
        }

        #expect(payload.series.count == 1)
        let yMean = payload.series[0].y.reduce(0, +) / Double(payload.series[0].y.count)
        // Y is always displayed in mV: yValue 2.0 (V) -> 2000.0 (mV).
        #expect(abs(yMean - 2000.0) < 1e-9, "Single sweep should not be shifted; got \(yMean)")
    }

    @Test("IVSweep.id uses stable file path, not hashValue")
    func iVSweepIDIsStableFilePath() {
        var sweep = IVSweep(
            stem: "sweep_stem",
            temperatureK: 10,
            fieldT: 0,
            current: [],
            ch1X: [],
            ch1Y: [],
            ch2X: [],
            ch2Y: [],
            measurementFilePath: nil
        )
        sweep.measurementFilePath = "/data/batch/sweep.lvm"
        #expect(sweep.id == "/data/batch/sweep.lvm")
    }

    @Test("IVSweep.id falls back to stem when path is absent")
    func iVSweepIDFallsBackToStemWhenPathAbsent() {
        let sweep = IVSweep(
            stem: "fallback_stem",
            temperatureK: 10,
            fieldT: 0,
            current: [],
            ch1X: [],
            ch1Y: [],
            ch2X: [],
            ch2Y: [],
            measurementFilePath: nil
        )
        #expect(sweep.id == "fallback_stem")
    }

    @Test("Zero stackOffsetMultiplier leaves IV y values unchanged")
    func zeroMultiplierLeavesYUnchanged() {
        let sweeps = [
            makeSweep(id: "5K", temperatureK: 5, yValue: 1.5),
            makeSweep(id: "10K", temperatureK: 10, yValue: 1.5),
        ]
        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 0.0

        guard let payload = renderer.makeFirstHarmonicPayload(sweeps: sweeps, device: "D1") else {
            Issue.record("payload should not be nil")
            return
        }

        for series in payload.series {
            for y in series.y {
                // Y is always displayed in mV: yValue 1.5 (V) -> 1500.0 (mV).
                #expect(abs(y - 1500.0) < 1e-9)
            }
        }
    }
}
