import Foundation
import Testing
@testable import SpinLabApp

/// End-to-end AFM workspace smoke test against the representative real `.ibw` file, exercised
/// through `AFMWorkspaceStore` (Analyze -> channel default -> Plane Level/Line Flatten/Zero
/// toggles, all without re-reading the source file). Skips gracefully when the file isn't
/// present on this machine — see `AFMRealFileSmokeTests` for the lower-level adapter-only smoke
/// test and the "never commit the real file" rationale.
@Suite("AFM workspace end-to-end (real file, local machine only)")
struct AFMEndToEndRealFileTests {

    private static let candidatePaths: [String] = [
        "/Users/jack/Downloads/data/batches/LNO/LNO22/samples/LNO22||STO|001/measurements/afm/LNO22_CONTACT_0000_AFM.ibw",
        "/Users/jack/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite/OneDrive - National University of Singapore.noindex/OneDrive - National University of Singapore/Desktop/Y1 MRAM/experiment results/sample data/LiJiaze AFM/LSMO/LSMO13_CONTACT_0000.ibw",
    ]

    private func locateRepresentativeFile() -> URL? {
        for path in Self.candidatePaths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forReadingFrom: url),
               let firstByte = try? handle.read(upToCount: 1)?.first,
               firstByte != 0 {
                return url
            }
        }
        return nil
    }

    private func waitUntil(timeoutMS: UInt64 = 30000, predicate: @escaping @Sendable () async -> Bool) async {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for condition.")
    }

    @MainActor
    @Test("Analyze -> default Height channel -> Plane Level / Line Flatten / Zero toggles rerender without re-reading the file")
    func endToEndWorkspaceSmoke() async throws {
        guard let url = locateRepresentativeFile() else {
            Issue.record("REQUIRED real AFM sample not found or is an empty cloud placeholder")
            return
        }
        let store = AFMWorkspaceStore(workflowID: "afm")
        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "\(url.path).spinlab.json", measurementFilePath: url.path, sourceFilePath: url.path,
            workflowID: "afm", workflowDisplayName: "AFM", workflowCanonicalID: "afm",
            batchID: "LSMO13", sampleKey: "LSMO13|b|LSMO|001", sampleSubstrate: "LSMO",
            conditions: [:], channels: [], appliedAt: .distantPast
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "afm", queryText: "", selectedIDs: [hit.id], selectedHits: [hit],
            sourceHitCount: 1, selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitUntil { await MainActor.run { !store.isAnalyzing && store.renderedImageData != nil } }

        #expect(store.parsedDataset?.channels.count == 3)
        #expect(store.activeChannel?.sourceLabel == "HeightRetrace", "must default to Height per the channel resolution policy")

        let datasetBeforeToggles = store.parsedDataset

        store.updateSurfaceLevel(.plane)
        await waitUntil { await MainActor.run { store.renderedImageData != nil } }
        #expect(store.processingConfiguration.surfaceLevel == .plane)
        #expect(store.parsedDataset?.sourceRef == datasetBeforeToggles?.sourceRef,
                "toggling Plane Level must not trigger a re-parse of the source dataset")

        store.updateLineFlattenOrder(.order1)
        await waitUntil { await MainActor.run { store.renderedImageData != nil } }
        #expect(store.processingConfiguration.lineFlattenOrder == .order1)

        store.updateZeroReference(.mean)
        await waitUntil { await MainActor.run { store.renderedImageData != nil } }
        #expect(store.processingConfiguration.zeroReference == .mean)

        // The underlying canonical dataset must be byte-identical (same object contents) across
        // every processing toggle — none of these calls re-read the file.
        #expect(store.parsedDataset == datasetBeforeToggles)
    }

    @MainActor
    @Test("AFM pack round-trip restores channel/config/display state and rerenders without re-ingesting")
    func packRoundTrip() async throws {
        guard let url = locateRepresentativeFile() else {
            Issue.record("REQUIRED real AFM sample not found or is an empty cloud placeholder")
            return
        }
        let store = AFMWorkspaceStore(workflowID: "afm")
        let vault = AnalysisVault()
        store.vault = vault
        store.lastLibraryRootPath = "/tmp/afm-pack-test-library"

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "\(url.path).spinlab.json", measurementFilePath: url.path, sourceFilePath: url.path,
            workflowID: "afm", workflowDisplayName: "AFM", workflowCanonicalID: "afm",
            batchID: "LSMO13", sampleKey: "LSMO13|b|LSMO|001", sampleSubstrate: "LSMO",
            conditions: [:], channels: [], appliedAt: .distantPast
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "afm", queryText: "", selectedIDs: [hit.id], selectedHits: [hit],
            sourceHitCount: 1, selectionSource: .canonicalSnapshot
        )
        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitUntil { await MainActor.run { !store.isAnalyzing && store.renderedImageData != nil } }
        store.updateSurfaceLevel(.plane)
        store.updateLineFlattenOrder(.order1)
        store.updateScaleBar(AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2))
        try await Task.sleep(nanoseconds: 2_500_000_000)   // let the async rerender settle

        let config = store.buildPackConfig()
        let result = store.buildPackResult()
        #expect(result.canonicalDataset != nil, "pack result must carry the ingestion result so restore never re-parses the source file")

        let pack = AnalysisPack(
            label: "test", workflowID: "afm", filePaths: [url.path], sampleKeys: [hit.sampleKey],
            sourceFingerprint: "fp",
            config: try JSONEncoder().encode(config),
            result: try JSONEncoder().encode(result)
        )

        let restoredStore = AFMWorkspaceStore(workflowID: "afm")
        restoredStore.vault = vault
        restoredStore.restoreFromPack(
            config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        await waitUntil { await MainActor.run { !restoredStore.isAnalyzing && restoredStore.renderedImageData != nil } }

        #expect(restoredStore.processingConfiguration.lineFlattenOrder == .order1)
        #expect(restoredStore.processingConfiguration.surfaceLevel == .plane)
        #expect(restoredStore.scaleBar == AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2))
        #expect(restoredStore.renderedImageData == store.renderedImageData, "restored render must match the saved render byte-for-byte")
        #expect(restoredStore.processingConfiguration.activeChannelID == config.packState.processingConfiguration.activeChannelID)
        #expect(restoredStore.parsedDataset?.channels.count == 3)
        #expect(restoredStore.packRestoreErrorMessage == nil)
    }

    @MainActor
    @Test("AFM Save to Library succeeds after analysis and writes a real chart artifact")
    func saveToLibrarySucceeds() async throws {
        guard let url = locateRepresentativeFile() else {
            Issue.record("REQUIRED real AFM sample not found or is an empty cloud placeholder")
            return
        }
        let libDir = FileManager.default.temporaryDirectory.appendingPathComponent("afm-save-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libDir) }

        let store = AFMWorkspaceStore(workflowID: "afm")
        store.lastLibraryRootPath = libDir.path

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "\(url.path).spinlab.json", measurementFilePath: url.path, sourceFilePath: url.path,
            workflowID: "afm", workflowDisplayName: "AFM", workflowCanonicalID: "afm",
            batchID: "LSMO13", sampleKey: "LSMO13|b|LSMO|001", sampleSubstrate: "LSMO",
            conditions: [:], channels: [], appliedAt: .distantPast
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "afm", queryText: "", selectedIDs: [hit.id], selectedHits: [hit],
            sourceHitCount: 1, selectionSource: .canonicalSnapshot
        )
        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitUntil { await MainActor.run { !store.isAnalyzing && store.renderedImageData != nil } }

        guard store.renderedImageData != nil else {
            Issue.record("AFM analysis produced no image — cannot test save")
            return
        }

        store.persistToLibrary()
        await waitUntil(timeoutMS: 10000) { await MainActor.run { store.persistenceOutcome != nil } }

        guard case .success = store.persistenceOutcome else {
            Issue.record("Expected .success; got \(String(describing: store.persistenceOutcome))")
            return
        }
        #expect(store.saveMessage == "Saved to Library.")

        let writtenFiles = (try? FileManager.default.subpathsOfDirectory(atPath: libDir.path)) ?? []
        #expect(writtenFiles.contains { $0.hasSuffix(".png") }, "Save must write a real chart PNG artifact to the library root")
    }

    @Test("legacy/missing AFM pack fields decode to V1 defaults")
    func legacyPackFieldsDecodeToDefaults() throws {
        let legacyJSON = """
        { "packState": { "schemaVersion": 1 }, "displayState": {} }
        """
        let config = try JSONDecoder().decode(AFMPackConfig.self, from: Data(legacyJSON.utf8))
        #expect(config.packState.processingConfiguration.activeChannelID.isEmpty)
        #expect(config.packState.processingConfiguration.surfaceLevel == .off)
        #expect(config.packState.processingConfiguration.lineFlattenOrder == .off)
        #expect(config.packState.processingConfiguration.zeroReference == .none)
        #expect(config.selectedSearchResultIDs.isEmpty)

        let emptyResultJSON = "{}"
        let result = try JSONDecoder().decode(AFMPackResult.self, from: Data(emptyResultJSON.utf8))
        #expect(result.canonicalDataset == nil)
    }
}
