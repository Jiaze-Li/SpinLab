import Foundation
import Testing
@testable import SpinLabApp

/// v8.5A Pack Persistence Gap — AHE and XYRotation PlotControl fields
///
/// Verifies that the three shared PlotControl settings (legendAnchor, seriesRenderMode,
/// chartStyleOverrides) and the XYRotation-specific showAuxiliaryLine180 survive a JSON
/// round-trip through the pack contract and are applied back to store state on restore.
@Suite("V8.5A Pack Persistence Gap")
struct V85APackPersistenceGapTests {

    // MARK: - Helpers

    private func makeHit(id: String, workflowID: String, workflowCanonicalID: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: [:],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    private func jsonRoundtrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - AHE contract round-trips

    @Test("AHE: seriesRenderMode survives JSON round-trip")
    func aheSeriesRenderModeRoundtrip() throws {
        let config = AHEPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            legendAnchor: "",
            seriesRenderMode: .scatter,
            chartStyleOverrides: [:]
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.seriesRenderMode == .scatter)
    }

    @Test("AHE: chartStyleOverrides survives JSON round-trip")
    func aheChartStyleOverridesRoundtrip() throws {
        let overrides = ["labelFontSize": "14", "tickFontSize": "11"]
        let config = AHEPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: overrides
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.chartStyleOverrides == overrides)
    }

    @Test("AHE: legendAnchor survives JSON round-trip")
    func aheLegendAnchorRoundtrip() throws {
        let config = AHEPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            legendAnchor: "top-left",
            seriesRenderMode: .line,
            chartStyleOverrides: [:]
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.legendAnchor == "top-left")
    }

    // MARK: - AHE restore applies values to store

    @MainActor
    @Test("AHE restore: legendAnchor, seriesRenderMode, chartStyleOverrides applied to store")
    func aheRestoreAppliesPlotControlFields() throws {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let hit = makeHit(id: "ahe-ctrl", workflowID: "ahe", workflowCanonicalID: "ahe")
        let ingestion = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [], sourceFiles: nil, warnings: []
        )
        let config = AHEPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: false,
            legendAnchor: "bottom-right",
            seriesRenderMode: .scatter,
            chartStyleOverrides: ["labelFontSize": "16"],
            tabStates: [:],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id],
            searchQueryText: ""
        )
        let result = AHEPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(
            label: "AHE Ctrl",
            workflowID: "ahe",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.tabs.legendAnchor == "bottom-right",
                "legendAnchor must be restored from pack")
        #expect(store.tabs.seriesRenderMode == .scatter,
                "seriesRenderMode must be restored from pack")
        #expect(store.tabs.chartStyleOverrides["labelFontSize"] == "16",
                "chartStyleOverrides must be restored from pack")
    }

    // MARK: - AHE backward compatibility

    @Test("AHE: old pack without new fields decodes with safe defaults")
    func aheOldPackBackwardCompatibility() throws {
        let json = """
        {
          "titleTemplate": "#tab",
          "showPlotGrid": true,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let decoded = try JSONDecoder().decode(AHEPackConfig.self, from: Data(json.utf8))
        #expect(decoded.legendAnchor == "")
        #expect(decoded.seriesRenderMode == .line)
        #expect(decoded.chartStyleOverrides == [:])
    }

    // MARK: - XYRotation contract round-trips

    @Test("XYRotation: showAuxiliaryLine180 survives JSON round-trip")
    func xyShowAuxiliaryLine180Roundtrip() throws {
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: false, linearDetrend: false,
            activeTab: "rxxVsPhi", titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, showAuxiliaryLine180: true
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.showAuxiliaryLine180 == true)
    }

    @Test("XYRotation: seriesRenderMode survives JSON round-trip")
    func xySeriesRenderModeRoundtrip() throws {
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: false, linearDetrend: false,
            activeTab: "rxxVsPhi", titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, seriesRenderMode: .scatter
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.seriesRenderMode == .scatter)
    }

    @Test("XYRotation: chartStyleOverrides survives JSON round-trip")
    func xyChartStyleOverridesRoundtrip() throws {
        let overrides = ["labelFontSize": "13", "tickFontSize": "10"]
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: false, linearDetrend: false,
            activeTab: "rxxVsPhi", titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, chartStyleOverrides: overrides
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.chartStyleOverrides == overrides)
    }

    @Test("XYRotation: legendAnchor survives JSON round-trip")
    func xyLegendAnchorRoundtrip() throws {
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: false, linearDetrend: false,
            activeTab: "rxxVsPhi", titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, legendAnchor: "top-right"
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.legendAnchor == "top-right")
    }

    // MARK: - XYRotation restore applies values to store

    @MainActor
    @Test("XYRotation restore: all new PlotControl fields applied to store before rerender")
    func xyRestoreAppliesAllPlotControlFields() throws {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let hit = makeHit(id: "xy-ctrl", workflowID: "xy", workflowCanonicalID: "xyRotation")
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: false, linearDetrend: false,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: "#tab", stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: false, showAuxiliaryLine180: true,
            legendAnchor: "top-left", seriesRenderMode: .scatter,
            chartStyleOverrides: ["labelFontSize": "15"],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id]
        )
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult())
        let pack = try AnalysisPack(
            label: "XY Ctrl",
            workflowID: "xy",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.showAuxiliaryLine180 == true,
                "showAuxiliaryLine180 must be restored from pack")
        #expect(store.tabs.legendAnchor == "top-left",
                "legendAnchor must be restored from pack")
        #expect(store.tabs.seriesRenderMode == .scatter,
                "seriesRenderMode must be restored from pack")
        #expect(store.tabs.chartStyleOverrides["labelFontSize"] == "15",
                "chartStyleOverrides must be restored from pack")
    }

    // MARK: - XYRotation backward compatibility

    @Test("XYRotation: old pack without new fields decodes with safe defaults")
    func xyOldPackBackwardCompatibility() throws {
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false,
          "activeTab": "rxxVsPhi",
          "titleTemplate": "#tab",
          "stackOffsetMultiplier": 0.0,
          "minGapFraction": 0.15,
          "showPlotGrid": true,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let decoded = try JSONDecoder().decode(XYRotationPackConfig.self, from: Data(json.utf8))
        #expect(decoded.showAuxiliaryLine180 == false)
        #expect(decoded.legendAnchor == "")
        #expect(decoded.seriesRenderMode == .line)
        #expect(decoded.chartStyleOverrides == [:])
    }

    // MARK: - IV contract round-trips

    @Test("IV: legendAnchor survives JSON round-trip")
    func ivLegendAnchorRoundtrip() throws {
        let config = IVPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            legendAnchor: "top-left"
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.legendAnchor == "top-left")
    }

    // MARK: - IV restore applies values to store

    @MainActor
    @Test("IV restore: legendAnchor applied to store before rerender")
    func ivRestoreAppliesLegendAnchor() throws {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        let hit = makeHit(id: "iv-ctrl", workflowID: "iv", workflowCanonicalID: "iv")
        let ingestion = IVIngestionResult()
        let config = IVPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: false,
            legendAnchor: "bottom-right",
            seriesRenderMode: .scatter,
            chartStyleOverrides: ["labelFontSize": "14"],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id]
        )
        let result = IVPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(
            label: "IV Ctrl",
            workflowID: "iv",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.tabs.legendAnchor == "bottom-right",
                "legendAnchor must be restored from pack")
        #expect(store.tabs.seriesRenderMode == .scatter,
                "seriesRenderMode must be restored from pack")
        #expect(store.tabs.chartStyleOverrides["labelFontSize"] == "14",
                "chartStyleOverrides must be restored from pack")
    }

    // MARK: - IV backward compatibility

    @Test("IV: old pack without legendAnchor decodes with safe default")
    func ivOldPackBackwardCompatibility() throws {
        let json = """
        {
          "titleTemplate": "#tab",
          "showPlotGrid": true,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let decoded = try JSONDecoder().decode(IVPackConfig.self, from: Data(json.utf8))
        #expect(decoded.legendAnchor == "")
        #expect(decoded.seriesRenderMode == .line)
        #expect(decoded.chartStyleOverrides == [:])
    }

    // MARK: - RT contract round-trips

    @Test("RT: legendAnchor survives JSON round-trip")
    func rtLegendAnchorRoundtrip() throws {
        let config = RTPackConfig(legendAnchor: "top-left")
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.legendAnchor == "top-left")
    }

    // MARK: - RT restore applies values to store

    @MainActor
    @Test("RT restore: legendAnchor applied to store before rerender")
    func rtRestoreAppliesLegendAnchor() throws {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)
        let hit = makeHit(id: "rt-ctrl", workflowID: "rt", workflowCanonicalID: "rt")
        let config = RTPackConfig(
            legendAnchor: "bottom-right",
            seriesRenderMode: .scatter,
            chartStyleOverrides: ["labelFontSize": "13"],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id]
        )
        let result = RTPackResult()
        let pack = try AnalysisPack(
            label: "RT Ctrl",
            workflowID: "rt",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.tabs.legendAnchor == "bottom-right",
                "legendAnchor must be restored from pack")
        #expect(store.tabs.seriesRenderMode == .scatter,
                "seriesRenderMode must be restored from pack")
    }

    // MARK: - RT backward compatibility

    @Test("RT: old pack without legendAnchor decodes with safe default")
    func rtOldPackBackwardCompatibility() throws {
        let json = """
        {
          "titleTemplate": "#tab #device #sample",
          "showPlotGrid": true,
          "stackOffsetMultiplier": 0.0,
          "minGapFraction": 0.15,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let decoded = try JSONDecoder().decode(RTPackConfig.self, from: Data(json.utf8))
        #expect(decoded.legendAnchor == "")
        #expect(decoded.seriesRenderMode == .line)
    }

    // MARK: - ThreeOmega contract round-trips

    @Test("ThreeOmega: seriesRenderMode survives JSON round-trip")
    func threeOmegaSeriesRenderModeRoundtrip() throws {
        let config = ThreeOmegaPackConfig(
            device: "", geometry: ThreeOmegaGeometry(), fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil, sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega", titleTemplate: "",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, plotLegendAnchor: "",
            seriesRenderMode: .scatter
        )
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.seriesRenderMode == .scatter)
    }

    // MARK: - ThreeOmega restore applies values to store

    @MainActor
    @Test("ThreeOmega restore: seriesRenderMode applied to tabs before rerender")
    func threeOmegaRestoreAppliesSeriesRenderMode() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let hit = makeHit(id: "3w-ctrl", workflowID: "3w", workflowCanonicalID: "threeOmega")
        let config = ThreeOmegaPackConfig(
            device: "", geometry: ThreeOmegaGeometry(), fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil, sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega", titleTemplate: "",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: false, plotLegendAnchor: "top-left",
            seriesRenderMode: .scatter,
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id]
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
        let pack = try AnalysisPack(
            label: "3ω Ctrl",
            workflowID: "3w",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.tabs.seriesRenderMode == .scatter,
                "seriesRenderMode must be restored from pack")
        #expect(store.tabs.legendAnchor == "top-left",
                "legendAnchor (plotLegendAnchor) must be restored from pack")
    }

    // MARK: - ThreeOmega backward compatibility

    @Test("ThreeOmega: old pack without seriesRenderMode decodes with safe default")
    func threeOmegaOldPackBackwardCompatibility() throws {
        let json = """
        {
          "device": "",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 0.0,
          "showPlotGrid": true,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let decoded = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: Data(json.utf8))
        #expect(decoded.seriesRenderMode == .line)
        #expect(decoded.plotLegendAnchor == "")
    }

    // MARK: - ThreeOmega Temperature Dependence display state round-trips

    private func makeThreeOmegaBaseConfig() -> ThreeOmegaPackConfig {
        ThreeOmegaPackConfig(
            device: "", geometry: ThreeOmegaGeometry(), fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil, sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega", titleTemplate: "",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, plotLegendAnchor: ""
        )
    }

    @Test("ThreeOmega TD: rightYLabelOverride survives JSON round-trip")
    func tdRightYLabelOverrideRoundtrip() throws {
        let snapshot = DualAxisDisplayStateSnapshot(rightYLabelOverride: "κ (W/mK)")
        var config = makeThreeOmegaBaseConfig()
        config.temperatureDependenceDisplayState = snapshot
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.temperatureDependenceDisplayState?.rightYLabelOverride == "κ (W/mK)")
    }

    @Test("ThreeOmega TD: manual X range survives JSON round-trip")
    func tdManualXRangeRoundtrip() throws {
        let snapshot = DualAxisDisplayStateSnapshot(
            axisRangeOverride: DualAxisAxisRangeOverride(xMin: 5.0, xMax: 300.0)
        )
        var config = makeThreeOmegaBaseConfig()
        config.temperatureDependenceDisplayState = snapshot
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.temperatureDependenceDisplayState?.axisRangeOverride?.xMin == 5.0)
        #expect(decoded.temperatureDependenceDisplayState?.axisRangeOverride?.xMax == 300.0)
    }

    @Test("ThreeOmega TD: manual leftY range survives JSON round-trip")
    func tdManualLeftYRangeRoundtrip() throws {
        let snapshot = DualAxisDisplayStateSnapshot(
            axisRangeOverride: DualAxisAxisRangeOverride(leftYMin: 1.0, leftYMax: 10.0)
        )
        var config = makeThreeOmegaBaseConfig()
        config.temperatureDependenceDisplayState = snapshot
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.temperatureDependenceDisplayState?.axisRangeOverride?.leftYMin == 1.0)
        #expect(decoded.temperatureDependenceDisplayState?.axisRangeOverride?.leftYMax == 10.0)
    }

    @Test("ThreeOmega TD: manual rightY range survives JSON round-trip")
    func tdManualRightYRangeRoundtrip() throws {
        let snapshot = DualAxisDisplayStateSnapshot(
            axisRangeOverride: DualAxisAxisRangeOverride(rightYMin: 0.5, rightYMax: 5.0)
        )
        var config = makeThreeOmegaBaseConfig()
        config.temperatureDependenceDisplayState = snapshot
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.temperatureDependenceDisplayState?.axisRangeOverride?.rightYMin == 0.5)
        #expect(decoded.temperatureDependenceDisplayState?.axisRangeOverride?.rightYMax == 5.0)
    }

    @Test("ThreeOmega TD: axisColorPolicy and series styles survive JSON round-trip")
    func tdStyleAndColorPolicyRoundtrip() throws {
        let snapshot = DualAxisDisplayStateSnapshot(
            leftSeriesStyle: DualAxisSeriesVisualStyle(linePattern: .dashed, markerShape: .circle, markerFill: .filled),
            rightSeriesStyle: DualAxisSeriesVisualStyle(linePattern: .solid, markerShape: .square, markerFill: .open),
            axisColorPolicy: .monochrome
        )
        var config = makeThreeOmegaBaseConfig()
        config.temperatureDependenceDisplayState = snapshot
        let decoded = try jsonRoundtrip(config)
        #expect(decoded.temperatureDependenceDisplayState?.axisColorPolicy == .monochrome)
        #expect(decoded.temperatureDependenceDisplayState?.leftSeriesStyle.linePattern == .dashed)
        #expect(decoded.temperatureDependenceDisplayState?.rightSeriesStyle.markerShape == .square)
    }

    @MainActor
    @Test("ThreeOmega TD: full display state restored to store from pack")
    func tdDisplayStateRestoredFromPack() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let hit = makeHit(id: "td-state", workflowID: "3w", workflowCanonicalID: "threeOmega")
        let tdSnapshot = DualAxisDisplayStateSnapshot(
            rightYLabelOverride: "κ (W/mK)",
            axisRangeOverride: DualAxisAxisRangeOverride(xMin: 10.0, xMax: 280.0, leftYMin: 1.0, leftYMax: 8.0),
            axisColorPolicy: .monochrome
        )
        var config = makeThreeOmegaBaseConfig()
        config.temperatureDependenceDisplayState = tdSnapshot
        config = ThreeOmegaPackConfig(
            device: "", geometry: ThreeOmegaGeometry(), fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil, sampleBatchAndSubstrate: "",
            activeTab: "temperatureDependence", titleTemplate: "",
            stackOffsetMultiplier: 0.0, minGapFraction: 0.15,
            showPlotGrid: true, plotLegendAnchor: "",
            temperatureDependenceDisplayState: tdSnapshot,
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id]
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
        let pack = try AnalysisPack(
            label: "TD State",
            workflowID: "3w",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.temperatureDependenceDisplayState.rightYLabelOverride == "κ (W/mK)")
        #expect(store.temperatureDependenceDisplayState.axisColorPolicy == .monochrome)
        #expect(store.temperatureDependenceDisplayState.axisRangeOverride?.xMin == 10.0)
        #expect(store.temperatureDependenceDisplayState.axisRangeOverride?.xMax == 280.0)
        #expect(store.temperatureDependenceDisplayState.axisRangeOverride?.leftYMin == 1.0)
    }

    @Test("ThreeOmega TD: old pack without temperatureDependenceDisplayState decodes with nil default")
    func tdOldPackBackwardCompatibility() throws {
        let json = """
        {
          "device": "",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "temperatureDependence",
          "stackOffsetMultiplier": 0.0,
          "showPlotGrid": true,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let decoded = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: Data(json.utf8))
        #expect(decoded.temperatureDependenceDisplayState == nil)
    }

    @MainActor
    @Test("ThreeOmega TD restore: store defaults to fresh DualAxisDisplayState when field absent")
    func tdOldPackRestoreUsesDefaultDisplayState() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        // Prime with a non-default state to confirm restore resets it
        store.temperatureDependenceDisplayState.rightYLabelOverride = "old"
        let config = makeThreeOmegaBaseConfig()
        // config.temperatureDependenceDisplayState == nil (old pack)
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
        let hit = makeHit(id: "td-default", workflowID: "3w", workflowCanonicalID: "threeOmega")
        let pack = try AnalysisPack(
            label: "Old Pack",
            workflowID: "3w",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        // nil config field → restore resets to fresh DualAxisDisplayState()
        #expect(store.temperatureDependenceDisplayState.rightYLabelOverride == "")
        #expect(store.temperatureDependenceDisplayState.axisColorPolicy == .templatePaired)
    }
}
