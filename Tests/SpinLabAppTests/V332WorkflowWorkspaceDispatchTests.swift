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

    @MainActor
    private func waitForSearchToFinish(_ wfs: WorkbenchFeatureStore, workflowID: WorkflowKey) async throws {
        var attempts = 0
        while wfs.isSearchRunning(for: workflowID) && attempts < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
    }


    @Test("WorkflowWorkspaceRegistry type exists and compiles")
    func registryExists() {
        // Compile-time smoke test: if WorkflowWorkspaceRegistry is removed or
        // renamed this function body will no longer build.
        _ = WorkflowWorkspaceRegistry.self
    }

    @MainActor
    @Test("runWorkflowMeasurementSearch syncs canonical results into the workflow mirror")
    func runSearchSyncsCanonicalResultsAndMirror() async throws {
        let runHits = [makeHit(id: "run-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(stubbedHits: runHits)
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v332-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.setSearchQueryText("ahe run", for: .ahe)
        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: tempRoot.path)

        try await waitForSearchToFinish(wfs, workflowID: .ahe)

        #expect(wfs.searchResultsList(for: .ahe) == runHits)
        #expect(wfs.aheWorkspace.cachedSearchResults == runHits)
        #expect(wfs.searchResultsList(for: .ahe) == wfs.aheWorkspace.cachedSearchResults)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay[runHits[0].sampleKey]?["温度"] == "80K")
        #expect(wfs.searchMessage(for: .ahe) == "Found 1 file(s).")
    }

    @MainActor
    @Test("runWorkflowMeasurementSearch syncs canonical results and mirrors into the RT workspace")
    func runSearchSyncsCanonicalResultsAndMirrorForRT() async throws {
        let runHits = [makeHit(id: "rt-run-1", workflowID: "RT", workflowCanonicalID: "RT", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(stubbedHits: runHits)
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v332-search-rt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.setSearchQueryText("RT run", for: .rt)
        wfs.runWorkflowMeasurementSearch(workflowID: .rt, libraryRootPath: tempRoot.path)

        try await waitForSearchToFinish(wfs, workflowID: .rt)

        #expect(wfs.searchResultsList(for: .rt) == runHits)
        #expect(wfs.rtWorkspace.cachedSearchResults == runHits)
        #expect(wfs.rtWorkspace.cachedSearchResults == wfs.searchResultsList(for: .rt))
        #expect(wfs.rtWorkspace.cachedSampleNumericDisplay[runHits[0].sampleKey]?["温度"] == "80K")
        #expect(wfs.rtWorkspace.lastLibraryRootPath == tempRoot.path)
        #expect(wfs.searchMessage(for: .rt) == "Found 1 file(s).")

        wfs.clearWorkflowMeasurementSearch(workflowID: .rt)
        #expect(wfs.searchResultsList(for: .rt).isEmpty)
        #expect(wfs.rtWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.rtWorkspace.cachedSampleNumericDisplay.isEmpty)
        #expect(wfs.searchMessage(for: .rt) == nil)
        #expect(wfs.isSearchRunning(for: .rt) == false)
    }

    @MainActor
    @Test("clearWorkflowMeasurementSearch propagates cache-clear to aheWorkspace")
    func clearSearchPropagatestoAHESubStore() async throws {
        let runHits = [makeHit(id: "run-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(stubbedHits: runHits)
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v332-clear-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.setSearchQueryText("ahe run", for: .ahe)
        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: tempRoot.path)

        try await waitForSearchToFinish(wfs, workflowID: .ahe)

        #expect(wfs.searchResultsList(for: .ahe) == runHits)
        #expect(wfs.aheWorkspace.cachedSearchResults == runHits)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay.isEmpty == false)

        wfs.clearWorkflowMeasurementSearch(workflowID: .ahe)
        #expect(wfs.searchResultsList(for: .ahe).isEmpty)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay.isEmpty)
        #expect(wfs.searchQueryText(for: .ahe) == WorkflowKey.ahe.searchPrefix)
        #expect(wfs.searchMessage(for: .ahe) == nil)
        #expect(wfs.isSearchRunning(for: .ahe) == false)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
    }

    @MainActor
    @Test("empty query clears canonical results and workflow-local mirrors")
    func emptyQueryClearsCanonicalAndMirrors() {
        let runHits = [makeHit(id: "seed-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(stubbedHits: runHits)
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v332-empty-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.restoreSearchState(results: runHits, queryText: "ahe run", for: .ahe)
        wfs.aheWorkspace.cachedSampleNumericDisplay = [runHits[0].sampleKey: ["温度": "80K"]]
        wfs.setSearchQueryText("   ", for: .ahe)

        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: tempRoot.path)

        #expect(wfs.searchResultsList(for: .ahe).isEmpty)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay.isEmpty)
        #expect(wfs.searchMessage(for: .ahe) == "Enter workflow query, for example: AHE PN31 80K")
        #expect(wfs.isSearchRunning(for: .ahe) == false)
        #expect(wfs.searchQueryText(for: .ahe) == "   ")
    }

    @MainActor
    @Test("missing library root clears canonical results and workflow-local mirrors")
    func missingLibraryRootClearsCanonicalAndMirrors() {
        let runHits = [makeHit(id: "seed-2", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(stubbedHits: runHits)
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        wfs.restoreSearchState(results: runHits, queryText: "ahe run", for: .ahe)
        wfs.aheWorkspace.cachedSampleNumericDisplay = [runHits[0].sampleKey: ["温度": "80K"]]
        wfs.setSearchQueryText("ahe run", for: .ahe)

        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: nil)

        #expect(wfs.searchResultsList(for: .ahe).isEmpty)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay.isEmpty)
        #expect(wfs.searchMessage(for: .ahe) == "Set Library Root before searching.")
        #expect(wfs.isSearchRunning(for: .ahe) == false)
        #expect(wfs.searchQueryText(for: .ahe) == "ahe run")
    }

    @MainActor
    @Test("search failure clears canonical results and workflow-local mirrors")
    func searchFailureClearsCanonicalAndMirrors() async throws {
        let runHits = [makeHit(id: "seed-3", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN40|b|STO|111")]
        let actor = StubSearchDataActor(
            stubbedHits: runHits,
            failingQuery: "force fail"
        )
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: actor
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v332-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.restoreSearchState(results: runHits, queryText: "ahe run", for: .ahe)
        wfs.aheWorkspace.cachedSampleNumericDisplay = [runHits[0].sampleKey: ["温度": "80K"]]
        wfs.setSearchQueryText("force fail", for: .ahe)

        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: tempRoot.path)
        try await waitForSearchToFinish(wfs, workflowID: .ahe)

        #expect(wfs.searchResultsList(for: .ahe).isEmpty)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay.isEmpty)
        #expect(wfs.searchMessage(for: .ahe) == "simulated search failure")
        #expect(wfs.isSearchRunning(for: .ahe) == false)
        #expect(wfs.searchQueryText(for: .ahe) == "force fail")
    }

    @MainActor
    @Test("restoreSearchState rehydrates canonical search state and workflow mirrors")
    func restoreSearchStateRehydratesCanonicalAndWorkflowMirrors() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        let aheHits = [makeHit(id: "ahe-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN31|b|STO|111")]
        let xyHits = [makeHit(id: "xy-1", workflowID: "xy", workflowCanonicalID: "xy", sampleKey: "PN32|o|STO|111")]

        wfs.setSearchQueryText("ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = []
        wfs.restoreSearchState(results: aheHits, queryText: "ahe pn31", for: .ahe)
        #expect(wfs.searchQueryText(for: .ahe) == "ahe pn31")
        #expect(wfs.searchResultsList(for: .ahe) == aheHits)
        #expect(wfs.aheWorkspace.cachedSearchResults == aheHits)
        #expect(wfs.searchMessage(for: .ahe) == "Restored from analysis pack (1 hit(s)).")
        #expect(wfs.isSearchRunning(for: .ahe) == false)

        wfs.setSearchQueryText("xy pn32", for: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = []
        wfs.restoreSearchState(results: xyHits, queryText: "xy pn32", for: .xyRotation)
        #expect(wfs.searchQueryText(for: .xyRotation) == "xy pn32")
        #expect(wfs.searchResultsList(for: .xyRotation) == xyHits)
        #expect(wfs.xyRotationWorkspace.cachedSearchResults == xyHits)
        #expect(wfs.searchMessage(for: .xyRotation) == "Restored from analysis pack (1 hit(s)).")
        #expect(wfs.isSearchRunning(for: .xyRotation) == false)

        wfs.selectWorkflow("ahe")
        wfs.selectWorkflow("xy")
        wfs.selectWorkflow("ahe")

        #expect(wfs.searchResultsList(for: .ahe) == aheHits)
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
        wfs.aheWorkspace.cachedSearchResults = []
        wfs.restoreSearchState(results: restoredHits, queryText: "ahe restored", for: .ahe)
        #expect(wfs.searchResultsList(for: .ahe) == restoredHits)
        #expect(wfs.searchResultsList(for: .ahe) == wfs.aheWorkspace.cachedSearchResults)

        wfs.clearWorkflowMeasurementSearch(workflowID: .ahe)
        #expect(wfs.searchResultsList(for: .ahe) == wfs.aheWorkspace.cachedSearchResults)
        #expect(wfs.searchResultsList(for: .ahe).isEmpty)
    }
}

private actor StubSearchDataActor: SpinLabDataActing {
    let stubbedHits: [WorkflowMeasurementSearchHit]
    let failingQuery: String?

    init(stubbedHits: [WorkflowMeasurementSearchHit], failingQuery: String? = nil) {
        self.stubbedHits = stubbedHits
        self.failingQuery = failingQuery
    }

    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        throw NSError(domain: "StubSearchDataActor", code: 1)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        throw NSError(domain: "StubSearchDataActor", code: 2)
    }

    func searchWorkflowMeasurements(settings: LibrarySettings, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) async throws -> [WorkflowMeasurementSearchHit] {
        if let failingQuery, query.rawText == failingQuery {
            throw NSError(
                domain: "StubSearchDataActor",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "simulated search failure"]
            )
        }
        return stubbedHits
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String : String] {
        guard sampleKey == "PN40|b|STO|111" else { return [:] }
        return ["温度": "80K", "氧压": "60mJ"]
    }
}
