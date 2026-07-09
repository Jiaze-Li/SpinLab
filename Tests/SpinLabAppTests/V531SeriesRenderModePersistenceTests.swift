import Foundation
import XCTest
@testable import SpinLabApp

@MainActor
final class V531SeriesRenderModePersistenceTests: XCTestCase {

    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    func testInteractionSnapshot_roundTripsPerWorkflowSeriesRenderMode() throws {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.aheSeriesRenderMode = .line
        snapshot.ivSeriesRenderMode = .lineAndScatter
        snapshot.threeOmegaSeriesRenderMode = .scatter
        snapshot.xyRotationSeriesRenderMode = .lineAndScatter

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)

        XCTAssertEqual(restored.aheSeriesRenderMode, .line)
        XCTAssertEqual(restored.ivSeriesRenderMode, .lineAndScatter)
        XCTAssertEqual(restored.threeOmegaSeriesRenderMode, .scatter)
        XCTAssertEqual(restored.xyRotationSeriesRenderMode, .lineAndScatter)
    }

    /// Regression test for the Codex #144 review finding: the snapshot used to store a single
    /// shared render mode sourced from AHE and broadcast it to every workflow on restore,
    /// silently discarding whatever mode IV/3ω/XY had been set to.
    func testWorkbenchFeatureStore_capturesAndRestoresIndependentPerWorkflowRenderModes() {
        let store = makeWorkbenchStore()
        store.aheWorkspace.tabs.seriesRenderMode = .line
        store.ivWorkspace.tabs.seriesRenderMode = .lineAndScatter
        store.threeOmegaWorkspace.tabs.seriesRenderMode = .scatter
        store.xyRotationWorkspace.tabs.seriesRenderMode = .lineAndScatter

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        XCTAssertEqual(snapshot.aheSeriesRenderMode, .line)
        XCTAssertEqual(snapshot.ivSeriesRenderMode, .lineAndScatter)
        XCTAssertEqual(snapshot.threeOmegaSeriesRenderMode, .scatter)
        XCTAssertEqual(snapshot.xyRotationSeriesRenderMode, .lineAndScatter)

        let restoredStore = makeWorkbenchStore()
        restoredStore.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            workbenchSeriesRenderMode: snapshot.workbenchSeriesRenderMode,
            aheSeriesRenderMode: snapshot.aheSeriesRenderMode,
            ivSeriesRenderMode: snapshot.ivSeriesRenderMode,
            threeOmegaSeriesRenderMode: snapshot.threeOmegaSeriesRenderMode,
            xyRotationSeriesRenderMode: snapshot.xyRotationSeriesRenderMode
        )

        XCTAssertEqual(restoredStore.aheWorkspace.tabs.seriesRenderMode, .line)
        XCTAssertEqual(restoredStore.ivWorkspace.tabs.seriesRenderMode, .lineAndScatter)
        XCTAssertEqual(restoredStore.threeOmegaWorkspace.tabs.seriesRenderMode, .scatter)
        XCTAssertEqual(restoredStore.xyRotationWorkspace.tabs.seriesRenderMode, .lineAndScatter)
    }

    /// Older persisted snapshots only populate the legacy shared field; restore should still
    /// apply it to every workflow so existing users don't lose their saved mode on upgrade.
    func testWorkbenchFeatureStore_restoreInteractionFallsBackToLegacySharedRenderMode() {
        let store = makeWorkbenchStore()

        store.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            workbenchSeriesRenderMode: .lineAndScatter
        )

        XCTAssertEqual(store.aheWorkspace.tabs.seriesRenderMode, .lineAndScatter)
        XCTAssertEqual(store.xyRotationWorkspace.tabs.seriesRenderMode, .lineAndScatter)
        XCTAssertEqual(store.threeOmegaWorkspace.tabs.seriesRenderMode, .lineAndScatter)
        XCTAssertEqual(store.ivWorkspace.tabs.seriesRenderMode, .lineAndScatter)
    }

    func testThreeOmegaScalingLawRestore_appliesLineAndScatter() throws {
        let config = ThreeOmegaPackConfig(
            device: "device",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "sample",
            activeTab: ThreeOmegaWorkbenchTab.scaling.stableKey,
            titleTemplate: "title",
            stackOffsetMultiplier: 1.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            seriesRenderMode: .lineAndScatter
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "device"),
            scalingResult: nil
        )
        let pack = try AnalysisPack(
            label: "3ω",
            workflowID: WorkflowKey.threeOmega.rawValue,
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
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

        XCTAssertEqual(store.tabs.activeTab, .scaling)
        XCTAssertEqual(store.tabs.seriesRenderMode, .lineAndScatter)
    }

    func testAHERestoreFromPack_appliesLineAndScatter() throws {
        let config = AHEPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            legendAnchor: "",
            seriesRenderMode: .lineAndScatter,
            chartStyleOverrides: [:]
        )
        let ingestionResult = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R_H (Ω)"),
            series: [],
            sourceFiles: [],
            warnings: []
        )
        let result = AHEPackResult(ingestionResult: ingestionResult)
        let pack = try AnalysisPack(
            label: "AHE",
            workflowID: WorkflowKey.ahe.rawValue,
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
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

        XCTAssertEqual(store.tabs.seriesRenderMode, .lineAndScatter)
    }

    func testXYRotationRestoreFromPack_appliesLineAndScatter() throws {
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:],
            centerBaseline: false,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: "#tab",
            stackOffsetMultiplier: 0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            showAuxiliaryLine180: false,
            legendAnchor: "",
            seriesRenderMode: .lineAndScatter
        )
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult())
        let pack = try AnalysisPack(
            label: "XY",
            workflowID: WorkflowKey.xyRotation.rawValue,
            filePaths: [],
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

        XCTAssertEqual(store.tabs.seriesRenderMode, .lineAndScatter)
    }
}
