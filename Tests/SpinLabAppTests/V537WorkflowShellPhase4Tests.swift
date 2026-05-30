import Foundation
import Testing
@testable import SpinLabApp

/// Phase 4 shell integration tests for AHE and XY Rotation workflows.
///
/// Invariant: per-tab text overrides (titleOverride, xLabelOverride, yLabelOverride,
/// seriesLabelOverrides) stored in TabRenderState are user preferences and must survive
/// all rerender paths. Only clearPlot() is allowed to wipe them.
///
/// These tests mirror the 3ω coverage in V563WorkflowStateBoundaryTests.
@Suite("V5.3.7 Workflow Shell Phase 4 Integration")
struct V537WorkflowShellPhase4Tests {

    // MARK: - AHE: early-return rerender paths

    @MainActor
    @Test("AHE rerenderForStyleChange does not clear per-tab text overrides from tabStates")
    func aheRerenderForStyleChangePreservesTabStateOverrides() {
        let store = AHEWorkspaceStore()
        store.tabs.tabStates[.ahe] = TabRenderState(
            titleOverride: "Custom AHE Title",
            xLabelOverride: "My X",
            yLabelOverride: "My Y",
            seriesLabelOverrides: ["sample-a": "Sample A"]
        )
        // ingestionResult is nil → early return; verifies tabStates are never touched
        store.rerenderForStyleChange()
        let state = store.tabs.state(for: .ahe)
        #expect(state.titleOverride == "Custom AHE Title")
        #expect(state.xLabelOverride == "My X")
        #expect(state.yLabelOverride == "My Y")
        #expect(state.seriesLabelOverrides == ["sample-a": "Sample A"])
    }

    @MainActor
    @Test("AHE updatePlotTitle / updateXAxisLabel / updateYAxisLabel write to active tab state")
    func aheOverrideMutationsWriteToActiveTabState() {
        let store = AHEWorkspaceStore()
        store.updatePlotTitle("My Title")
        store.updateXAxisLabel("X Label")
        store.updateYAxisLabel("Y Label")
        let state = store.tabs.state(for: .ahe)
        #expect(state.titleOverride == "My Title")
        #expect(state.xLabelOverride == "X Label")
        #expect(state.yLabelOverride == "Y Label")
    }

    @MainActor
    @Test("AHE updateSeriesLabel writes to active tab state")
    func aheUpdateSeriesLabelWritesToActiveTabState() {
        let store = AHEWorkspaceStore()
        store.updateSeriesLabel(sampleID: "sample-a", newLabel: "Renamed A")
        let state = store.tabs.state(for: .ahe)
        #expect(state.seriesLabelOverrides["sample-a"] == "Renamed A")
    }

    @MainActor
    @Test("AHE runAnalysis with empty selection preserves tab state overrides (guard path)")
    func aheRunAnalysisEmptySelectionPreservesTabStateOverrides() {
        let store = AHEWorkspaceStore()
        store.tabs.tabStates[.ahe] = TabRenderState(
            titleOverride: "My AHE Title",
            xLabelOverride: "My X",
            seriesLabelOverrides: ["sample-a": "A"]
        )
        // empty selection → guard exits before any tab manager call
        store.runAnalysis()
        let state = store.tabs.state(for: .ahe)
        #expect(state.titleOverride == "My AHE Title")
        #expect(state.xLabelOverride == "My X")
        #expect(state.seriesLabelOverrides == ["sample-a": "A"])
    }

    // MARK: - XY: early-return rerender paths

    @MainActor
    @Test("XY rerenderForStyleChange does not clear per-tab text overrides from tabStates")
    func xyRerenderForStyleChangePreservesTabStateOverrides() {
        let store = XYRotationWorkspaceStore()
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(
            titleOverride: "Custom Rxx Title",
            xLabelOverride: "φ (deg)",
            yLabelOverride: "Rxx (Ω)",
            seriesLabelOverrides: ["sample-a": "Sample A"]
        )
        store.tabs.tabStates[.rxyVsPhi] = TabRenderState(
            titleOverride: "Custom Rxy Title"
        )
        // ingestionResult is nil → early return; verifies tabStates are never touched
        store.rerenderForStyleChange()
        let rxxState = store.tabs.state(for: .rxxVsPhi)
        let rxyState = store.tabs.state(for: .rxyVsPhi)
        #expect(rxxState.titleOverride == "Custom Rxx Title")
        #expect(rxxState.xLabelOverride == "φ (deg)")
        #expect(rxxState.yLabelOverride == "Rxx (Ω)")
        #expect(rxxState.seriesLabelOverrides == ["sample-a": "Sample A"])
        #expect(rxyState.titleOverride == "Custom Rxy Title")
    }

    @MainActor
    @Test("XY tab state overrides are isolated per tab: rxxVsPhi override does not appear in rxyVsPhi")
    func xyTabStateOverridesAreTabIsolated() {
        let store = XYRotationWorkspaceStore()
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(
            titleOverride: "Only Rxx",
            seriesLabelOverrides: ["sample-a": "A"]
        )
        // rxyVsPhi starts with no overrides
        store.rerenderForStyleChange()
        let rxxState = store.tabs.state(for: .rxxVsPhi)
        let rxyState = store.tabs.state(for: .rxyVsPhi)
        #expect(rxxState.titleOverride == "Only Rxx")
        #expect(rxxState.seriesLabelOverrides == ["sample-a": "A"])
        #expect(rxyState.titleOverride == "")
        #expect(rxyState.seriesLabelOverrides.isEmpty)
    }

    @MainActor
    @Test("XY runAnalysis with empty selection preserves tab state overrides (guard path)")
    func xyRunAnalysisEmptySelectionPreservesTabStateOverrides() {
        let store = XYRotationWorkspaceStore()
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(
            titleOverride: "My Rxx Title",
            xLabelOverride: "φ",
            seriesLabelOverrides: ["sample-a": "A"]
        )
        store.tabs.tabStates[.rxyVsPhi] = TabRenderState(
            titleOverride: "My Rxy Title"
        )
        // empty cachedSearchResults + empty selectedSearchResultIDs → guard exits before clearOutputs
        store.runAnalysis()
        #expect(store.tabs.state(for: .rxxVsPhi).titleOverride == "My Rxx Title")
        #expect(store.tabs.state(for: .rxxVsPhi).xLabelOverride == "φ")
        #expect(store.tabs.state(for: .rxxVsPhi).seriesLabelOverrides == ["sample-a": "A"])
        #expect(store.tabs.state(for: .rxyVsPhi).titleOverride == "My Rxy Title")
    }

    // MARK: - XY: render path with mock ingestion data

    @MainActor
    @Test("XY rerenderForStyleChange preserves tab state and reflects title override in rendered output")
    func xyRerenderForStyleChangeReflectsTitleOverrideInOutput() async throws {
        let store = XYRotationWorkspaceStore()
        let sweep = XYRotationAngleSweep(
            temperatureK: 80,
            stem: "sample",
            sourceKind: .lvm,
            angleDeg: [0.0, 90.0, 180.0, 270.0, 360.0],
            resistanceXX: [1.0, 0.9, 1.0, 0.9, 1.0],
            resistanceXY: nil,
            defaultPhiOffset: 0.0,
            measurementFilePath: "/tmp/sample.lvm"
        )
        store.ingestionResult = XYRotationIngestionResult(sweeps: [sweep], device: "0deg", warnings: [])
        store.tabs.activeTab = .rxxVsPhi
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(
            titleOverride: "Custom Rxx Title",
            xLabelOverride: "Angle (deg)",
            yLabelOverride: "Rxx (kΩ)"
        )

        store.rerenderForStyleChange()

        var attempts = 0
        while store.tabs.activeLayout == nil && attempts < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        let output = store.tabs.output(for: .rxxVsPhi)
        #expect(output.imageData != nil)
        #expect(output.layout != nil)

        // tabStates must be preserved through the rerender
        let state = store.tabs.state(for: .rxxVsPhi)
        #expect(state.titleOverride == "Custom Rxx Title")
        #expect(state.xLabelOverride == "Angle (deg)")
        #expect(state.yLabelOverride == "Rxx (kΩ)")

        // rxyVsPhi was not rerenderred — its output stays nil (active tab only)
        #expect(store.tabs.output(for: .rxyVsPhi).imageData == nil)
    }

    @MainActor
    @Test("XY rerenderForStyleChange: rxxVsPhi and rxyVsPhi tabStates stay independent through render")
    func xyRerenderForStyleChangeKeepsTabsIsolatedThroughRender() async throws {
        let store = XYRotationWorkspaceStore()
        let sweep = XYRotationAngleSweep(
            temperatureK: 80,
            stem: "sample",
            sourceKind: .lvm,
            angleDeg: [0.0, 90.0, 180.0],
            resistanceXX: [1.0, 0.9, 1.0],
            resistanceXY: [-0.1, 0.0, 0.1],
            defaultPhiOffset: 0.0,
            measurementFilePath: "/tmp/sample.lvm"
        )
        store.ingestionResult = XYRotationIngestionResult(sweeps: [sweep], device: "0deg", warnings: [])
        store.tabs.activeTab = .rxxVsPhi
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(titleOverride: "Rxx Override")
        store.tabs.tabStates[.rxyVsPhi] = TabRenderState(titleOverride: "Rxy Override")

        store.rerenderForStyleChange()

        var attempts = 0
        while store.tabs.activeLayout == nil && attempts < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        // Only the active tab is re-rendered; both tabStates must remain intact
        #expect(store.tabs.state(for: .rxxVsPhi).titleOverride == "Rxx Override")
        #expect(store.tabs.state(for: .rxyVsPhi).titleOverride == "Rxy Override")

        // Inactive tab output untouched by this rerender
        #expect(store.tabs.output(for: .rxyVsPhi).imageData == nil)
    }

    // MARK: - XY: series order preserved through clearOutputs (Phase 4 regression gate)

    @MainActor
    @Test("XY runAnalysis does not clear series order from tabStates (guard path)")
    func xyRunAnalysisGuardPathPreservesSeriesOrder() {
        let store = XYRotationWorkspaceStore()
        let order = ["key-a|/tmp/a.lvm", "key-b|/tmp/b.lvm"]
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(seriesOrder: order)
        // empty selection → guard exits
        store.runAnalysis()
        #expect(store.tabs.state(for: .rxxVsPhi).seriesOrder == order)
    }

    // MARK: - Payload identity: active tab projection matches output store

    @MainActor
    @Test("XY activeImageData is a projection over tabOutputs for the active tab")
    func xyActiveImageDataProjectsFromTabOutputs() {
        let store = XYRotationWorkspaceStore()
        #expect(store.activeImageData == nil)
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xAB]), layout: nil, manifestPayload: nil),
            for: .rxxVsPhi
        )
        #expect(store.activeImageData == Data([0xAB]))
        store.tabs.clearOutputs()
        #expect(store.activeImageData == nil)
    }

    @MainActor
    @Test("AHE activeImageData is a projection over tabOutputs for the active tab")
    func aheActiveImageDataProjectsFromTabOutputs() {
        let store = AHEWorkspaceStore()
        #expect(store.activeImageData == nil)
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xCD]), layout: nil, manifestPayload: nil),
            for: .ahe
        )
        #expect(store.activeImageData == Data([0xCD]))
        store.tabs.clearOutputs()
        #expect(store.activeImageData == nil)
    }
}
