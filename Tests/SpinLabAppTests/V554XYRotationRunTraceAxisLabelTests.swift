import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.4-fix: XYRotation run trace axisMapping must reflect the active tab's
/// real physical quantity (Rxx vs Rxy), not the ambiguous workflow-level
/// fallback "R (Ω)" that could not express which tab produced the run.
///
/// Drives the store via `restoreFromPack` with in-memory sweep data (no file I/O,
/// no async ingestion pipeline) to isolate `buildRunTrace()` from unrelated
/// pre-existing crashes in the file-based `runAnalysis()` path.
@Suite("V5.5.4 XY Rotation run trace axis label disambiguation")
struct V554XYRotationRunTraceAxisLabelTests {

    // MARK: - Fixtures

    private func makeSweep() -> XYRotationAngleSweep {
        XYRotationAngleSweep(
            temperatureK: 80,
            stem: "sweep-A",
            sourceKind: .lvm,
            angleDeg: [0, 90, 180, 270],
            resistanceXX: [1.0, 1.1, 1.2, 1.3],
            resistanceXY: [0.1, 0.2, 0.3, 0.4],
            defaultPhiOffset: 0,
            measurementFilePath: "/tmp/sweep-A.lvm"
        )
    }

    private func makeConfig(activeTab: XYRotationWorkbenchTab) -> XYRotationPackConfig {
        XYRotationPackConfig(
            phiOffsetOverrides: [:],
            centerBaseline: false,
            activeTab: activeTab.rawValue,
            titleTemplate: "#tab",
            stackOffsetMultiplier: 0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            showAuxiliaryLine180: false,
            legendAnchor: "",
            seriesRenderMode: .lineAndScatter
        )
    }

    @MainActor
    private func makeRestoredStore(
        activeTab: XYRotationWorkbenchTab,
        sweeps: [XYRotationAngleSweep],
        filePaths: [String]
    ) throws -> XYRotationWorkspaceStore {
        let config = makeConfig(activeTab: activeTab)
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult(sweeps: sweeps, device: "dev"))
        let pack = try AnalysisPack(
            label: "XY",
            workflowID: WorkflowKey.xyRotation.rawValue,
            filePaths: filePaths,
            sampleKeys: [],
            config: config,
            result: result
        )
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let vault = AnalysisVault()
        vault.add(pack)
        store.vault = vault

        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        return store
    }

    // MARK: - Tests

    @MainActor
    @Test("Active Rxx tab run trace yField matches vocabulary .rxx manifest label (from tab payload)")
    func rxxTabUsesRxxVocabularyLabel() throws {
        let store = try makeRestoredStore(activeTab: .rxxVsPhi, sweeps: [makeSweep()], filePaths: ["/tmp/sweep-A.lvm"])

        let trace = try #require(store.buildRunTrace())
        #expect(trace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .manifestPlainText))
        #expect(trace.axisMapping.yField != "R (Ω)")
    }

    @MainActor
    @Test("Active Rxy tab run trace yField matches vocabulary .rxy manifest label (from tab payload)")
    func rxyTabUsesRxyVocabularyLabel() throws {
        let store = try makeRestoredStore(activeTab: .rxyVsPhi, sweeps: [makeSweep()], filePaths: ["/tmp/sweep-A.lvm"])

        let trace = try #require(store.buildRunTrace())
        #expect(trace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.label(for: .rxy, context: .manifestPlainText))
        #expect(trace.axisMapping.yField != "R (Ω)")
    }

    @MainActor
    @Test("Fallback (no active manifest payload) still resolves Rxx/Rxy via vocabulary, never 'R (Ω)'")
    func fallbackWithoutManifestPayloadUsesVocabularyPerTab() throws {
        // Empty sweeps → renderer produces no manifestPayload for either tab,
        // forcing buildRunTrace() onto its active-tab vocabulary fallback branch.
        let rxxStore = try makeRestoredStore(activeTab: .rxxVsPhi, sweeps: [], filePaths: ["/tmp/empty.lvm"])
        let rxxTrace = try #require(rxxStore.buildRunTrace())
        #expect(rxxTrace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .manifestPlainText))
        #expect(rxxTrace.axisMapping.yField != "R (Ω)")

        let rxyStore = try makeRestoredStore(activeTab: .rxyVsPhi, sweeps: [], filePaths: ["/tmp/empty.lvm"])
        let rxyTrace = try #require(rxyStore.buildRunTrace())
        #expect(rxyTrace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.label(for: .rxy, context: .manifestPlainText))
        #expect(rxyTrace.axisMapping.yField != "R (Ω)")
    }
}
