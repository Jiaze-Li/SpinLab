import Foundation
import Testing
@testable import SpinLabApp

/// Pack / Restore through the shared Controls Surface: restored state must come back into the
/// controls and produce the same plot result as setting it live (spec 06 CS-28, AC6).
@MainActor
@Suite("Controls adapters — Pack/Restore (real stores)", .rulesGlobalState)
struct ControlsRestoreTests {
    private func descriptor(_ kind: WorkbenchWorkflowKind, _ appState: SpinLabAppState) -> WorkbenchControlsDescriptor {
        kind.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
    }

    // MARK: XY Rotation — Center / Detrend / x=180

    private func xySweeps() -> [XYRotationAngleSweep] {
        [XYRotationAngleSweep(
            temperatureK: 80, stem: "sweep-A", sourceKind: .lvm,
            angleDeg: [0, 45, 90, 135, 180, 225, 270, 315],
            resistanceXX: [10.0, 10.4, 11.1, 11.9, 12.6, 13.1, 13.9, 14.2],
            resistanceXY: [1.0, 1.5, 1.2, 2.0, 2.2, 2.9, 3.1, 3.6],
            defaultPhiOffset: 0, measurementFilePath: "/tmp/sweep-A.lvm")]
    }

    private func xyConfig(center: Bool, detrend: Bool, line180: Bool) -> XYRotationPackConfig {
        XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: center, linearDetrend: detrend,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue, titleTemplate: "#tab",
            minGapFraction: 0.15, showPlotGrid: true,
            showAuxiliaryLine180: line180, legendAnchor: "", seriesRenderMode: .lineAndScatter)
    }

    private func restoreXY(_ config: XYRotationPackConfig) throws -> XYRotationWorkspaceStore {
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult(sweeps: xySweeps(), device: "dev"))
        let pack = try AnalysisPack(label: "XY", workflowID: WorkflowKey.xyRotation.rawValue,
                                    filePaths: ["/tmp/sweep-A.lvm"], sampleKeys: [], config: config, result: result)
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let vault = AnalysisVault()
        vault.add(pack)
        store.vault = vault
        store.restoreFromPack(config: config, result: result, pack: pack,
                              restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
        return store
    }

    private func settledImage(_ store: XYRotationWorkspaceStore) async throws -> Data {
        for _ in 0..<250 where store.activeImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 300_000_000)
        return try #require(store.activeImageData)
    }

    @Test("XY Rotation: Center, Detrend and x=180 survive Pack/Restore and drive the restored plot")
    func xyRestoreRestoresFlagsAndPlot() async throws {
        let plain = try restoreXY(xyConfig(center: false, detrend: false, line180: false))
        let corrected = try restoreXY(xyConfig(center: true, detrend: true, line180: true))
        #expect(corrected.centerBaseline && corrected.linearDetrend && corrected.showAuxiliaryLine180)
        #expect(!plain.centerBaseline && !plain.linearDetrend && !plain.showAuxiliaryLine180)

        let plainImage = try await settledImage(plain)
        let restoredImage = try await settledImage(corrected)
        #expect(plainImage != restoredImage, "the restored corrections must change the figure")

        // Setting the same corrections live (what a user click does) yields the same figure.
        let live = try restoreXY(xyConfig(center: false, detrend: false, line180: false))
        _ = try await settledImage(live)
        live.centerBaseline = true; live.linearDetrend = true; live.showAuxiliaryLine180 = true
        live.rerenderForStyleChange()
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(try await settledImage(live) == restoredImage, "restored plot must equal the live plot")

        // The restored values reach the Specific controls through the adapter.
        let appState = SpinLabAppState()
        let groups = appState.workbench.xyRotationWorkspace.controlsSpecificContent(appState: appState).groups.map(\.id)
        #expect(groups == ["dataCorrection", "plotAnnotation", "calibration"])
    }

    // MARK: 3ω — Plot Mode after restore

    @Test("3ω: the Plot Mode after restore follows the restored tab")
    func threeOmegaRestoredPlotMode() throws {
        for (tab, mode) in [(ThreeOmegaWorkbenchTab.temperatureDependence, WorkbenchPlotMode.dualAxis),
                            (.scaling, .cartesianXY), (.rahe1omegaVsDevice, .cartesianXY)] {
            let config = ThreeOmegaPackConfig(
                device: "device", geometry: ThreeOmegaGeometry(), fitRanges: [],
                v3Method: ThreeOmegaV3Method.highField.rawValue,
                rahe1Method: ThreeOmegaV3Method.highField.rawValue,
                rahe3Method: ThreeOmegaV3Method.highField.rawValue,
                rtFilePath: nil, sampleBatchAndSubstrate: "sample", activeTab: tab.stableKey,
                titleTemplate: "title", minGapFraction: 0.15,
                showPlotGrid: true, plotLegendAnchor: "", seriesRenderMode: .lineAndScatter)
            let result = ThreeOmegaPackResult(
                ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "device"),
                scalingResult: nil)
            let pack = try AnalysisPack(label: "3ω", workflowID: WorkflowKey.threeOmega.rawValue,
                                        filePaths: [], sampleKeys: [], config: config, result: result)
            let appState = SpinLabAppState()
            let store = appState.workbench.threeOmegaWorkspace
            let vault = AnalysisVault()
            vault.add(pack)
            store.vault = vault
            store.restoreFromPack(config: config, result: result, pack: pack,
                                  restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
            #expect(store.tabs.activeTab == tab)
            let d = descriptor(.threeOmega, appState)
            #expect(d.plot.mode == mode, "\(tab)")
            let groups = d.specific.groups.map(\.id)
            #expect(groups.contains("transportGeometry") == (tab == .scaling || tab == .temperatureDependence), "\(tab)")
        }
    }

    // MARK: AFM — plot settings and state after restore

    @Test("AFM: processing, scale bar and display settings restore into the controls and the figure")
    func afmRestoreRestoresControls() async throws {
        let n = 24
        let xs = (0..<n).map { Double($0) * 0.2 }
        let values = xs.map { y in xs.map { x in sin(x) + cos(y) + 0.1 * x } }
        let channel = CanonicalAFMChannel(
            id: "c", sourceIndex: 0, sourceLabel: "HeightTrace", semanticTypeRaw: "Height", displayLabel: "HeightTrace",
            values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil))
        let dataset = CanonicalAFMDataset(
            sourceRef: "/x.ibw", title: "T", xCoordinates: xs, yCoordinates: xs, channels: [channel],
            sourceMetadata: AFMSourceProvenance(sourceFilePath: "/x.ibw", waveName: "T", sourceWidth: n, sourceHeight: n, rawNote: ""))
        let result = AFMPackResult(canonicalDataset: dataset)

        func restore(processing: AFMProcessingConfiguration, bar: AFMScaleBarSetting,
                     display: HeatmapTabRenderState) async throws -> (AFMWorkspaceStore, Data) {
            let config = AFMPackConfig(packState: AFMPackState(processingConfiguration: processing, scaleBar: bar), displayState: display)
            let pack = AnalysisPack(label: "t", workflowID: "afm", filePaths: ["/x.ibw"], sampleKeys: ["k"], sourceFingerprint: "f",
                                    config: try JSONEncoder().encode(config), result: try JSONEncoder().encode(result))
            let store = AFMWorkspaceStore(workflowID: "afm")
            store.restoreFromPack(config: config, result: result, pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
            for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(store.packRestoreErrorMessage == nil)
            return (store, try #require(store.renderedImageData))
        }

        var display = HeatmapTabRenderState()
        display.showTitle = false
        display.colorScaleMode = .log10
        let processed = AFMProcessingConfiguration(activeChannelID: "c", surfaceLevel: .plane, lineFlattenOrder: .order1, zeroReference: .mean)
        let bar = AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2, color: .black)
        let (store, restoredImage) = try await restore(processing: processed, bar: bar, display: display)
        let (_, plainImage) = try await restore(
            processing: AFMProcessingConfiguration(activeChannelID: "c"), bar: AFMScaleBarSetting(mode: .off), display: HeatmapTabRenderState())

        #expect(store.processingConfiguration == processed)
        #expect(store.scaleBar == bar)
        #expect(store.heatmapDisplayState.showTitle == false)
        #expect(store.heatmapDisplayState.colorScaleMode == .log10)
        #expect(restoredImage != plainImage, "restored processing/scale bar/colour scale must show in the figure")

        // The controls reflect the restored state.
        let appState = SpinLabAppState()
        let afm = appState.workbench.afmWorkspace
        afm.processingConfiguration = processed
        afm.scaleBar = bar
        afm.heatmapDisplayState = display
        let d = descriptor(.afm, appState)
        #expect(d.common.showTitle == false)
        guard case .heatmap(let plot) = d.plot else { Issue.record("AFM must be heatmap"); return }
        #expect(plot.colorScaleMode == .log10)
        let decoration = d.specific.groups.first { $0.id == "plotDecoration" }
        #expect(decoration?.rows.map(\.id) == ["scaleBar", "barText", "barLength"])
    }

    // MARK: AFM — Clear Plot resets processing (pre-existing behaviour)

    @Test("AFM Clear Plot resets processing to defaults; this is the store's existing behaviour")
    func afmClearPlotResetsProcessing() {
        let store = AFMWorkspaceStore(workflowID: "afm")
        store.processingConfiguration = AFMProcessingConfiguration(activeChannelID: "c", surfaceLevel: .plane)
        store.clearPlot()
        #expect(store.processingConfiguration == AFMProcessingConfiguration(activeChannelID: ""))
        #expect(store.processingConfiguration.surfaceLevel == .off)
    }

    // MARK: Heatmap Title Template — real AFM / RSM data (CS-9, CS-9a)

    private static let rsmScan = """
    # RSM scan — HL plane, K=0 fixed
    H        K        L        Detector
    -1.0     0.0      1.0      100.0
     0.0     0.0      1.0      200.0
     1.0     0.0      1.0      150.0
    -1.0     0.0      1.5      110.0
     0.0     0.0      1.5      250.0
     1.0     0.0      1.5      180.0
    -1.0     0.0      2.0       90.0
     0.0     0.0      2.0      300.0
     1.0     0.0      2.0      120.0
    """

    private func searchHit(sampleKey: String, file: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: file + ".spinlab.json", measurementFilePath: file, sourceFilePath: file, workflowID: "afm",
            workflowDisplayName: "AFM", workflowCanonicalID: "afm", batchID: "b", sampleKey: sampleKey,
            sampleSubstrate: "s", conditions: [:], channels: [], appliedAt: .distantPast)
    }

    private func afmFigure(display: HeatmapTabRenderState, search: [WorkflowMeasurementSearchHit] = [],
                           analyzed: WorkflowMeasurementSearchHit? = nil,
                           numeric: [String: String]? = nil) async throws -> (AFMWorkspaceStore, Data) {
        let n = 24
        let xs = (0..<n).map { Double($0) * 0.2 }
        let values = xs.map { y in xs.map { x in sin(x) + cos(y) + 0.1 * x } }
        let channel = CanonicalAFMChannel(
            id: "c", sourceIndex: 0, sourceLabel: "HeightTrace", semanticTypeRaw: "Height", displayLabel: "HeightTrace",
            values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil))
        let dataset = CanonicalAFMDataset(
            sourceRef: "/x.ibw", title: "T", xCoordinates: xs, yCoordinates: xs, channels: [channel],
            sourceMetadata: AFMSourceProvenance(sourceFilePath: "/x.ibw", waveName: "T", sourceWidth: n, sourceHeight: n, rawNote: ""))
        let result = AFMPackResult(canonicalDataset: dataset)
        let config = AFMPackConfig(
            packState: AFMPackState(processingConfiguration: AFMProcessingConfiguration(activeChannelID: "c"), scaleBar: AFMScaleBarSetting(mode: .off)),
            displayState: display, cachedSearchResults: search, analyzedHit: analyzed, analyzedNumericDisplay: numeric)
        let pack = AnalysisPack(label: "t", workflowID: "afm", filePaths: ["/x.ibw"], sampleKeys: [analyzed?.sampleKey ?? "k"], sourceFingerprint: "f",
                                config: try JSONEncoder().encode(config), result: try JSONEncoder().encode(result))
        let store = AFMWorkspaceStore(workflowID: "afm")
        store.restoreFromPack(config: config, result: result, pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
        for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        return (store, try #require(store.renderedImageData))
    }

    @Test("AFM: title tokens follow the analyzed hit, not the first search result (restore, pack round-trip, old packs)")
    func afmTitleTokensBindToAnalyzedHit() async throws {
        let a = searchHit(sampleKey: "PN31|b|STO|111", file: "/a.ibw")
        let b = searchHit(sampleKey: "PN45|c|LAO|001", file: "/x.ibw")   // the file the pack analyzed
        #expect(a.sampleBatchAndSubstrate != b.sampleBatchAndSubstrate)
        var display = HeatmapTabRenderState()
        display.titleTemplate = "#sample"

        // Search order [A, B] with B analyzed renders B's title, identical to a search list of B alone.
        let (store, figureB) = try await afmFigure(display: display, search: [a, b], analyzed: b)
        let (_, figureBOnly) = try await afmFigure(display: display, search: [b], analyzed: b)
        let (_, figureA) = try await afmFigure(display: display, search: [a, b], analyzed: a)
        #expect(figureB == figureBOnly, "title must come from the analyzed hit even when it is not first")
        #expect(figureB != figureA, "a different analyzed hit gives a different title")
        #expect(store.analyzedHit == b)

        // A pack without the analyzed hit (older pack): the source file identifies it, never the first result.
        let (legacy, figureLegacy) = try await afmFigure(display: display, search: [a, b], analyzed: nil)
        #expect(legacy.analyzedHit == b, "matched by the pack's source file")
        #expect(figureLegacy == figureB)

        // Control changes re-render with the same source.
        legacy.updateHeatmapShowColorbar(false)
        legacy.cachedSearchResults = [a]            // a later search replaced the list
        #expect(legacy.heatmapRenderState(legacy.heatmapDisplayState, hit: legacy.analyzedHit, numeric: legacy.titleNumericDisplay).titleOverride == b.sampleBatchAndSubstrate)

        // Pack config round-trips the hit and decodes without it.
        let config = AFMPackConfig(
            packState: AFMPackState(processingConfiguration: AFMProcessingConfiguration(activeChannelID: "c"), scaleBar: AFMScaleBarSetting(mode: .off)),
            displayState: display, cachedSearchResults: [a, b], analyzedHit: b)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AFMPackConfig.self, from: data).analyzedHit == b)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "analyzedHit")
        let old = try JSONDecoder().decode(AFMPackConfig.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.analyzedHit == nil && old.cachedSearchResults.count == 2)
    }

    @Test("RSM: title tokens follow the analyzed hit on restore, not the first search result")
    func rsmTitleTokensBindToAnalyzedHit() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rsm-bind-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "scan.dat")
        try Self.rsmScan.write(to: file, atomically: true, encoding: .utf8)
        let a = searchHit(sampleKey: "PN31|b|STO|111", file: "/other.dat")
        let b = searchHit(sampleKey: "PN45|c|LAO|001", file: file.path)
        var display = HeatmapTabRenderState()
        display.titleTemplate = "#sample"

        func restore(search: [WorkflowMeasurementSearchHit], analyzed: WorkflowMeasurementSearchHit?) async throws -> (RSMWorkspaceStore, Data) {
            let config = RSMPackConfig(
                packState: RSMPackState(sourceFileIdentity: file.path, detectorColumnName: "Detector", activeView: .hl),
                displayState: display, cachedSearchResults: search, analyzedHit: analyzed)
            let pack = AnalysisPack(label: "scan", workflowID: "rsm", filePaths: [file.path], sampleKeys: [b.sampleKey], sourceFingerprint: "f",
                                    config: try JSONEncoder().encode(config), result: Data("{}".utf8))
            let store = RSMWorkspaceStore(workflowID: "rsm")
            store.restoreFromPack(config: config, result: RSMPackResult(), pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
            for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            return (store, try #require(store.renderedImageData))
        }
        let (store, withFirstA) = try await restore(search: [a, b], analyzed: nil)
        let (_, bOnly) = try await restore(search: [b], analyzed: b)
        #expect(store.analyzedHit == b)
        #expect(withFirstA == bOnly, "first search result A must not supply the tokens")
        let (_, asAnalyzed) = try await restore(search: [a, b], analyzed: a)
        #expect(asAnalyzed != bOnly)
    }

    // MARK: Numeric title tokens survive a later search

    private func previewTitle(_ store: some WorkbenchHeatmapControlsStore) -> (title: String, available: [String]) {
        let common = store.heatmapControlsDescriptor(
            appState: SpinLabAppState(), globalPlotDefaults: .constant([:]), flushSource: "t", defaultTitle: "Default",
            sourceResetToken: "t", axes: PlotAxesModel(sourceResetToken: "t"), fontRoles: [.title], specific: .empty).common
        return (common.renderedTitle, common.availableTokens)
    }

    /// A search for A replaces the cache, as `WorkbenchMainSearchRuntime` does after a query.
    private func searchForA(_ store: AnyObject, a: WorkflowMeasurementSearchHit) {
        if let afm = store as? AFMWorkspaceStore {
            afm.cachedSearchResults = [a]; afm.cachedSampleNumericDisplay = [a.sampleKey: ["氧压": "9Pa"]]
        } else if let rsm = store as? RSMWorkspaceStore {
            rsm.cachedSearchResults = [a]; rsm.cachedSampleNumericDisplay = [a.sampleKey: ["氧压": "9Pa"]]
        }
    }

    @Test("AFM: analyze B with #sample #氧压, then search A — preview, re-render, saved Pack and restore still use B")
    func afmNumericTokensSurviveLaterSearch() async throws {
        let a = searchHit(sampleKey: "PN31|b|STO|111", file: "/a.ibw")
        let b = searchHit(sampleKey: "PN45|c|LAO|001", file: "/x.ibw")
        var display = HeatmapTabRenderState()
        display.titleTemplate = "#sample #氧压"
        let bNumeric = ["氧压": "5Pa"]

        // The state right after analyzing B (snapshot taken at analysis time).
        let (store, before) = try await afmFigure(display: display, search: [a, b], analyzed: b, numeric: bNumeric)
        searchForA(store, a: a)

        // 1. Title preview and Available list.
        let preview = previewTitle(store)
        #expect(preview.title == "\(b.sampleBatchAndSubstrate) 5Pa", "preview must show B's values, got \(preview.title)")
        #expect(preview.available.contains("#氧压"))

        // 2. Re-render after a control change equals a fresh render of B with that change.
        store.updateHeatmapShowColorbar(false)
        try await Task.sleep(nanoseconds: 600_000_000)
        for _ in 0..<300 where store.isAnalyzing { try await Task.sleep(nanoseconds: 20_000_000) }
        var noBar = display; noBar.showColorbar = false
        let (_, reference) = try await afmFigure(display: noBar, search: [b], analyzed: b, numeric: bNumeric)
        #expect(store.renderedImageData == reference, "re-render must keep B's numeric values")
        #expect(store.renderedImageData != before)

        // 3. Saved Pack metadata carries B's snapshot, not A's.
        let config = store.buildPackConfig()
        #expect(config.analyzedNumericDisplay == bNumeric)
        let decoded = try JSONDecoder().decode(AFMPackConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.analyzedNumericDisplay == bNumeric)

        // 4. Restore into a store whose cache holds only A: still B.
        let (restored, restoredFigure) = try await afmFigure(display: noBar, search: [a], analyzed: b, numeric: bNumeric)
        #expect(restored.titleNumericDisplay == bNumeric)
        #expect(restoredFigure == reference)

        // Old packs have no snapshot and still decode (falls back to the cache for the analyzed hit).
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "analyzedNumericDisplay")
        let old = try JSONDecoder().decode(AFMPackConfig.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.analyzedNumericDisplay == nil && old.analyzedHit == b)
    }

    @Test("RSM: analyze B with #sample #氧压, then search A — preview, re-render, saved Pack and restore still use B")
    func rsmNumericTokensSurviveLaterSearch() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rsm-num-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "scan.dat")
        try Self.rsmScan.write(to: file, atomically: true, encoding: .utf8)
        let a = searchHit(sampleKey: "PN31|b|STO|111", file: "/other.dat")
        let b = searchHit(sampleKey: "PN45|c|LAO|001", file: file.path)
        var display = HeatmapTabRenderState()
        display.titleTemplate = "#sample #氧压"
        let bNumeric = ["氧压": "5Pa"]

        func restore(_ display: HeatmapTabRenderState, search: [WorkflowMeasurementSearchHit]) async throws -> (RSMWorkspaceStore, Data) {
            let config = RSMPackConfig(
                packState: RSMPackState(sourceFileIdentity: file.path, detectorColumnName: "Detector", activeView: .hl),
                displayState: display, cachedSearchResults: search, analyzedHit: b, analyzedNumericDisplay: bNumeric)
            let pack = AnalysisPack(label: "scan", workflowID: "rsm", filePaths: [file.path], sampleKeys: [b.sampleKey], sourceFingerprint: "f",
                                    config: try JSONEncoder().encode(config), result: Data("{}".utf8))
            let store = RSMWorkspaceStore(workflowID: "rsm")
            store.restoreFromPack(config: config, result: RSMPackResult(), pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
            for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            return (store, try #require(store.renderedImageData))
        }
        let (store, before) = try await restore(display, search: [a, b])
        searchForA(store, a: a)

        let preview = previewTitle(store)
        #expect(preview.title == "\(b.sampleBatchAndSubstrate) 5Pa", "preview must show B's values, got \(preview.title)")
        #expect(preview.available.contains("#氧压"))

        store.updateHeatmapShowColorbar(false)
        try await Task.sleep(nanoseconds: 600_000_000)
        for _ in 0..<300 where store.isAnalyzing { try await Task.sleep(nanoseconds: 20_000_000) }
        var noBar = display; noBar.showColorbar = false
        let (_, reference) = try await restore(noBar, search: [b])
        #expect(store.renderedImageData == reference, "re-render must keep B's numeric values")
        #expect(store.renderedImageData != before)

        let config = store.buildPackConfig()
        #expect(config.analyzedNumericDisplay == bNumeric)
        let decoded = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.analyzedNumericDisplay == bNumeric)

        let (restored, restoredFigure) = try await restore(noBar, search: [a])
        #expect(restored.titleNumericDisplay == bNumeric)
        #expect(restoredFigure == reference)

        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "analyzedNumericDisplay")
        let old = try JSONDecoder().decode(RSMPackConfig.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.analyzedNumericDisplay == nil && old.analyzedHit == b)
    }

    @Test("AFM: the Title Template reaches the rendered figure; a manual title wins; an unresolvable template falls back to the default")
    func afmTitleTemplateDrivesFigure() async throws {
        var plain = HeatmapTabRenderState()
        let (_, defaultImage) = try await afmFigure(display: plain)

        plain.titleTemplate = "#tab"
        let (store, templated) = try await afmFigure(display: plain)
        #expect(templated != defaultImage, "the template title must be drawn instead of the dataset default")
        #expect(store.heatmapDisplayState.titleTemplate == "#tab", "the template restored from the pack")

        var manual = plain
        manual.titleOverride = "My manual title"
        let (_, manualImage) = try await afmFigure(display: manual)
        #expect(manualImage != templated && manualImage != defaultImage, "manual title outranks the template")

        var missing = HeatmapTabRenderState()
        missing.titleTemplate = "#sample #nothingHere"   // no sample, unknown token → resolves to nothing
        let (_, fallbackImage) = try await afmFigure(display: missing)
        #expect(fallbackImage == defaultImage, "an empty template result falls back to the source default title")

        var hidden = plain
        hidden.showTitle = false
        let (hiddenStore, hiddenImage) = try await afmFigure(display: hidden)
        #expect(hiddenImage != templated, "Show Title off hides the title")
        #expect(hiddenStore.heatmapDisplayState.titleTemplate == "#tab", "Show Title never clears the template")
    }

    @Test("RSM: the Title Template reaches the rendered figure from a real scan file; manual title wins")
    func rsmTitleTemplateDrivesFigure() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rsm-title-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "scan.dat")
        try Self.rsmScan.write(to: file, atomically: true, encoding: .utf8)

        func figure(_ display: HeatmapTabRenderState) async throws -> Data {
            let config = RSMPackConfig(
                packState: RSMPackState(sourceFileIdentity: file.path, detectorColumnName: "Detector", activeView: .hl),
                displayState: display)
            let pack = AnalysisPack(label: "scan", workflowID: "rsm", filePaths: [file.path], sampleKeys: ["k"], sourceFingerprint: "f",
                                    config: try JSONEncoder().encode(config), result: Data("{}".utf8))
            let store = RSMWorkspaceStore(workflowID: "rsm")
            store.restoreFromPack(config: config, result: RSMPackResult(), pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
            for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            return try #require(store.renderedImageData)
        }

        let defaultImage = try await figure(HeatmapTabRenderState())
        var templated = HeatmapTabRenderState()
        templated.titleTemplate = "#tab"
        let templatedImage = try await figure(templated)
        #expect(templatedImage != defaultImage)

        var manual = templated
        manual.titleOverride = "My manual title"
        let manualImage = try await figure(manual)
        #expect(manualImage != templatedImage && manualImage != defaultImage)

        var unresolved = HeatmapTabRenderState()
        unresolved.titleTemplate = "#nothingHere"
        #expect(try await figure(unresolved) == defaultImage)
    }

    @Test("Heatmap display state: old packs decode with an empty template; the template round-trips and keeps saved overrides")
    func heatmapDisplayStateCompatibility() throws {
        let legacy = #"{"schemaVersion":2,"titleOverride":"Saved Title","showTitle":false,"colorScaleMode":"log10"}"#
        let old = try JSONDecoder().decode(HeatmapTabRenderState.self, from: Data(legacy.utf8))
        #expect(old.titleTemplate.isEmpty)
        #expect(old.titleOverride == "Saved Title", "saved manual overrides stay recoverable")
        #expect(old.showTitle == false)

        var state = old
        state.titleTemplate = "#tab #sample"
        let back = try JSONDecoder().decode(HeatmapTabRenderState.self, from: JSONEncoder().encode(state))
        #expect(back.titleTemplate == "#tab #sample")
        #expect(back.titleOverride == "Saved Title")
        #expect(back == state)
    }
}
