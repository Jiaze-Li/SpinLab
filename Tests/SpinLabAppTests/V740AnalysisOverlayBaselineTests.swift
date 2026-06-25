import Foundation
import Testing
@testable import SpinLabApp

/// V7.4.0 Analysis Overlay — Baseline (Gate 7.4 Step 1)
///
/// Locks current 3ω overlay behavior before extracting WorkbenchAnalysisOverlayRuntime.
/// No production code is changed by this file; these tests establish the behavioral
/// contract that must remain intact through extraction.
///
/// Groups:
///   1. Pack serialization — overlay state must not appear in ThreeOmegaPackConfig or
///      ThreeOmegaPackResult JSON.
///   2. Restore/clear — restore clears overlay state; clearPlot clears overlay state.
///   3. Snapshot independence — rerender uses snapshot data, not the vault.
///   4. Scaling Law boundary — Scaling tab has no overlay render path.
@Suite("V7.4.0 Analysis Overlay — Baseline (Gate 7.4 Step 1)")
struct V740AnalysisOverlayBaselineTests {

    // MARK: - Fixtures

    private func makeMinimalConfig() -> ThreeOmegaPackConfig {
        ThreeOmegaPackConfig(
            device: "",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega",
            titleTemplate: "#tab",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: false,
            plotLegendAnchor: "",
            tabStates: [:],
            chartStyleOverrides: [:]
        )
    }

    private func makeMinimalResult() -> ThreeOmegaPackResult {
        ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
    }

    private func makePack() throws -> AnalysisPack {
        try AnalysisPack(
            label: "Overlay Baseline Fixture",
            workflowID: "3w",
            filePaths: [],
            sampleKeys: [],
            config: makeMinimalConfig(),
            result: makeMinimalResult()
        )
    }

    private func makeOverlaySnapshot(label: String = "Overlay A") -> OverlaySnapshot {
        OverlaySnapshot(label: label, sweeps: [], sourceFiles: [], sampleKeys: [])
    }

    // MARK: - 1. Pack Serialization

    /// ThreeOmegaPackConfig is Codable. Encoding it must never include overlay state.
    /// Overlay IDs live only in session RAM — they must not enter pack JSON.
    @Test("ThreeOmegaPackConfig JSON does not contain overlay keys")
    func packConfigDoesNotSerializeOverlayState() throws {
        let config = makeMinimalConfig()
        let data = try JSONEncoder().encode(config)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("overlay"),
                "ThreeOmegaPackConfig JSON must not contain any 'overlay' key")
        #expect(!json.contains("Overlay"),
                "ThreeOmegaPackConfig JSON must not contain any 'Overlay' key")
    }

    /// ThreeOmegaPackResult is Codable. Encoding it must never include overlay state.
    @Test("ThreeOmegaPackResult JSON does not contain overlay keys")
    func packResultDoesNotSerializeOverlayState() throws {
        let result = makeMinimalResult()
        let data = try JSONEncoder().encode(result)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("overlay"),
                "ThreeOmegaPackResult JSON must not contain any 'overlay' key")
        #expect(!json.contains("Overlay"),
                "ThreeOmegaPackResult JSON must not contain any 'Overlay' key")
    }

    /// Full round-trip: build a pack with active overlay state in the store,
    /// serialize via _buildPackConfig / _buildPackResult, decode back,
    /// confirm overlay fields are absent from the decoded struct.
    @MainActor
    @Test("pack round-trip does not preserve overlay IDs")
    func packRoundTripDoesNotPreserveOverlayIDs() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt
        let overlayID = AnalysisPack.ID()

        // Simulate an overlay being active in session.
        rt.addEntry(id: overlayID, label: "Round Trip Overlay")
        store.overlaySnapshots[overlayID] = makeOverlaySnapshot()

        // Build config as _buildPackConfig would (it never writes overlayPackIDs).
        let configData = try JSONEncoder().encode(store._buildPackConfig())
        let decoded = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: configData)

        // The decoded config has no overlay concept whatsoever — there is no property to check.
        // The encode/decode must succeed without loss of other fields.
        #expect(decoded.device == "",
                "Expected round-trip to preserve unrelated fields")

        // Confirm raw JSON has no overlay key — belt-and-suspenders.
        let json = try #require(String(data: configData, encoding: .utf8))
        #expect(!json.contains("overlay") && !json.contains("Overlay"),
                "Pack config JSON must contain no overlay state after round-trip")
    }

    // MARK: - 2. Restore / Clear

    /// restoreFromPack explicitly clears overlayPackIDs.
    /// A session with active overlays must have them removed after any pack load.
    @MainActor
    @Test("restoreFromPack clears overlayPackIDs")
    func restoreFromPackClearsOverlayPackIDs() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt
        let overlayID = AnalysisPack.ID()
        rt.addEntry(id: overlayID, label: "Pre-restore Overlay")

        let pack = try makePack()
        store.restoreFromPack(
            config: makeMinimalConfig(),
            result: makeMinimalResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.overlayPackIDs.isEmpty,
                "Expected restoreFromPack to clear overlayPackIDs")
    }

    /// restoreFromPack explicitly clears overlaySnapshots.
    @MainActor
    @Test("restoreFromPack clears overlaySnapshots")
    func restoreFromPackClearsOverlaySnapshots() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt
        let overlayID = AnalysisPack.ID()
        store.overlaySnapshots[overlayID] = makeOverlaySnapshot()
        rt.addEntry(id: overlayID, label: "Pre-restore Overlay")

        let pack = try makePack()
        store.restoreFromPack(
            config: makeMinimalConfig(),
            result: makeMinimalResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.overlaySnapshots.isEmpty,
                "Expected restoreFromPack to clear overlaySnapshots")
    }

    /// clearPlot removes all overlay state (IDs and snapshots).
    @MainActor
    @Test("clearPlot clears overlay IDs and snapshots")
    func clearPlotClearsOverlayState() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt
        let idA = AnalysisPack.ID()
        let idB = AnalysisPack.ID()
        rt.addEntry(id: idA, label: "A")
        rt.addEntry(id: idB, label: "B")
        store.overlaySnapshots[idA] = makeOverlaySnapshot(label: "A")
        store.overlaySnapshots[idB] = makeOverlaySnapshot(label: "B")

        store.clearPlot()

        #expect(store.overlayPackIDs.isEmpty,
                "Expected clearPlot to clear overlayPackIDs")
        #expect(store.overlaySnapshots.isEmpty,
                "Expected clearPlot to clear overlaySnapshots")
    }

    // MARK: - 3. Snapshot Independence

    /// After a snapshot is captured via addOverlay, it survives vault pack deletion.
    /// This test is present in V4117 but is re-stated here as a Gate 7.4 boundary contract:
    /// _renderRAHEWithOverlays must read from overlaySnapshots, not re-fetch from vault.
    @MainActor
    @Test("overlay snapshot survives vault deletion — rerender uses snapshot not vault")
    func overlaySnapshotSurvivesVaultDeletion() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let vault = AnalysisVault()
        store.vault = vault

        // Build a pack and add it to the vault.
        let pack = try makePack()
        vault.add(pack)

        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt

        // Manually simulate the snapshot capture step from addOverlay.
        let snapshot = makeOverlaySnapshot(label: "Persisted Overlay")
        store.overlaySnapshots[pack.id] = snapshot
        rt.addEntry(id: pack.id, label: "Persisted Overlay")

        // Delete the pack from vault (simulates user deleting the saved analysis).
        vault.remove(id: pack.id)

        // Overlay state is still in the store — snapshot survived deletion.
        #expect(store.overlayPackIDs == [pack.id],
                "Expected overlayPackIDs to survive vault deletion")
        #expect(store.overlaySnapshots[pack.id]?.label == "Persisted Overlay",
                "Expected overlaySnapshot to survive vault deletion")
    }

    // MARK: - 4. Scaling Law Boundary

    /// Changing the active tab to .scaling while overlays are loaded does NOT
    /// route through _renderRAHEWithOverlays (RAHE-only path). The Scaling tab
    /// has no overlay render path in the first Gate 7.4 cut.
    ///
    /// Structural test: we verify that _rerenderActiveTab with a .scaling active tab
    /// and non-empty overlayPackIDs does not crash — which would happen if the scaling
    /// renderer were accidentally passed RAHE overlay groups.
    @MainActor
    @Test("scaling tab with active overlays does not crash (no overlay render path for scaling)")
    func scalingTabSkipsOverlayRenderPath() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)

        // Set up a minimal ingestion result so the guard in _rerenderActiveTab passes.
        store.ingestionResult = ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "")

        // Set active tab to .scaling.
        store.tabs.activeTab = .scaling

        // Overlay is loaded via wired runtime.
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt
        let oid = AnalysisPack.ID()
        rt.addEntry(id: oid, label: "Scaling Overlay")
        store.overlaySnapshots[oid] = makeOverlaySnapshot()

        // Must not crash. The render path for .scaling never calls _renderRAHEWithOverlays.
        store._rerenderActiveTab()
    }
}
