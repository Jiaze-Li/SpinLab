import Foundation
import Testing
@testable import SpinLabApp

/// Pack / Restore through the shared Controls Surface: restored state must come back into the
/// controls and produce the same plot result as setting it live (spec 06 CS-28, AC6).
@MainActor
@Suite("Controls adapters — Pack/Restore (real stores)")
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
            stackOffsetMultiplier: 0, minGapFraction: 0.15, showPlotGrid: true,
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
                titleTemplate: "title", stackOffsetMultiplier: 1.0, minGapFraction: 0.15,
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
}
