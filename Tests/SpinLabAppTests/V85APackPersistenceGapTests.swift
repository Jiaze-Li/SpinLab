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
}
