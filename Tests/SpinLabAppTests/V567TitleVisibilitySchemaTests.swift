import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Title Visibility schema + persistence audit (Phase 1: schema/persistence only)
//
// Covers showTitle: Bool = true across the three plot-family typed display
// states — TabRenderState (Cartesian XY), DualAxisDisplayState/Snapshot,
// HeatmapTabRenderState — and their pack round-trip / legacy-JSON compatibility.
// No renderer/layout/UI behavior is exercised here.

@Suite("Title visibility schema (Gate showTitle Phase 1)")
struct V567TitleVisibilitySchemaTests {

    // MARK: - Cartesian XY: TabRenderState

    @Test("XY: TabRenderState.showTitle defaults to true")
    func xyDefaultsToTrue() {
        #expect(TabRenderState().showTitle)
    }

    @Test("XY: TabRenderState.showTitle survives encode/decode round-trip as false")
    func xyRoundTripPreservesFalse() throws {
        let state = TabRenderState(showTitle: false)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: data)
        #expect(!decoded.showTitle, "showTitle = false must survive encode → decode")
    }

    @Test("XY: old pack JSON missing showTitle decodes to true")
    func xyLegacyJSONMissingFieldDefaultsToTrue() throws {
        let json = """
        {
          "titleOverride": "T",
          "xLabelOverride": "X",
          "yLabelOverride": "Y"
        }
        """
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: Data(json.utf8))
        #expect(decoded.showTitle, "showTitle missing in old pack must default to true")
    }

    @Test("XY: WorkbenchTabDisplayStateSnapshot carries showTitle")
    func xySnapshotCarriesShowTitle() {
        let snapshot = WorkbenchTabDisplayStateSnapshot(
            titleOverride: "",
            xLabelOverride: "",
            yLabelOverride: "",
            seriesLabelOverrides: [:],
            legendPoint: nil,
            hiddenPointLabelsBySeries: [:],
            seriesOrder: nil,
            axisRangeOverride: nil,
            showPointTags: false,
            showTitle: false
        )
        #expect(!snapshot.showTitle)
        // `with(...)` copies must preserve showTitle unchanged.
        #expect(!snapshot.with(seriesOrder: ["a"]).showTitle)
        #expect(!snapshot.with(hiddenSeriesKeys: ["a"]).showTitle)
    }

    @Test("XY: TabRenderManager.displayStateSnapshot threads showTitle from tabStates")
    @MainActor
    func xyManagerThreadsShowTitle() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.tabStates[.ahe] = TabRenderState(showTitle: false)
        #expect(!manager.displayStateSnapshot(for: .ahe).showTitle)
    }

    // MARK: - DualAxis: DualAxisDisplayState / DualAxisDisplayStateSnapshot

    @Test("DualAxis: DualAxisDisplayState.showTitle defaults to true")
    func dualAxisStateDefaultsToTrue() {
        #expect(DualAxisDisplayState().showTitle)
    }

    @Test("DualAxis: DualAxisDisplayStateSnapshot.showTitle defaults to true")
    func dualAxisSnapshotDefaultsToTrue() {
        #expect(DualAxisDisplayStateSnapshot().showTitle)
        #expect(DualAxisDisplayStateSnapshot.default.showTitle)
    }

    @Test("DualAxis: snapshot() and init(_:) round-trip showTitle between mutable state and snapshot")
    func dualAxisStateSnapshotConversionPreservesShowTitle() {
        var state = DualAxisDisplayState()
        state.showTitle = false
        let snapshot = state.snapshot()
        #expect(!snapshot.showTitle, "snapshot() must carry showTitle from mutable state")

        let roundTrippedState = DualAxisDisplayState(snapshot)
        #expect(!roundTrippedState.showTitle, "init(_:) from snapshot must carry showTitle back")
    }

    @Test("DualAxis: DualAxisDisplayStateSnapshot (the persisted type) survives encode/decode round-trip as false")
    func dualAxisSnapshotRoundTripPreservesFalse() throws {
        let snapshot = DualAxisDisplayStateSnapshot(showTitle: false)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DualAxisDisplayStateSnapshot.self, from: data)
        #expect(!decoded.showTitle, "showTitle = false must survive encode → decode")
    }

    @Test("DualAxis: old pack JSON missing showTitle decodes to true")
    func dualAxisLegacyJSONMissingFieldDefaultsToTrue() throws {
        let json = """
        {
          "titleOverride": "",
          "xLabelOverride": "",
          "leftYLabelOverride": "",
          "rightYLabelOverride": "",
          "leftSeriesStyle": {"linePattern": "solid", "markerShape": "square", "markerFill": "open"},
          "rightSeriesStyle": {"linePattern": "dashed", "markerShape": "circle", "markerFill": "filled"},
          "axisColorPolicy": "templatePaired"
        }
        """
        let decoded = try JSONDecoder().decode(DualAxisDisplayStateSnapshot.self, from: Data(json.utf8))
        #expect(decoded.showTitle, "showTitle missing in old DualAxis pack must default to true")
    }

    @Test("DualAxis: showTitle survives ThreeOmegaPackConfig round-trip via temperatureDependenceDisplayState")
    func dualAxisSurvivesThreeOmegaPackConfigRoundTrip() throws {
        let config = ThreeOmegaPackConfig(
            device: "dev", geometry: ThreeOmegaGeometry(), fitRanges: [],
            v3Method: "auto", rahe1Method: "auto", rahe3Method: "auto", rtFilePath: nil,
            sampleBatchAndSubstrate: "", activeTab: "raw", titleTemplate: "",
            stackOffsetMultiplier: 1.0, minGapFraction: 0.15, showPlotGrid: true,
            plotLegendAnchor: "",
            temperatureDependenceDisplayState: DualAxisDisplayStateSnapshot(showTitle: false)
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: data)
        #expect(decoded.temperatureDependenceDisplayState?.showTitle == false,
                "showTitle = false must survive ThreeOmegaPackConfig encode → decode")
    }

    // MARK: - Heatmap: HeatmapTabRenderState

    @Test("Heatmap: HeatmapTabRenderState.showTitle defaults to true")
    func heatmapDefaultsToTrue() {
        #expect(HeatmapTabRenderState().showTitle)
    }

    @Test("Heatmap: HeatmapTabRenderState.showTitle survives encode/decode round-trip as false")
    func heatmapRoundTripPreservesFalse() throws {
        let state = HeatmapTabRenderState(showTitle: false)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: data)
        #expect(!decoded.showTitle, "showTitle = false must survive encode → decode")
    }

    @Test("Heatmap: old pack JSON missing showTitle decodes to true")
    func heatmapLegacyJSONMissingFieldDefaultsToTrue() throws {
        let json = """
        {
          "schemaVersion": 1,
          "titleOverride": "",
          "xLabelOverride": "",
          "yLabelOverride": "",
          "zLabelOverride": "",
          "showColorbar": true,
          "colorScaleMode": "linear",
          "colormapKey": "viridis",
          "zDomainState": {"mode": "auto", "percentilePreset": "p1_99", "manualRange": {"minText": "", "maxText": ""}}
        }
        """
        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: Data(json.utf8))
        #expect(decoded.showTitle, "showTitle missing in old heatmap pack must default to true")
        #expect(decoded.schemaVersion == 1, "adding showTitle must not force-migrate schemaVersion on decode")
    }

    @Test("Heatmap: schemaVersion is not bumped for the additive showTitle field")
    func heatmapSchemaVersionUnchanged() {
        #expect(HeatmapTabRenderState.currentSchemaVersion == 2,
                "showTitle is purely additive with a safe default — no schema migration needed, so currentSchemaVersion must stay 2")
    }

    @Test("Heatmap: showTitle survives RSMPackConfig round-trip")
    func heatmapSurvivesRSMPackConfigRoundTrip() throws {
        let config = RSMPackConfig(
            packState: RSMPackState(
                sourceFileIdentity: "/tmp/rsm-title.dat",
                detectorColumnName: "Detector",
                activeView: .hl
            ),
            displayState: HeatmapTabRenderState(showTitle: false)
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RSMPackConfig.self, from: data)
        #expect(!decoded.displayState.showTitle,
                "showTitle = false must survive RSMPackConfig encode → decode")
    }
}
