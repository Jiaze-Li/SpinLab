import Foundation
import Testing
@testable import SpinLabApp

/// Regression gate for the Pack-restore numeric-display cache gap:
///
/// A live search projects both `cachedSearchResults` and `cachedSampleNumericDisplay`
/// (via `projectSearchMirrors` → `buildNumericDisplayCache`). Restoring an Analysis Pack
/// only went through `restoreSearchState` → `projectSearchResults`, which never touched
/// `cachedSampleNumericDisplay` — so `WorkflowHitRow`'s parenthesized growth-condition line
/// silently disappeared for any restored search row, in every workflow.
///
/// These tests lock the fix: `restoreSearchState` now also rebuilds the numeric-display
/// cache for every unique restored `sampleKey` (never just `.first`), guarded by a
/// per-workflow revision token so an out-of-order async write from a superseded restore
/// cannot clobber a newer one.
@Suite("Pack restore numeric-display cache")
struct PackRestoreNumericDisplayCacheTests {

    // MARK: - Helpers

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
    private func makeWFS(dataActor: any SpinLabDataActing) -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            dataActor: dataActor
        )
    }

    /// Numeric-display refresh runs on a detached Task; give it a few run-loop turns
    /// to complete before asserting. All stub lookups below resolve near-instantly.
    /// Polls for up to ~10s (400 × 25ms). The async refresh itself resolves in a few
    /// milliseconds against these in-memory stub actors; the generous ceiling only matters
    /// under heavy CPU contention from `swift test` running the entire suite in parallel —
    /// it does not slow down an isolated run, which exits as soon as the count is met.
    private func waitForCachePopulation(
        _ wfs: WorkbenchFeatureStore,
        workspace: (WorkbenchFeatureStore) -> [String: [String: String]],
        expectedCount: Int,
        maxAttempts: Int = 400
    ) async throws {
        var attempts = 0
        while workspace(wfs).count < expectedCount && attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 25_000_000)
            attempts += 1
        }
    }

    // MARK: - 1. Multi-sample restore fills numeric display for every restored sampleKey

    @MainActor
    @Test("Multi-sample Pack restore fills numeric display for every restored sampleKey")
    func multiSampleRestoreFillsAllSampleKeys() async throws {
        let actor = StubNumericDisplayDataActor(bySampleKey: [
            "PN31|b|STO|111": ["温度": "80K", "磁场": "60mT"],
            "PN32|o|STO|111": ["温度": "300K"],
        ])
        let wfs = makeWFS(dataActor: actor)
        wfs.aheWorkspace.lastLibraryRootPath = "/tmp/fake-lib-root"

        let hits = [
            makeHit(id: "ahe-a", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN31|b|STO|111"),
            makeHit(id: "ahe-b", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN32|o|STO|111"),
        ]

        wfs.restoreSearchState(results: hits, queryText: "ahe pn3", for: .ahe)

        try await waitForCachePopulation(
            wfs,
            workspace: { $0.aheWorkspace.cachedSampleNumericDisplay },
            expectedCount: 2
        )

        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay["PN31|b|STO|111"]?["磁场"] == "60mT")
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay["PN32|o|STO|111"]?["温度"] == "300K")
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay.count == 2,
                "Both restored sampleKeys must be populated, not just .first")
    }

    // MARK: - 2. Empty / legacy cachedSearchResults is safe

    @MainActor
    @Test("Empty restored results yield an empty numeric-display cache without crashing")
    func emptyRestoreYieldsEmptyCache() async throws {
        let actor = StubNumericDisplayDataActor(bySampleKey: [:])
        let wfs = makeWFS(dataActor: actor)
        wfs.threeOmegaWorkspace.lastLibraryRootPath = "/tmp/fake-lib-root"

        // Pre-seed with stale data to prove restore actively clears it, not merely skips.
        wfs.threeOmegaWorkspace.cachedSampleNumericDisplay = ["stale|key": ["温度": "1K"]]

        wfs.restoreSearchState(results: [], queryText: "", for: .threeOmega)

        // Poll until the pre-seeded stale entry is actually cleared (proves an active write
        // of [:], not merely "nothing ran yet"), tolerating heavy CPU contention.
        var attempts = 0
        while !wfs.threeOmegaWorkspace.cachedSampleNumericDisplay.isEmpty && attempts < 400 {
            try await Task.sleep(nanoseconds: 25_000_000)
            attempts += 1
        }

        #expect(wfs.threeOmegaWorkspace.cachedSampleNumericDisplay.isEmpty)
        #expect(wfs.searchResultsList(for: .threeOmega).isEmpty)
    }

    // MARK: - 3. Rapid Pack A → Pack B cannot produce a stale overwrite

    @MainActor
    @Test("Rapid Pack A then Pack B restore: slow Pack A lookup cannot clobber Pack B's cache")
    func rapidSuccessiveRestoresDoNotClobber() async throws {
        let actor = StubNumericDisplayDataActor(
            bySampleKey: [
                "PACK-A|sample": ["温度": "10K"],
                "PACK-B|sample": ["温度": "20K"],
            ],
            // Pack A's lookup is slow: it resolves well after Pack B's own restore has written.
            delayNanoseconds: ["PACK-A|sample": 500_000_000]
        )
        let wfs = makeWFS(dataActor: actor)
        wfs.rtWorkspace.lastLibraryRootPath = "/tmp/fake-lib-root"

        let hitA = makeHit(id: "rt-a", workflowID: "RT", workflowCanonicalID: "rt", sampleKey: "PACK-A|sample")
        let hitB = makeHit(id: "rt-b", workflowID: "RT", workflowCanonicalID: "rt", sampleKey: "PACK-B|sample")

        wfs.restoreSearchState(results: [hitA], queryText: "rt pack-a", for: .rt)
        // Immediately supersede with Pack B before Pack A's slow lookup resolves.
        wfs.restoreSearchState(results: [hitB], queryText: "rt pack-b", for: .rt)

        try await waitForCachePopulation(
            wfs,
            workspace: { $0.rtWorkspace.cachedSampleNumericDisplay },
            expectedCount: 1
        )
        // Let Pack A's delayed (stale) lookup fully resolve too, so we assert its write was dropped.
        // Generous margin over the 500ms stub delay to tolerate full-suite CPU contention.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        #expect(wfs.rtWorkspace.cachedSampleNumericDisplay["PACK-B|sample"]?["温度"] == "20K",
                "Pack B's cache entry must be present")
        #expect(wfs.rtWorkspace.cachedSampleNumericDisplay["PACK-A|sample"] == nil,
                "Pack A's late-arriving lookup must not resurrect its (superseded) cache entry")
        #expect(wfs.rtWorkspace.cachedSampleNumericDisplay.count == 1)
    }

    // MARK: - 4. Every workflow receives numeric display data on restore

    @MainActor
    @Test("Each workflow's restored search row receives numeric display data", arguments: [
        (wf: String.ahe, workflowID: "ahe", canonical: "ahe"),
        (wf: String.threeOmega, workflowID: "3w", canonical: "threeOmega"),
        (wf: String.xyRotation, workflowID: "XY", canonical: "xyRotation"),
        (wf: String.iv, workflowID: "IV", canonical: "iv"),
        (wf: String.rsm, workflowID: "rsm", canonical: "rsm"),
        (wf: String.rt, workflowID: "RT", canonical: "rt"),
    ])
    func perWorkflowRestorePopulatesCache(_ fixture: (wf: String, workflowID: String, canonical: String)) async throws {
        let actor = StubNumericDisplayDataActor(bySampleKey: [
            "SAMPLE|1": ["温度": "77K"],
        ])
        let wfs = makeWFS(dataActor: actor)
        setLastLibraryRootPath("/tmp/fake-lib-root", for: fixture.wf, on: wfs)

        let hit = makeHit(id: "\(fixture.wf)-hit", workflowID: fixture.workflowID,
                           workflowCanonicalID: fixture.canonical, sampleKey: "SAMPLE|1")
        wfs.restoreSearchState(results: [hit], queryText: "restored", for: fixture.wf)

        try await waitForCachePopulation(
            wfs,
            workspace: { cachedNumericDisplay(for: fixture.wf, on: $0) },
            expectedCount: 1
        )

        #expect(cachedNumericDisplay(for: fixture.wf, on: wfs)["SAMPLE|1"]?["温度"] == "77K")
    }

    @MainActor
    private func setLastLibraryRootPath(_ path: String, for wf: String, on wfs: WorkbenchFeatureStore) {
        if wf == .ahe { wfs.aheWorkspace.lastLibraryRootPath = path }
        else if wf == .threeOmega { wfs.threeOmegaWorkspace.lastLibraryRootPath = path }
        else if wf == .xyRotation { wfs.xyRotationWorkspace.lastLibraryRootPath = path }
        else if wf == .iv { wfs.ivWorkspace.lastLibraryRootPath = path }
        else if wf == .rsm { wfs.rsmWorkspace.lastLibraryRootPath = path }
        else if wf == .rt { wfs.rtWorkspace.lastLibraryRootPath = path }
    }

    @MainActor
    private func cachedNumericDisplay(for wf: String, on wfs: WorkbenchFeatureStore) -> [String: [String: String]] {
        if wf == .ahe { return wfs.aheWorkspace.cachedSampleNumericDisplay }
        if wf == .threeOmega { return wfs.threeOmegaWorkspace.cachedSampleNumericDisplay }
        if wf == .xyRotation { return wfs.xyRotationWorkspace.cachedSampleNumericDisplay }
        if wf == .iv { return wfs.ivWorkspace.cachedSampleNumericDisplay }
        if wf == .rsm { return wfs.rsmWorkspace.cachedSampleNumericDisplay }
        if wf == .rt { return wfs.rtWorkspace.cachedSampleNumericDisplay }
        return [:]
    }

    // MARK: - 5. Existing live-search behavior remains unchanged

    @MainActor
    @Test("Live search still populates canonical results and numeric-display cache as before")
    func liveSearchBehaviorUnchanged() async throws {
        let actor = StubSearchAndNumericDisplayDataActor(
            searchResults: [
                makeHit(id: "live-1", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "LIVE|1"),
            ],
            bySampleKey: ["LIVE|1": ["温度": "150K"]]
        )
        let wfs = makeWFS(dataActor: actor)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-pack-restore-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        wfs.setSearchQueryText("ahe live", for: .ahe)
        wfs.runWorkflowMeasurementSearch(workflowID: .ahe, libraryRootPath: tempRoot.path)

        var attempts = 0
        while wfs.isSearchRunning(for: .ahe) && attempts < 40 {
            try await Task.sleep(nanoseconds: 25_000_000)
            attempts += 1
        }

        #expect(wfs.searchResultsList(for: .ahe).count == 1)
        #expect(wfs.aheWorkspace.cachedSampleNumericDisplay["LIVE|1"]?["温度"] == "150K")
    }
}

// MARK: - Stubs

private actor StubNumericDisplayDataActor: SpinLabDataActing {
    let bySampleKey: [String: [String: String]]
    let delayNanoseconds: [String: UInt64]

    init(bySampleKey: [String: [String: String]], delayNanoseconds: [String: UInt64] = [:]) {
        self.bySampleKey = bySampleKey
        self.delayNanoseconds = delayNanoseconds
    }

    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        throw NSError(domain: "PackRestoreNumericDisplayCacheTests", code: 1)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        throw NSError(domain: "PackRestoreNumericDisplayCacheTests", code: 2)
    }

    func searchWorkflowMeasurements(settings: LibrarySettings, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) async throws -> [WorkflowMeasurementSearchHit] {
        []
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String: String] {
        if let delay = delayNanoseconds[sampleKey] {
            try await Task.sleep(nanoseconds: delay)
        }
        return bySampleKey[sampleKey] ?? [:]
    }
}

private actor StubSearchAndNumericDisplayDataActor: SpinLabDataActing {
    let searchResults: [WorkflowMeasurementSearchHit]
    let bySampleKey: [String: [String: String]]

    init(searchResults: [WorkflowMeasurementSearchHit], bySampleKey: [String: [String: String]]) {
        self.searchResults = searchResults
        self.bySampleKey = bySampleKey
    }

    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        throw NSError(domain: "PackRestoreNumericDisplayCacheTests", code: 1)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        throw NSError(domain: "PackRestoreNumericDisplayCacheTests", code: 2)
    }

    func searchWorkflowMeasurements(settings: LibrarySettings, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) async throws -> [WorkflowMeasurementSearchHit] {
        searchResults
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String: String] {
        bySampleKey[sampleKey] ?? [:]
    }
}
