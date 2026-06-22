import Foundation
import Testing
@testable import SpinLabApp

/// Gate 7.8B — Plot System module boundary tests.
///
/// Invariants documented in MODULE_BOUNDARIES.md (Plot System section) and
/// PLOT_SYSTEM.md that are not yet covered by earlier boundary suites:
///
///   1. Plot display mutations (updatePlotTitle, updateLegendPoint, updateSeriesLabel,
///      togglePointLabelVisibility) must not touch search/selection/ingestion state.
///   2. titleTemplate changes (Layer 2 extraction gate pre-condition) must not touch
///      search/selection/ingestion state.
///   3. TabRenderManager.restoreStates preserves all TabRenderState fields (title,
///      axis labels, series labels, legendPoint, seriesOrder, hiddenPointLabels) and
///      does NOT route through clearStates — which would wipe the text overrides.
///
/// Scope guard:
///   - AHE updatePlotTitle / updateLegendPoint at search level are already covered
///     in V563WorkflowStateBoundaryTests. Tests here cover the remaining mutations and
///     workflows.
///   - Item 4 (AHE vs XY/3ω controls specialization source-inspection) is deferred:
///     no pre-existing source-inspection tests establish a baseline to gate against.
@Suite("V7.8B Plot System Boundary")
struct V78BPlotSystemBoundaryTests {

    // MARK: - Helpers

    private func makeSearchHit(id: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe",
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    private func make3OmegaIngestion() -> ThreeOmegaIngestionResult {
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
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
        return ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100: 1e-3],
            warnings: []
        )
    }

    // MARK: - 1. Plot display mutations do not touch search / ingestion state

    // MARK: updateSeriesLabel

    @MainActor
    @Test("AHE updateSeriesLabel does not mutate cachedSearchResults or ingestionResult")
    func aheUpdateSeriesLabelDoesNotMutateSearchOrIngestion() {
        let store = AHEWorkspaceStore()
        let hits = [makeSearchHit(id: "a1")]
        store.cachedSearchResults = hits
        // ingestionResult stays nil — verify it is not side-effected to a non-nil value

        store.updateSeriesLabel(identityKey: "sample-a", newLabel: "Renamed")

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("XY updateSeriesLabel does not mutate cachedSearchResults or ingestionResult")
    func xyUpdateSeriesLabelDoesNotMutateSearchOrIngestion() {
        let store = XYRotationWorkspaceStore()
        let hits = [makeSearchHit(id: "xy1")]
        store.cachedSearchResults = hits

        store.updateSeriesLabel(identityKey: "sample-xy", newLabel: "Renamed XY")

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("3ω updateSeriesLabel does not mutate cachedSearchResults or ingestionResult")
    func threeOmegaUpdateSeriesLabelDoesNotMutateSearchOrIngestion() {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeSearchHit(id: "3w1")]
        store.cachedSearchResults = hits
        store.ingestionResult = make3OmegaIngestion()
        let beforeIngestion = store.ingestionResult

        store.updateSeriesLabel(identityKey: "sample-a", newLabel: "Renamed 3ω")

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == beforeIngestion)
    }

    // MARK: togglePointLabelVisibility (3ω only — AHE/XY use the no-op default)

    @MainActor
    @Test("3ω togglePointLabelVisibility does not mutate cachedSearchResults or ingestionResult")
    func threeOmegaTogglePointLabelDoesNotMutateSearchOrIngestion() {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeSearchHit(id: "3w2")]
        store.cachedSearchResults = hits
        store.ingestionResult = make3OmegaIngestion()
        let beforeIngestion = store.ingestionResult
        store.tabs.activeTab = .scaling

        store.togglePointLabelVisibility(sampleID: "sample-a", pointIndex: 0)

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == beforeIngestion)
        // Verify the mutation landed in tabStates, not somewhere else
        let hidden = store.tabs.hiddenPointLabelsBySampleID(for: .scaling)
        #expect(hidden["sample-a"] == [0])
    }

    @MainActor
    @Test("3ω second togglePointLabelVisibility removes the index (toggle-off path)")
    func threeOmegaTogglePointLabelToggleOffPath() {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeSearchHit(id: "3w3")]
        store.cachedSearchResults = hits
        store.tabs.activeTab = .scaling

        store.togglePointLabelVisibility(sampleID: "sample-a", pointIndex: 1)
        store.togglePointLabelVisibility(sampleID: "sample-a", pointIndex: 1)

        #expect(store.cachedSearchResults == hits)
        let hidden = store.tabs.hiddenPointLabelsBySampleID(for: .scaling)
        // After two toggles the index is absent (hidden set is empty → key removed)
        #expect(hidden["sample-a"] == nil)
    }

    // MARK: updatePlotTitle / updateLegendPoint for XY and 3ω (AHE covered by V563)

    @MainActor
    @Test("XY updatePlotTitle does not mutate cachedSearchResults or ingestionResult")
    func xyUpdatePlotTitleDoesNotMutateSearchOrIngestion() {
        let store = XYRotationWorkspaceStore()
        let hits = [makeSearchHit(id: "xy2")]
        store.cachedSearchResults = hits

        store.updatePlotTitle("New XY Title")

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == nil)
        #expect(store.tabs.state(for: .rxxVsPhi).titleOverride == "New XY Title")
    }

    @MainActor
    @Test("XY updateLegendPoint does not mutate cachedSearchResults or ingestionResult")
    func xyUpdateLegendPointDoesNotMutateSearchOrIngestion() {
        let store = XYRotationWorkspaceStore()
        let hits = [makeSearchHit(id: "xy3")]
        store.cachedSearchResults = hits

        store.updateLegendPoint(CGPoint(x: 0.1, y: 0.9))

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("3ω updatePlotTitle does not mutate cachedSearchResults or ingestionResult")
    func threeOmegaUpdatePlotTitleDoesNotMutateSearchOrIngestion() {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeSearchHit(id: "3w4")]
        store.cachedSearchResults = hits
        store.ingestionResult = make3OmegaIngestion()
        let beforeIngestion = store.ingestionResult

        store.updatePlotTitle("New 3ω Title")

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == beforeIngestion)
    }

    @MainActor
    @Test("3ω updateLegendPoint does not mutate cachedSearchResults or ingestionResult")
    func threeOmegaUpdateLegendPointDoesNotMutateSearchOrIngestion() {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeSearchHit(id: "3w5")]
        store.cachedSearchResults = hits
        store.ingestionResult = make3OmegaIngestion()
        let beforeIngestion = store.ingestionResult

        store.updateLegendPoint(CGPoint(x: 0.3, y: 0.7))

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == beforeIngestion)
    }

    // MARK: - 2. titleTemplate changes do not touch search / selection / ingestion state

    @MainActor
    @Test("AHE titleTemplate mutation does not mutate cachedSearchResults or ingestionResult")
    func aheTitleTemplateMutationDoesNotMutateSearchOrIngestion() {
        let store = AHEWorkspaceStore()
        let hits = [makeSearchHit(id: "tt-ahe")]
        store.cachedSearchResults = hits

        store.titleTemplate = "#tab #device"

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == nil)
        #expect(store.titleTemplate == "#tab #device")
    }

    @MainActor
    @Test("XY titleTemplate mutation does not mutate cachedSearchResults or ingestionResult")
    func xyTitleTemplateMutationDoesNotMutateSearchOrIngestion() {
        let store = XYRotationWorkspaceStore()
        let hits = [makeSearchHit(id: "tt-xy")]
        store.cachedSearchResults = hits

        store.titleTemplate = "#tab #sample"

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == nil)
        #expect(store.titleTemplate == "#tab #sample")
    }

    @MainActor
    @Test("3ω titleTemplate mutation does not mutate cachedSearchResults or ingestionResult")
    func threeOmegaTitleTemplateMutationDoesNotMutateSearchOrIngestion() {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeSearchHit(id: "tt-3w")]
        store.cachedSearchResults = hits
        store.ingestionResult = make3OmegaIngestion()
        let beforeIngestion = store.ingestionResult

        store.titleTemplate = "#tab #method #device"

        #expect(store.cachedSearchResults == hits)
        #expect(store.ingestionResult == beforeIngestion)
        #expect(store.titleTemplate == "#tab #method #device")
    }

    // MARK: - 3. TabRenderManager.restoreStates preserves all override fields

    @MainActor
    @Test("restoreStates restores all TabRenderState fields from snapshot")
    func restoreStatesPreservesAllOverrideFields() {
        enum TestTab: String, Hashable, Sendable, CaseIterable { case alpha, beta }
        let manager = TabRenderManager<TestTab>(defaultTab: .alpha)

        let point = CGPointCodable(CGPoint(x: 0.25, y: 0.75))
        let snapshot: [String: TabRenderState] = [
            "alpha": TabRenderState(
                legendPoint: point,
                titleOverride: "Alpha Title",
                xLabelOverride: "Alpha X",
                yLabelOverride: "Alpha Y",
                seriesLabelOverrides: ["s1": "Series One"],
                seriesOrder: ["key-a", "key-b"]
            ),
            "beta": TabRenderState(
                titleOverride: "Beta Title",
                seriesLabelOverrides: ["s2": "Series Two"]
            )
        ]

        manager.restoreStates(snapshot, tabFor: { TestTab(rawValue: $0) })

        let alpha = manager.state(for: .alpha)
        #expect(alpha.legendPoint?.cgPoint == CGPoint(x: 0.25, y: 0.75))
        #expect(alpha.titleOverride == "Alpha Title")
        #expect(alpha.xLabelOverride == "Alpha X")
        #expect(alpha.yLabelOverride == "Alpha Y")
        #expect(alpha.seriesLabelOverrides == ["s1": "Series One"])
        #expect(alpha.seriesOrder == ["key-a", "key-b"])

        let beta = manager.state(for: .beta)
        #expect(beta.titleOverride == "Beta Title")
        #expect(beta.seriesLabelOverrides == ["s2": "Series Two"])
    }

    @MainActor
    @Test("restoreStates preserves hidden-point-label indices from snapshot")
    func restoreStatesPreservesHiddenPointLabelIndices() {
        enum TestTab: String, Hashable, Sendable, CaseIterable { case main }
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        var state = TabRenderState()
        state.hiddenPointLabelIndicesBySeries = ["sample-x": [0, 2, 4]]
        manager.restoreStates(["main": state], tabFor: { TestTab(rawValue: $0) })

        let restored = manager.state(for: .main)
        #expect(restored.hiddenPointLabelIndicesBySeries["sample-x"] == [0, 2, 4])
    }

    @MainActor
    @Test("restoreStates does not erase text overrides the way clearStates would")
    func restoreStatesDoesNotBehavelikeClearStates() {
        // clearStates wipes titleOverride / axis overrides / seriesLabelOverrides.
        // restoreStates must restore them intact from the snapshot.
        enum TestTab: String, Hashable, Sendable, CaseIterable { case tab1 }
        let manager = TabRenderManager<TestTab>(defaultTab: .tab1)

        let snapshot: [String: TabRenderState] = [
            "tab1": TabRenderState(
                titleOverride: "Preserved Title",
                xLabelOverride: "Preserved X",
                seriesLabelOverrides: ["k": "v"]
            )
        ]

        manager.restoreStates(snapshot, tabFor: { TestTab(rawValue: $0) })

        let state = manager.state(for: .tab1)
        #expect(state.titleOverride == "Preserved Title")
        #expect(state.xLabelOverride == "Preserved X")
        #expect(state.seriesLabelOverrides == ["k": "v"])

        // Confirm the contract difference: clearStates on the same initial data would wipe them
        manager.tabStates[.tab1] = TabRenderState(
            legendPoint: CGPointCodable(CGPoint(x: 0.5, y: 0.5)),
            titleOverride: "Before Clear",
            seriesLabelOverrides: ["k": "v"]
        )
        manager.clearStates()
        let afterClear = manager.state(for: .tab1)
        #expect(afterClear.titleOverride == "")
        #expect(afterClear.seriesLabelOverrides.isEmpty)
        // legendPoint survives clearStates (by design)
        #expect(afterClear.legendPoint?.cgPoint == CGPoint(x: 0.5, y: 0.5))
    }

    @MainActor
    @Test("restoreStates with partial snapshot leaves unmentioned tabs empty")
    func restoreStatesPartialSnapshotLeavesOtherTabsEmpty() {
        enum TestTab: String, Hashable, Sendable, CaseIterable { case first, second }
        let manager = TabRenderManager<TestTab>(defaultTab: .first)

        // Pre-populate both tabs
        manager.tabStates[.first] = TabRenderState(titleOverride: "Pre-first")
        manager.tabStates[.second] = TabRenderState(titleOverride: "Pre-second")

        // Restore only .first
        let snapshot: [String: TabRenderState] = [
            "first": TabRenderState(titleOverride: "Restored First")
        ]
        manager.restoreStates(snapshot, tabFor: { TestTab(rawValue: $0) })

        #expect(manager.state(for: .first).titleOverride == "Restored First")
        // .second is not in the snapshot → cleared (restoreStates replaces the entire dict)
        #expect(manager.state(for: .second).titleOverride == "")
    }

    @MainActor
    @Test("restoreStates with empty snapshot clears all tab state")
    func restoreStatesEmptySnapshotClearsAllTabState() {
        enum TestTab: String, Hashable, Sendable, CaseIterable { case only }
        let manager = TabRenderManager<TestTab>(defaultTab: .only)
        manager.tabStates[.only] = TabRenderState(
            titleOverride: "Was Here",
            seriesLabelOverrides: ["x": "y"]
        )

        manager.restoreStates([:], tabFor: { TestTab(rawValue: $0) })

        #expect(manager.state(for: .only).titleOverride == "")
        #expect(manager.state(for: .only).seriesLabelOverrides.isEmpty)
    }
}
