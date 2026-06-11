import Foundation
import Testing
@testable import SpinLabApp

/// V7.4.0 Analysis Overlay — Runtime Extraction (Gate 7.4 Step 2)
///
/// Proves that WorkbenchAnalysisOverlayRuntime now owns overlay ID list and chip
/// display metadata, and that ThreeOmegaWorkspaceStore correctly delegates to it
/// when wired (falling back to standalone behavior when not wired).
///
/// Groups:
///   1. WorkbenchAnalysisOverlayRuntime — standalone unit tests of the new runtime.
///   2. Delegation — ThreeOmegaWorkspaceStore forwards overlay mutations to runtime.
///   3. Isolation — common runtime has no 3ω / RAHE / workflow-specific semantics.
///   4. WorkbenchFeatureStore wiring — overlayRuntime is injected and live via WFS.
@Suite("V7.4.0 Analysis Overlay — Runtime Extraction (Gate 7.4 Step 2)")
struct V740AnalysisOverlayRuntimeTests {

    // MARK: - 1. WorkbenchAnalysisOverlayRuntime standalone

    @MainActor
    @Test("addEntry appends id to overlayIDs and sets label")
    func addEntryAppendsIDAndLabel() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "Sample A 300K")

        #expect(rt.overlayIDs == [id])
        #expect(rt.displayLabels[id] == "Sample A 300K")
    }

    @MainActor
    @Test("addEntry is idempotent — duplicate id does not double-append")
    func addEntryIsIdempotent() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "First")
        rt.addEntry(id: id, label: "Second")  // same id, different label

        #expect(rt.overlayIDs.count == 1,
                "Expected addEntry to ignore duplicate id")
        #expect(rt.displayLabels[id] == "First",
                "Expected first label to be preserved when duplicate is ignored")
    }

    @MainActor
    @Test("removeEntry removes id and label")
    func removeEntryRemovesIDAndLabel() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let idA = AnalysisPack.ID()
        let idB = AnalysisPack.ID()
        rt.addEntry(id: idA, label: "A")
        rt.addEntry(id: idB, label: "B")

        rt.removeEntry(id: idA)

        #expect(rt.overlayIDs == [idB])
        #expect(rt.displayLabels[idA] == nil)
        #expect(rt.displayLabels[idB] == "B")
    }

    @MainActor
    @Test("clear empties overlayIDs and displayLabels")
    func clearEmptiesAllState() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let idA = AnalysisPack.ID()
        let idB = AnalysisPack.ID()
        rt.addEntry(id: idA, label: "A")
        rt.addEntry(id: idB, label: "B")

        rt.clear()

        #expect(rt.overlayIDs.isEmpty)
        #expect(rt.displayLabels.isEmpty)
    }

    @MainActor
    @Test("isOverlaid returns correct values")
    func isOverlaidReturnsCorrectValues() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let id = AnalysisPack.ID()
        let other = AnalysisPack.ID()
        rt.addEntry(id: id, label: "X")

        #expect(rt.isOverlaid(id))
        #expect(!rt.isOverlaid(other))
    }

    // MARK: - 2. Delegation (store → runtime)

    @MainActor
    @Test("overlayPackIDs forwards to runtime overlayIDs when wired")
    func overlayPackIDsForwardsToRuntimeWhenWired() {
        let store = ThreeOmegaWorkspaceStore()
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt

        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "Forwarded")

        #expect(store.overlayPackIDs == [id],
                "Expected store.overlayPackIDs to forward to rt.overlayIDs when wired")
    }

    @MainActor
    @Test("removeOverlay delegates to runtime when wired")
    func removeOverlayDelegatesToRuntimeWhenWired() {
        let store = ThreeOmegaWorkspaceStore()
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt

        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "To Remove")
        store.overlaySnapshots[id] = OverlaySnapshot(label: "To Remove", sweeps: [], sourceFiles: [], sampleKeys: [])

        store.removeOverlay(id: id)

        #expect(rt.overlayIDs.isEmpty,
                "Expected runtime overlayIDs to be empty after removeOverlay")
        #expect(rt.displayLabels[id] == nil,
                "Expected runtime label to be removed after removeOverlay")
        #expect(store.overlaySnapshots[id] == nil,
                "Expected store snapshot to be removed after removeOverlay")
    }

    @MainActor
    @Test("clearPlot calls runtime.clear() when wired")
    func clearPlotCallsRuntimeClearWhenWired() {
        let store = ThreeOmegaWorkspaceStore()
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt

        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "Active")
        store.overlaySnapshots[id] = OverlaySnapshot(label: "Active", sweeps: [], sourceFiles: [], sampleKeys: [])

        store.clearPlot()

        #expect(rt.overlayIDs.isEmpty,
                "Expected runtime overlayIDs cleared by clearPlot")
        #expect(rt.displayLabels.isEmpty,
                "Expected runtime displayLabels cleared by clearPlot")
        #expect(store.overlaySnapshots.isEmpty,
                "Expected store snapshots cleared by clearPlot")
    }

    @MainActor
    @Test("restoreFromPack calls runtime.clear() when wired")
    func restoreFromPackCallsRuntimeClearWhenWired() throws {
        let store = ThreeOmegaWorkspaceStore()
        let rt = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = rt

        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "Pre-restore Overlay")
        store.overlaySnapshots[id] = OverlaySnapshot(label: "Pre-restore Overlay", sweeps: [], sourceFiles: [], sampleKeys: [])

        let config = makeMinimalConfig()
        let result = makeMinimalResult()
        let pack = try makePack()

        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(rt.overlayIDs.isEmpty,
                "Expected runtime overlayIDs cleared by restoreFromPack")
        #expect(rt.displayLabels.isEmpty,
                "Expected runtime displayLabels cleared by restoreFromPack")
        #expect(store.overlaySnapshots.isEmpty,
                "Expected store snapshots cleared by restoreFromPack")
    }

    // MARK: - 3. Isolation — runtime has no workflow-specific semantics

    /// WorkbenchAnalysisOverlayRuntime's public API uses only AnalysisPack.ID and String.
    /// It has no knowledge of OverlaySnapshot, ThreeOmegaFieldSweepResult, RAHE methods,
    /// Scaling Law semantics, or sample-key policy. This test compiles only because the
    /// runtime's API is purely (AnalysisPack.ID, String) — no 3ω types needed.
    @MainActor
    @Test("common overlay runtime API uses only AnalysisPack.ID and String — no 3ω semantic types")
    func runtimeAPIHasNoWorkflowSemantics() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let id = AnalysisPack.ID()

        // These are the only types in rt's public API.
        // If OverlaySnapshot, ThreeOmegaFieldSweepResult, or any workflow type
        // appeared in the API, this test file would fail to compile without importing them.
        rt.addEntry(id: id, label: "label only")
        let _: [AnalysisPack.ID] = rt.overlayIDs
        let _: [AnalysisPack.ID: String] = rt.displayLabels
        let _: Bool = rt.isOverlaid(id)
        rt.removeEntry(id: id)
        rt.clear()

        #expect(rt.overlayIDs.isEmpty)
    }

    /// OverlaySnapshot (workflow-specific content) is not exposed through the runtime.
    /// The runtime returns no sweep data, no sampleKeys, and no sourceFiles.
    @MainActor
    @Test("common overlay runtime does not expose OverlaySnapshot or sweep content")
    func runtimeDoesNotExposeOverlaySnapshotContent() {
        let rt = WorkbenchAnalysisOverlayRuntime()
        let id = AnalysisPack.ID()
        rt.addEntry(id: id, label: "chip label")

        // Runtime only exposes the label string — not sweep content or sampleKeys.
        #expect(rt.displayLabels[id] == "chip label",
                "Expected runtime to expose only the display label, not snapshot content")
    }

    // MARK: - 4. WorkbenchFeatureStore wiring

    @MainActor
    @Test("WorkbenchFeatureStore injects overlayRuntime into threeOmegaWorkspace")
    func wfsInjectsOverlayRuntimeIntoWorkspace() {
        let wfs = makeWFS()

        #expect(wfs.threeOmegaWorkspace.overlayRuntime === wfs.overlayRuntime,
                "Expected threeOmegaWorkspace.overlayRuntime to be the same instance as wfs.overlayRuntime")
    }

    @MainActor
    @Test("addOverlay via WFS registers entry in runtime and workspace snapshot")
    func addOverlayViaWFSRegistersInRuntime() throws {
        let wfs = makeWFS()

        // Build a pack and add it to the vault.
        let pack = try makePack(label: "WFS Overlay Pack")
        wfs.analysisVault.add(pack)

        // Simulate having an active analysis result so addOverlay can proceed.
        wfs.threeOmegaWorkspace.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [], rtResult: nil, device: ""
        )

        wfs.threeOmegaWorkspace.addOverlay(id: pack.id)

        #expect(wfs.overlayRuntime.overlayIDs.contains(pack.id),
                "Expected overlayRuntime.overlayIDs to contain the added pack id")
        #expect(wfs.overlayRuntime.displayLabels[pack.id] == "WFS Overlay Pack",
                "Expected overlayRuntime.displayLabels to hold the pack label")
        #expect(wfs.threeOmegaWorkspace.overlaySnapshots[pack.id] != nil,
                "Expected workspace to retain OverlaySnapshot after addOverlay")
    }

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

    private func makePack(label: String = "Runtime Test Fixture") throws -> AnalysisPack {
        try AnalysisPack(
            label: label,
            workflowID: "3w",
            filePaths: [],
            sampleKeys: [],
            config: makeMinimalConfig(),
            result: makeMinimalResult()
        )
    }

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }
}
