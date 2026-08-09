import Foundation
import Testing
@testable import SpinLabApp

/// Phase 6A — Shared AnalysisPack common helpers.
///
/// Verifies that `AnalysisPackSearchContext` and `analysisPackLabel(...)` reproduce, byte-for-byte,
/// the behavior that used to be hand-written six times (once per workflow store). These tests are
/// behavior guards, not schema tests — no PackConfig shape changed in this phase.
@Suite("V6A Shared Pack Common Helpers")
struct V6APackCommonHelpersTests {

    // MARK: - Helpers

    private func makeHit(id: String, workflowID: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowID,
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: [:],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    // MARK: - AnalysisPackSearchContext: sort determinism

    @MainActor
    @Test("AnalysisPackSearchContext sorts selected IDs deterministically")
    func searchContextSortsDeterministically() {
        let fake = SelectionReadingFake()
        fake.idsByWorkflow["ahe"] = ["zebra", "alpha", "mike"]
        let context = AnalysisPackSearchContext(
            cachedSearchResults: [],
            selectionReading: fake,
            workflowID: "ahe"
        )
        #expect(context.selectedSearchResultIDs == ["alpha", "mike", "zebra"])
    }

    @MainActor
    @Test("AnalysisPackSearchContext: empty selection produces empty array")
    func searchContextEmptySelection() {
        let fake = SelectionReadingFake()
        let context = AnalysisPackSearchContext(
            cachedSearchResults: [],
            selectionReading: fake,
            workflowID: "ahe"
        )
        #expect(context.selectedSearchResultIDs == [])
    }

    @MainActor
    @Test("AnalysisPackSearchContext: nil selectionReading produces empty array")
    func searchContextNilSelectionReading() {
        let context = AnalysisPackSearchContext(
            cachedSearchResults: [],
            selectionReading: nil,
            workflowID: "ahe"
        )
        #expect(context.selectedSearchResultIDs == [])
    }

    @MainActor
    @Test("AnalysisPackSearchContext: cachedSearchResults preserved unchanged, not filtered")
    func searchContextPreservesCachedSearchResults() {
        let hitA = makeHit(id: "a", workflowID: "ahe")
        let hitB = makeHit(id: "b", workflowID: "ahe")
        let fake = SelectionReadingFake()
        fake.idsByWorkflow["ahe"] = ["a"]  // only "a" selected — "b" must still survive in cachedSearchResults
        let context = AnalysisPackSearchContext(
            cachedSearchResults: [hitA, hitB],
            selectionReading: fake,
            workflowID: "ahe"
        )
        #expect(context.cachedSearchResults.map(\.id) == [hitA.id, hitB.id])
        #expect(context.selectedSearchResultIDs == ["a"])
    }

    // MARK: - analysisPackLabel: variant A (sample-only — AHE, RSM)

    @Test("analysisPackLabel: sample present, device nil returns sample only")
    func labelSampleOnlyVariantSamplePresent() {
        #expect(analysisPackLabel(sampleBatchAndSubstrate: "PN31 STO111", device: nil, fallback: "AHE") == "PN31 STO111")
    }

    @Test("analysisPackLabel: sample missing, device nil returns fallback")
    func labelSampleOnlyVariantSampleMissing() {
        #expect(analysisPackLabel(sampleBatchAndSubstrate: nil, device: nil, fallback: "AHE") == "AHE")
        #expect(analysisPackLabel(sampleBatchAndSubstrate: nil, device: nil, fallback: "RSM") == "RSM")
    }

    // MARK: - analysisPackLabel: variant B (sample + device — IV, RT, 3ω, XY)

    @Test("analysisPackLabel: sample present, device present appends device")
    func labelSampleDeviceVariantBothPresent() {
        #expect(analysisPackLabel(sampleBatchAndSubstrate: "PN31 STO111", device: "Dev1", fallback: "Unknown") == "PN31 STO111 Dev1")
    }

    @Test("analysisPackLabel: sample present, device absent (nil) returns sample only")
    func labelSampleDeviceVariantDeviceNil() {
        #expect(analysisPackLabel(sampleBatchAndSubstrate: "PN31 STO111", device: nil, fallback: "Unknown") == "PN31 STO111")
    }

    @Test("analysisPackLabel: sample present, device empty string returns sample only")
    func labelSampleDeviceVariantDeviceEmpty() {
        #expect(analysisPackLabel(sampleBatchAndSubstrate: "PN31 STO111", device: "", fallback: "Unknown") == "PN31 STO111")
    }

    @Test("analysisPackLabel: sample missing, device present uses fallback + device")
    func labelSampleDeviceVariantSampleMissing() {
        #expect(analysisPackLabel(sampleBatchAndSubstrate: nil, device: "Dev1", fallback: "Unknown") == "Unknown Dev1")
    }

    // MARK: - Per-workflow buildPackConfig(): shared helper wired in, sort applied

    @MainActor
    @Test("AHE buildPackConfig: selectedSearchResultIDs sorted via shared helper")
    func aheBuildPackConfigUsesSharedHelper() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let hitA = makeHit(id: "zzz", workflowID: WorkflowKey.ahe.rawValue)
        let hitB = makeHit(id: "aaa", workflowID: WorkflowKey.ahe.rawValue)
        store.cachedSearchResults = [hitA, hitB]
        let fake = SelectionReadingFake()
        fake.idsByWorkflow[WorkflowKey.ahe.rawValue] = ["zzz", "aaa"]
        store.selectionReading = fake

        let config = store.buildPackConfig()
        #expect(config.selectedSearchResultIDs == ["aaa", "zzz"])
        #expect(config.cachedSearchResults.map(\.id) == [hitA.id, hitB.id])
    }

    @MainActor
    @Test("IV buildPackConfig: selectedSearchResultIDs sorted via shared helper")
    func ivBuildPackConfigUsesSharedHelper() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        let fake = SelectionReadingFake()
        fake.idsByWorkflow[WorkflowKey.iv.rawValue] = ["charlie", "alpha", "bravo"]
        store.selectionReading = fake

        let config = store.buildPackConfig()
        #expect(config.selectedSearchResultIDs == ["alpha", "bravo", "charlie"])
    }

    @MainActor
    @Test("RT buildPackConfig: selectedSearchResultIDs sorted via shared helper")
    func rtBuildPackConfigUsesSharedHelper() {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)
        let fake = SelectionReadingFake()
        fake.idsByWorkflow[WorkflowKey.rt.rawValue] = ["b", "a"]
        store.selectionReading = fake

        let config = store.buildPackConfig()
        #expect(config.selectedSearchResultIDs == ["a", "b"])
    }

    @MainActor
    @Test("ThreeOmega buildPackConfig: selectedSearchResultIDs sorted via shared helper")
    func threeOmegaBuildPackConfigUsesSharedHelper() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let fake = SelectionReadingFake()
        fake.idsByWorkflow[WorkflowKey.threeOmega.rawValue] = ["y", "x"]
        store.selectionReading = fake

        let config = store.buildPackConfig()
        #expect(config.selectedSearchResultIDs == ["x", "y"])
    }

    @MainActor
    @Test("XYRotation buildPackConfig: selectedSearchResultIDs sorted via shared helper")
    func xyRotationBuildPackConfigUsesSharedHelper() {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let fake = SelectionReadingFake()
        fake.idsByWorkflow[WorkflowKey.xyRotation.rawValue] = ["q", "p"]
        store.selectionReading = fake

        let config = store.buildPackConfig()
        #expect(config.selectedSearchResultIDs == ["p", "q"])
    }

    @MainActor
    @Test("RSM buildPackConfig: selectedSearchResultIDs sorted via shared helper")
    func rsmBuildPackConfigUsesSharedHelper() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        let fake = SelectionReadingFake()
        fake.idsByWorkflow[WorkflowKey.rsm.rawValue] = ["n", "m"]
        store.selectionReading = fake

        let config = store.buildPackConfig()
        #expect(config.selectedSearchResultIDs == ["m", "n"])
    }

    // MARK: - Per-workflow autoPackLabel(): fallback preserved exactly

    @MainActor
    @Test("AHE autoPackLabel: falls back to 'AHE' when no cached search results")
    func aheAutoPackLabelFallback() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        #expect(store.autoPackLabel() == "AHE")
    }

    @MainActor
    @Test("AHE autoPackLabel: uses sample/substrate, never a device suffix")
    func aheAutoPackLabelUsesSampleOnly() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let hit = makeHit(id: "a", workflowID: WorkflowKey.ahe.rawValue)
        store.cachedSearchResults = [hit]
        #expect(store.autoPackLabel() == hit.sampleBatchAndSubstrate)
    }

    @MainActor
    @Test("RSM autoPackLabel: falls back to 'RSM' when no cached search results")
    func rsmAutoPackLabelFallback() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        #expect(store.autoPackLabel() == "RSM")
    }

    @MainActor
    @Test("IV autoPackLabel: falls back to 'Unknown' when no cached search results")
    func ivAutoPackLabelFallback() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        #expect(store.autoPackLabel() == "Unknown")
    }

    @MainActor
    @Test("RT autoPackLabel: falls back to 'Unknown' when no cached search results")
    func rtAutoPackLabelFallback() {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)
        #expect(store.autoPackLabel() == "Unknown")
    }

    @MainActor
    @Test("XYRotation autoPackLabel: falls back to 'Unknown' when no cached search results")
    func xyRotationAutoPackLabelFallback() {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        #expect(store.autoPackLabel() == "Unknown")
    }

    @MainActor
    @Test("ThreeOmega autoPackLabel: falls back to 'Unknown' when no cached search results")
    func threeOmegaAutoPackLabelFallback() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        #expect(store.autoPackLabel() == "Unknown")
    }

    // MARK: - Architectural guard: no manual copy of the sort expression remains

    @Test("No workflow store manually re-implements the selected-ID sort expression")
    func noManualSortExpressionRemains() throws {
        let workbenchDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // .../Tests/SpinLabAppTests
            .deletingLastPathComponent()  // .../Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Sources/SpinLabApp/Features/Workbench")
        let files = try FileManager.default.contentsOfDirectory(at: workbenchDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let needle = "selectionReading?.selectedIDs(for: workflowID) ?? []).sorted()"
        var offendingFiles: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains(needle) {
                offendingFiles.append(file.lastPathComponent)
            }
        }
        #expect(offendingFiles.isEmpty, "Manual selected-ID sort found outside the shared helper in: \(offendingFiles)")
    }
}
