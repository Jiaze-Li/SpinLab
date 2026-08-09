import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5C-2 — Selection semantics convergence architecture guards.
///
/// Locks in the contract from the Phase 5C-1 audit:
///   1. search results are canonical
///   2. selection stores IDs
///   3. selectedCount reflects current visible/canonical results
///   4. restore drops dangling IDs
///   5. Analyze uses snapshot-only input
///   6. ThreeOmega RT secondary-picker behavior is preserved unchanged
@Suite("Phase 5C-2 Selection Semantics Convergence Guards")
struct SelectionSemanticsConvergenceGuardTests {

    private func makeHit(id: String, workflowID: String, workflowCanonicalID: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    private func loadSource(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 1. selectedCount is intersection with current canonical result IDs

    @MainActor
    @Test("selectedCount excludes IDs selected from a superseded search")
    func selectedCountExcludesSupersededIDs() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A", workflowID: "ahe", workflowCanonicalID: "ahe")
        let hitB = makeHit(id: "B", workflowID: "ahe", workflowCanonicalID: "ahe")

        wfs.restoreSearchState(results: [hitA], queryText: "q1", for: .ahe)
        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)
        #expect(wfs.selectedCount(for: .ahe) == 1)

        wfs.restoreSearchState(results: [hitB], queryText: "q2", for: .ahe)
        // hitA is still in the internal basket but off-screen relative to current results.
        #expect(wfs.selectedCount(for: .ahe) == 0,
                "selectedCount must intersect selected IDs with the current canonical result set")

        wfs.toggleSearchHitSelection(hitB.id, for: .ahe)
        #expect(wfs.selectedCount(for: .ahe) == 1)
    }

    // MARK: - 2. stale IDs do not affect isAllSelected

    @MainActor
    @Test("isAllSelected ignores stale IDs from a superseded search")
    func isAllSelectedIgnoresStaleIDs() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A", workflowID: "xy", workflowCanonicalID: "xyRotation")
        let hitB = makeHit(id: "B", workflowID: "xy", workflowCanonicalID: "xyRotation")
        let hitC = makeHit(id: "C", workflowID: "xy", workflowCanonicalID: "xyRotation")

        wfs.restoreSearchState(results: [hitA], queryText: "q1", for: .xyRotation)
        wfs.selectAll(for: .xyRotation)
        #expect(wfs.isAllSelected(for: .xyRotation))

        // New, disjoint result set: hitA (still selected in the basket) is stale/off-screen.
        wfs.restoreSearchState(results: [hitB, hitC], queryText: "q2", for: .xyRotation)
        #expect(!wfs.isAllSelected(for: .xyRotation),
                "stale hitA selection must not make isAllSelected true for an unrelated current result set")

        wfs.selectAll(for: .xyRotation)
        #expect(wfs.isAllSelected(for: .xyRotation))
    }

    // MARK: - 3. restore drops dangling IDs

    @MainActor
    @Test("seedRestoredSelection drops IDs with no matching hit in availableHits")
    func seedRestoredSelectionDropsDanglingIDs() {
        let wfs = makeWFS()
        let hit = makeHit(id: "real", workflowID: "ahe", workflowCanonicalID: "ahe")

        wfs.seedRestoredSelection([hit.id, "ghost-id"], availableHits: [hit], for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe) == [hit.id],
                "the ghost ID must be dropped, not kept dangling")
    }

    @MainActor
    @Test("seedRestoredSelection with all IDs missing yields an empty selection")
    func seedRestoredSelectionAllIDsMissing() {
        let wfs = makeWFS()
        let hit = makeHit(id: "unrelated", workflowID: "ahe", workflowCanonicalID: "ahe")

        wfs.seedRestoredSelection(["ghost-1", "ghost-2"], availableHits: [hit], for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).isEmpty)
        #expect(wfs.selectedCount(for: .ahe) == 0)
    }

    @MainActor
    @Test("seedRestoredSelection with all IDs valid keeps every ID")
    func seedRestoredSelectionAllIDsValid() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A", workflowID: "ahe", workflowCanonicalID: "ahe")
        let hitB = makeHit(id: "B", workflowID: "ahe", workflowCanonicalID: "ahe")

        wfs.seedRestoredSelection([hitA.id, hitB.id], availableHits: [hitA, hitB], for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe) == [hitA.id, hitB.id])
    }

    // MARK: - 4. tray row count matches selectedCount after restore

    @MainActor
    @Test("selected-hit display row count matches selectedCount after reconciled restore")
    func trayRowCountMatchesSelectedCountAfterRestore() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A", workflowID: "ahe", workflowCanonicalID: "ahe")
        let hitB = makeHit(id: "B", workflowID: "ahe", workflowCanonicalID: "ahe")

        // Persisted selection includes a dangling ID with no matching restored hit.
        wfs.seedRestoredSelection([hitA.id, hitB.id, "dangling"], availableHits: [hitA, hitB], for: .ahe)
        wfs.restoreSearchState(results: [hitA, hitB], queryText: "restored", for: .ahe)

        let rowCount = wfs.selectedHitDisplayInfos(for: .ahe).count
        #expect(rowCount == wfs.selectedCount(for: .ahe),
                "tray row count and selectedCount must agree after a reconciled restore")
        #expect(rowCount == 2)
    }

    // MARK: - 5. shipped Analyze path requires WorkbenchSelectedHitsSnapshot

    @Test("WorkflowWorkspaceActionBar's Analyze action calls runAnalysis(selectedHitsSnapshot:) built from the facade")
    func shippedAnalyzePathUsesSelectedHitsSnapshot() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift")
        #expect(source.contains("store.runAnalysis(selectedHitsSnapshot: workbench.selectedHitsSnapshot(for: workflowID))"))
    }

    @Test("runAnalysis(selectedHitsSnapshot:) is non-optional on the shared protocol — no live-state fallback path can exist")
    func runAnalysisSelectedHitsSnapshotIsNonOptional() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift")
        #expect(source.contains("func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot)"))
        #expect(!source.contains("func runAnalysis()"))
        #expect(!source.contains("func runAnalysis(searchSnapshot:"))
    }

    // MARK: - 6. no production Analyze implementation re-reads live search state mid-run

    @Test(
        "no workspace store's runAnalysis(selectedHitsSnapshot:) implementation reads cachedSearchResults or selectionReading",
        arguments: [
            "Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift",
            "Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift",
            "Sources/SpinLabApp/Features/Workbench/RTWorkspaceStore.swift",
            "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift",
            "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift",
            "Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift",
        ]
    )
    func runAnalysisImplementationDoesNotReadLiveState(relativePath: String) throws {
        let source = try loadSource(relativePath: relativePath)
        guard let start = source.range(of: "func runAnalysis(selectedHitsSnapshot:") else {
            Issue.record("runAnalysis(selectedHitsSnapshot:) not found in \(relativePath)")
            return
        }
        // Slice from the method start to the next top-level "func " or end of file, matching
        // braces is unnecessary here since we only need to check body text does not appear.
        let rest = source[start.lowerBound...]
        let nextFunc = rest.range(of: "\n    func ", range: rest.index(after: rest.startIndex)..<rest.endIndex)
        let body = nextFunc.map { rest[rest.startIndex..<$0.lowerBound] } ?? rest
        #expect(!body.contains("cachedSearchResults"),
                "\(relativePath): runAnalysis(selectedHitsSnapshot:) must not read cachedSearchResults")
        #expect(!body.contains("selectionReading"),
                "\(relativePath): runAnalysis(selectedHitsSnapshot:) must not read selectionReading")
    }

    // MARK: - 7. RSM has only one cachedSearchResults declaration on the store type

    @Test("RSMWorkspaceStore declares cachedSearchResults exactly once as a stored property on the class")
    func rsmHasSingleStoreLevelCachedSearchResultsDeclaration() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
        // RSMPackConfig (a separate Codable type in the same file) also has a field with this
        // name — that is the normal pack-config/store-mirror pairing every workflow has, not a
        // duplicate. This guard checks the class-level stored property specifically.
        guard let classRange = source.range(of: "final class RSMWorkspaceStore") else {
            Issue.record("RSMWorkspaceStore class declaration not found")
            return
        }
        let classBody = source[classRange.lowerBound...]
        let occurrences = classBody.components(separatedBy: "var cachedSearchResults: [WorkflowMeasurementSearchHit] = []").count - 1
        #expect(occurrences == 1,
                "RSMWorkspaceStore (the class) must declare cachedSearchResults exactly once")
    }

    // MARK: - 8. RSM selection restores consistently with sibling workflows

    @MainActor
    @Test("RSM restore seeds selection from the persisted IDs, reconciled against restored hits")
    func rsmRestoreSeedsSelectionConsistently() throws {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm", workflowCanonicalID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm", workflowCanonicalID: "rsm")

        let config = RSMPackConfig(
            packState: RSMPackState(detectorColumnName: "detector"),
            displayState: HeatmapTabRenderState(),
            cachedSearchResults: [hitA, hitB],
            searchQueryText: "rsm query",
            selectedSearchResultIDs: [hitA.id, "rsm-ghost"]
        )
        let result = RSMPackResult()
        let pack = AnalysisPack(
            label: "test",
            workflowID: "rsm",
            createdAt: .distantPast,
            filePaths: [],
            sampleKeys: [],
            config: (try? JSONEncoder().encode(config)) ?? Data(),
            result: (try? JSONEncoder().encode(result)) ?? Data()
        )

        var seededIDs: Set<String> = []
        var seededHits: [WorkflowMeasurementSearchHit] = []
        store.restoreFromPack(
            config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { ids, hits in
                seededIDs = ids
                seededHits = hits
            }
        )

        #expect(seededIDs == [hitA.id, "rsm-ghost"],
                "restoreFromPack must pass the persisted IDs through to the seedSelection closure unfiltered — reconciliation happens inside the closure (seedRestoredSelection), not in RSMWorkspaceStore itself")
        #expect(seededHits == [hitA, hitB])
    }

    @MainActor
    @Test("RSMPackConfig decodes legacy packs with no selectedSearchResultIDs field to an empty selection")
    func rsmPackConfigDecodesLegacyPacksWithoutSelectedIDs() throws {
        let legacyJSON = """
        {
          "packState": { "schemaVersion": 1, "detectorColumnName": "detector", "activeView": "hl" },
          "displayState": {},
          "cachedSearchResults": [],
          "searchQueryText": ""
        }
        """
        let data = Data(legacyJSON.utf8)
        let config = try JSONDecoder().decode(RSMPackConfig.self, from: data)
        #expect(config.selectedSearchResultIDs.isEmpty,
                "legacy RSM packs without selectedSearchResultIDs must still decode, defaulting to no selection")
    }

    // MARK: - 9. ThreeOmega RT picker remains unchanged

    @Test("ThreeOmega RT secondary picker keeps its single-hit, auto-run interaction model")
    func threeOmegaRTPickerUnchanged() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift")
        #expect(source.contains("var selectedRTHit: WorkflowMeasurementSearchHit?"),
                "RT selection must remain a single optional hit, not a Set<String> of IDs")

        let selectionSource = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift")
        #expect(selectionSource.contains("func selectRTHit"))
        #expect(selectionSource.contains("launchRTAnalysis"),
                "picking an RT hit must still auto-launch analysis, unlike the main multi-select + explicit Analyze flow")
    }

    // MARK: - 10. cachedSearchResults pack compatibility remains intact

    @Test(
        "cachedSearchResults remains a persisted field on every workflow pack config",
        arguments: [
            "Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift",
            "Sources/SpinLabApp/Workbench/V3/IVPackContracts.swift",
            "Sources/SpinLabApp/Workbench/V3/RTPackContracts.swift",
            "Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift",
        ]
    )
    func cachedSearchResultsRemainsPersisted(relativePath: String) throws {
        let source = try loadSource(relativePath: relativePath)
        #expect(source.contains("cachedSearchResults"),
                "\(relativePath): Phase 5C-2 explicitly defers removing cachedSearchResults persistence")
    }
}
