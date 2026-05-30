import Foundation
import Testing
@testable import SpinLabApp

/// V3.3.2 — Generic workspace dispatch via WorkflowWorkspaceRegistry.
///
/// Acceptance record: WorkbenchView delegates to registry; unknown IDs get fallback;
/// no AHE-specific symbols remain in WorkbenchView.swift.
@Suite("V3.3.2 Workflow Workspace Dispatch")
struct V332WorkflowWorkspaceDispatchTests {
    private func makeHit(
        id: String,
        workflowID: String,
        workflowCanonicalID: String,
        sampleKey: String
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN31",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }


    @Test("WorkflowWorkspaceRegistry type exists and compiles")
    func registryExists() {
        // Compile-time smoke test: if WorkflowWorkspaceRegistry is removed or
        // renamed this function body will no longer build.
        _ = WorkflowWorkspaceRegistry.self
    }

    @MainActor
    @Test("clearWorkflowMeasurementSearch propagates cache-clear to aheWorkspace")
    func clearSearchPropagatestoAHESubStore() {
        // Behavioural invariant: if WFS stopped routing through aheWorkspace this would fail.
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        wfs.aheWorkspace.cachedSearchResults = [
            WorkflowMeasurementSearchHit(
                sidecarPath: "/s/sc.json", measurementFilePath: "/s/m.dat",
                sourceFilePath: "/s/m.dat", workflowID: "ahe",
                workflowDisplayName: "AHE", workflowCanonicalID: "ahe",
                batchID: "B1", sampleKey: "s1", sampleSubstrate: "",
                conditions: [:], channels: [], appliedAt: .distantPast
            )
        ]
        #expect(wfs.aheWorkspace.cachedSearchResults.count == 1)
        wfs.clearWorkflowMeasurementSearch(workflowID: .ahe)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
    }

    @MainActor
    @Test("workflow switch preserves per-workflow search state by default")
    func workflowSwitchPreservesPerWorkflowSearchState() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        let aheHits = [makeHit(id: "ahe-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN31|b|STO|111")]
        let xyHits = [makeHit(id: "xy-1", workflowID: "xy", workflowCanonicalID: "xy", sampleKey: "PN32|o|STO|111")]

        wfs.setSearchQueryText("ahe pn31", for: .ahe)
        wfs.restoreSearchState(results: aheHits, queryText: "ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = aheHits

        wfs.setSearchQueryText("xy pn32", for: .xyRotation)
        wfs.restoreSearchState(results: xyHits, queryText: "xy pn32", for: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = xyHits

        wfs.selectWorkflow("ahe")
        wfs.selectWorkflow("xy")
        wfs.selectWorkflow("ahe")

        #expect(wfs.searchQueryText(for: .ahe) == "ahe pn31")
        #expect(wfs.searchResultsList(for: .ahe) == aheHits)
        #expect(wfs.searchQueryText(for: .xyRotation) == "xy pn32")
        #expect(wfs.searchResultsList(for: .xyRotation) == xyHits)
    }

    @MainActor
    @Test("mirror consistency: run/restore/clear keep top-level and workflow-local search results equal")
    func mirrorConsistencyAcrossRunRestoreAndClear() async throws {
        let runHits = [makeHit(id: "run-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(stubbedHits: runHits)
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v332-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.setSearchQueryText("ahe run", for: .ahe)
        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: tempRoot.path)

        var attempts = 0
        while wfs.isSearchRunning(for: .ahe) && attempts < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        #expect(wfs.searchResultsList(for: .ahe) == wfs.aheWorkspace.cachedSearchResults)
        #expect(wfs.searchResultsList(for: .ahe) == runHits)

        let restoredHits = [makeHit(id: "restore-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN41|o|STO|111")]
        wfs.aheWorkspace.cachedSearchResults = restoredHits
        wfs.restoreSearchState(results: restoredHits, queryText: "ahe restored", for: .ahe)
        #expect(wfs.searchResultsList(for: .ahe) == wfs.aheWorkspace.cachedSearchResults)

        wfs.clearWorkflowMeasurementSearch(workflowID: .ahe)
        #expect(wfs.searchResultsList(for: .ahe) == wfs.aheWorkspace.cachedSearchResults)
        #expect(wfs.searchResultsList(for: .ahe).isEmpty)
    }
}

private actor StubSearchDataActor: SpinLabDataActing {
    let stubbedHits: [WorkflowMeasurementSearchHit]

    init(stubbedHits: [WorkflowMeasurementSearchHit]) {
        self.stubbedHits = stubbedHits
    }

    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        throw NSError(domain: "StubSearchDataActor", code: 1)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        throw NSError(domain: "StubSearchDataActor", code: 2)
    }

    func searchWorkflowMeasurements(settings: LibrarySettings, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) async throws -> [WorkflowMeasurementSearchHit] {
        stubbedHits
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String : String] {
        [:]
    }
}
