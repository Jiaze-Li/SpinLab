import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 Pack/Restore Module Boundary — Phase 5F-3
///
/// Locks the documented Pack/Restore contract before runtime extraction.
/// Each group targets one boundary dimension from PACK_RESTORE.md:
///   1. Source inspection: restoreFromPack never calls commitRunTrace() directly
///   2. Runtime: currentRunTrace nil immediately after restore (synchronous check)
///   3. isAllSelected reflects restored mirror count, not empty
///   4. AHE legacy nil-ingestion path activates runAnalysis(); search state pre-seeded
///   5. Session-only fields (persistenceOutcome, saveMessage) not written by restore
///   6. Restore callback only writes to its own workflow canonical; other workflows unaffected
///   7. activePackID not set by restoreFromPack — loadPack() caller is responsible
@Suite("V5.3.7 Pack Restore Module Boundary")
struct V537PackRestoreModuleBoundaryTests {

    // MARK: - Shared helpers

    private func makeHit(
        id: String,
        workflowID: String,
        workflowCanonicalID: String,
        sampleKey: String = "PN31|b|STO|111"
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
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // Source inspection helpers — same pattern as V537SaveModuleBoundaryTests.
    private func loadSource(file: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: "Sources/SpinLabApp/Features/Workbench/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunction(_ name: String, from source: String) -> String? {
        guard let sig = source.range(of: "func \(name)") else { return nil }
        guard let open = source[sig.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let c = source[index]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return String(source[sig.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    // MARK: - Pack fixture builders

    private func makeThreeOmegaPack(
        hits: [WorkflowMeasurementSearchHit],
        selectedIDs: [String]
    ) throws -> (ThreeOmegaPackConfig, ThreeOmegaPackResult, AnalysisPack) {
        let config = ThreeOmegaPackConfig(
            device: "",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega",
            titleTemplate: "#tab #sample",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: false,
            plotLegendAnchor: "",
            tabStates: [:],
            chartStyleOverrides: [:],
            cachedSearchResults: hits,
            selectedSearchResultIDs: selectedIDs,
            selectedRTHit: nil,
            rtQuery: "",
            searchQueryText: "3w fixture"
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
        let pack = try AnalysisPack(
            label: "3ω Fixture",
            workflowID: "3w",
            filePaths: hits.map(\.measurementFilePath),
            sampleKeys: hits.map(\.sampleKey),
            config: config,
            result: result
        )
        return (config, result, pack)
    }

    private func makeXYPack(
        hits: [WorkflowMeasurementSearchHit],
        selectedIDs: [String]
    ) throws -> (XYRotationPackConfig, XYRotationPackResult, AnalysisPack) {
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:],
            centerBaseline: false,
            linearDetrend: false,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: "#tab #sample",
            stackOffsetMultiplier: 0.0,
            minGapFraction: 0.15,
            showPlotGrid: false,
            tabStates: [:],
            cachedSearchResults: hits,
            selectedSearchResultIDs: selectedIDs,
            searchQueryText: "xy fixture"
        )
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult())
        let pack = try AnalysisPack(
            label: "XY Fixture",
            workflowID: "xy",
            filePaths: hits.map(\.measurementFilePath),
            sampleKeys: hits.map(\.sampleKey),
            config: config,
            result: result
        )
        return (config, result, pack)
    }

    private func makeAHEPack(
        hits: [WorkflowMeasurementSearchHit],
        selectedIDs: [String],
        ingestionResult: AHEIngestionResult? = nil
    ) throws -> (AHEPackConfig, AHEPackResult, AnalysisPack) {
        let config = AHEPackConfig(
            plotAxisXOverride: "",
            plotAxisYOverride: "",
            titleTemplate: "#tab #sample",
            showPlotGrid: false,
            tabStates: [:],
            cachedSearchResults: hits,
            selectedSearchResultIDs: selectedIDs,
            searchQueryText: "ahe fixture"
        )
        let result = AHEPackResult(ingestionResult: ingestionResult)
        let pack = try AnalysisPack(
            label: "AHE Fixture",
            workflowID: "ahe",
            filePaths: hits.map(\.measurementFilePath),
            sampleKeys: hits.map(\.sampleKey),
            config: config,
            result: result
        )
        return (config, result, pack)
    }

    // MARK: - 1. Source inspection: restoreFromPack must not call commitRunTrace() directly

    @Test("3ω restoreFromPack source does not call commitRunTrace() directly")
    func threeOmegaRestoreFromPackNoDirectCommitTrace() throws {
        let source = try loadSource(file: "ThreeOmegaWorkspaceStore+Pack.swift")
        let body = try #require(
            extractFunction("restoreFromPack", from: source),
            "restoreFromPack must exist in ThreeOmegaWorkspaceStore+Pack.swift"
        )
        #expect(
            !body.contains("commitRunTrace()"),
            "3ω restoreFromPack must not call commitRunTrace() directly"
        )
    }

    @Test("XY restoreFromPack source does not call commitRunTrace() directly")
    func xyRestoreFromPackNoDirectCommitTrace() throws {
        let source = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let body = try #require(
            extractFunction("restoreFromPack", from: source),
            "restoreFromPack must exist in XYRotationWorkspaceStore.swift"
        )
        #expect(
            !body.contains("commitRunTrace()"),
            "XY restoreFromPack must not call commitRunTrace() directly"
        )
    }

    @Test("AHE restoreFromPack source does not call commitRunTrace() directly; only runAnalysis() may")
    func aheRestoreFromPackNoDirectCommitTrace() throws {
        let source = try loadSource(file: "AHEWorkspaceStore.swift")
        let body = try #require(
            extractFunction("restoreFromPack", from: source),
            "restoreFromPack must exist in AHEWorkspaceStore.swift"
        )
        // AHE legacy path calls runAnalysis() which may call commitRunTrace() internally.
        // The contract forbids calling commitRunTrace() directly from restoreFromPack itself.
        #expect(
            !body.contains("commitRunTrace()"),
            "AHE restoreFromPack must not call commitRunTrace() directly; only runAnalysis() may do so via legacy path"
        )
    }

    // MARK: - 2. Runtime: currentRunTrace nil immediately after restore

    @MainActor
    @Test("3ω restoreFromPack: currentRunTrace is nil immediately after restore")
    func threeOmegaRestoreTraceNilAfterRestore() throws {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeHit(id: "3w-trace-a", workflowID: "3w", workflowCanonicalID: "threeOmega")]
        let (config, result, pack) = try makeThreeOmegaPack(hits: hits, selectedIDs: [hits[0].id])
        var callbackFired = false

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in
            callbackFired = true
        }

        #expect(callbackFired, "restoreSearchState callback must be called during restore")
        #expect(
            store.currentRunTrace == nil,
            "currentRunTrace must not be set by restore; it is set only by commitRunTrace() after analysis"
        )
    }

    @MainActor
    @Test("XY restoreFromPack: currentRunTrace is nil immediately after restore")
    func xyRestoreTraceNilAfterRestore() throws {
        let store = XYRotationWorkspaceStore()
        let hits = [makeHit(id: "xy-trace-a", workflowID: "xy", workflowCanonicalID: "xyRotation")]
        let (config, result, pack) = try makeXYPack(hits: hits, selectedIDs: [hits[0].id])
        var callbackFired = false

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in
            callbackFired = true
        }

        #expect(callbackFired, "restoreSearchState callback must be called during restore")
        #expect(
            store.currentRunTrace == nil,
            "currentRunTrace must not be set by restore; it is set only by commitRunTrace() after analysis"
        )
    }

    // MARK: - 3. isAllSelected reflects restored mirror count, not empty

    @MainActor
    @Test("3ω restore: isAllSelected true when all 2 hits are selected")
    func threeOmegaRestoreIsAllSelectedAllSelected() throws {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [
            makeHit(id: "3w-sel-a", workflowID: "3w", workflowCanonicalID: "threeOmega"),
            makeHit(id: "3w-sel-b", workflowID: "3w", workflowCanonicalID: "threeOmega",
                    sampleKey: "PN32|o|STO|111"),
        ]
        let (config, result, pack) = try makeThreeOmegaPack(hits: hits, selectedIDs: hits.map(\.id))

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.cachedSearchResults.count == 2,
                "cachedSearchResults must reflect all restored hits")
        #expect(store.selectedSearchResultIDs.count == 2,
                "selectedSearchResultIDs must reflect all restored selected IDs")
        #expect(store.isAllSelected,
                "isAllSelected must be true when all restored hits are selected; regression guard for restore ordering errors")
    }

    @MainActor
    @Test("3ω restore: isAllSelected false when only 1 of 2 hits is selected")
    func threeOmegaRestoreIsAllSelectedPartial() throws {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [
            makeHit(id: "3w-part-a", workflowID: "3w", workflowCanonicalID: "threeOmega"),
            makeHit(id: "3w-part-b", workflowID: "3w", workflowCanonicalID: "threeOmega",
                    sampleKey: "PN32|o|STO|111"),
        ]
        let (config, result, pack) = try makeThreeOmegaPack(
            hits: hits, selectedIDs: [hits[0].id]
        )

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.cachedSearchResults.count == 2)
        #expect(store.selectedSearchResultIDs.count == 1)
        #expect(!store.isAllSelected,
                "isAllSelected must be false when only 1 of 2 restored hits is selected")
    }

    @MainActor
    @Test("XY restore: isAllSelected true when all 2 hits are selected")
    func xyRestoreIsAllSelectedAllSelected() throws {
        let store = XYRotationWorkspaceStore()
        let hits = [
            makeHit(id: "xy-sel-a", workflowID: "xy", workflowCanonicalID: "xyRotation"),
            makeHit(id: "xy-sel-b", workflowID: "xy", workflowCanonicalID: "xyRotation",
                    sampleKey: "PN32|o|STO|111"),
        ]
        let (config, result, pack) = try makeXYPack(hits: hits, selectedIDs: hits.map(\.id))

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.cachedSearchResults.count == 2)
        #expect(store.selectedSearchResultIDs.count == 2)
        #expect(store.isAllSelected,
                "isAllSelected must be true when all restored hits are selected")
    }

    @MainActor
    @Test("AHE restore: isAllSelected true when all 2 hits are selected")
    func aheRestoreIsAllSelectedAllSelected() throws {
        let store = AHEWorkspaceStore()
        let hits = [
            makeHit(id: "ahe-sel-a", workflowID: "ahe", workflowCanonicalID: "ahe"),
            makeHit(id: "ahe-sel-b", workflowID: "ahe", workflowCanonicalID: "ahe",
                    sampleKey: "PN32|o|STO|111"),
        ]
        let ingestion = AHEIngestionResult(
            candidateAxisFields: [],
            defaultAxisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [],
            sourceFiles: nil,
            warnings: []
        )
        let (config, result, pack) = try makeAHEPack(
            hits: hits, selectedIDs: hits.map(\.id), ingestionResult: ingestion
        )

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.cachedSearchResults.count == 2)
        #expect(store.selectedSearchResultIDs.count == 2)
        #expect(store.isAllSelected,
                "isAllSelected must be true when all restored hits are selected")
    }

    // MARK: - 4. AHE legacy nil-ingestion path

    /// When AHEPackResult.ingestionResult == nil (legacy packs pre-v5.3.4), restore calls
    /// runAnalysis() to reconstruct analysis state. The contract requires search state to be
    /// seeded before runAnalysis() is called so the analysis has a valid input set.
    @MainActor
    @Test("AHE legacy restore with nil ingestionResult activates runAnalysis(); search state pre-seeded")
    func aheRestoreNilIngestionActivatesRunAnalysis() throws {
        let store = AHEWorkspaceStore()
        let hit = makeHit(id: "ahe-legacy", workflowID: "ahe", workflowCanonicalID: "ahe")

        // Legacy pack: nil ingestionResult, 1 hit in cache, no selected IDs.
        // restoreFromPack calls runAnalysis() via the legacy path.
        // runAnalysis() finds no selections → synchronous guard return → plotMessage set, no Task spawned.
        var callbackHits: [WorkflowMeasurementSearchHit] = []
        var callbackQuery = ""
        let (config, result, pack) = try makeAHEPack(
            hits: [hit],
            selectedIDs: [],
            ingestionResult: nil
        )

        store.restoreFromPack(config: config, result: result, pack: pack) { hits, query in
            callbackHits = hits
            callbackQuery = query
        }

        // restoreSearchState callback must have been called with the packed hits before runAnalysis().
        #expect(callbackHits == [hit],
                "restoreSearchState callback must receive packed hits before runAnalysis() is called")
        #expect(callbackQuery == "ahe fixture",
                "restoreSearchState callback must receive packed query text")

        // Legacy path activated: runAnalysis() was called.
        // No selections → synchronous guard → plotMessage set without spawning a Task.
        #expect(
            store.plotMessage == "Select at least one AHE measurement to plot.",
            "Legacy path must activate runAnalysis(); the empty-selection guard message confirms it ran"
        )

        // cachedSearchResults and selectedSearchResultIDs were set before runAnalysis().
        #expect(store.cachedSearchResults == [hit],
                "cachedSearchResults must be restored from pack before runAnalysis() is called")
        #expect(store.selectedSearchResultIDs.isEmpty,
                "selectedSearchResultIDs reflects the packed empty selection")

        // No successful analysis completed (guard returned early), so trace was not committed.
        #expect(
            store.currentRunTrace == nil,
            "no successful analysis ran; trace must not have been committed by the guard-exit path"
        )
    }

    // MARK: - 5. Session-only fields not written by restore

    @MainActor
    @Test("3ω restore does not set persistenceOutcome or saveMessage")
    func threeOmegaRestoreDoesNotSetSessionOnlyFields() throws {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeHit(id: "3w-session", workflowID: "3w", workflowCanonicalID: "threeOmega")]
        let (config, result, pack) = try makeThreeOmegaPack(hits: hits, selectedIDs: [hits[0].id])

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.persistenceOutcome == nil,
                "restore must not write persistenceOutcome — it is session-only, owned by Save Module")
        #expect(store.saveMessage == nil,
                "restore must not write saveMessage — it is session-only, owned by Save Module")
    }

    @MainActor
    @Test("XY restore does not set persistenceOutcome or saveMessage")
    func xyRestoreDoesNotSetSessionOnlyFields() throws {
        let store = XYRotationWorkspaceStore()
        let hits = [makeHit(id: "xy-session", workflowID: "xy", workflowCanonicalID: "xyRotation")]
        let (config, result, pack) = try makeXYPack(hits: hits, selectedIDs: [hits[0].id])

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.persistenceOutcome == nil,
                "restore must not write persistenceOutcome — it is session-only, owned by Save Module")
        #expect(store.saveMessage == nil,
                "restore must not write saveMessage — it is session-only, owned by Save Module")
    }

    @MainActor
    @Test("AHE restore (non-legacy) does not set persistenceOutcome or saveMessage")
    func aheRestoreNonLegacyDoesNotSetSessionOnlyFields() throws {
        let store = AHEWorkspaceStore()
        let hits = [makeHit(id: "ahe-session", workflowID: "ahe", workflowCanonicalID: "ahe")]
        let ingestion = AHEIngestionResult(
            candidateAxisFields: [],
            defaultAxisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [],
            sourceFiles: nil,
            warnings: []
        )
        let (config, result, pack) = try makeAHEPack(
            hits: hits, selectedIDs: [hits[0].id], ingestionResult: ingestion
        )

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(store.persistenceOutcome == nil,
                "restore must not write persistenceOutcome — it is session-only, owned by Save Module")
        #expect(store.saveMessage == nil,
                "restore must not write saveMessage — it is session-only, owned by Save Module")
    }

    // MARK: - 6. Restore only writes to its own workflow canonical

    @MainActor
    @Test("3ω restore callback only writes threeOmega canonical; pre-seeded AHE canonical unaffected")
    func threeOmegaRestoreDoesNotCorruptAheCanonical() throws {
        let wfs = makeWFS()

        // Pre-seed AHE canonical with known state.
        let aheHit = makeHit(id: "ahe-pre", workflowID: "ahe", workflowCanonicalID: "ahe")
        wfs.restoreSearchState(results: [aheHit], queryText: "ahe pre-seeded", for: .ahe)
        wfs.searchMessages[.ahe] = "AHE pre-seeded message"

        let aheQueryBefore = wfs.searchQueryText(for: .ahe)
        let aheResultsBefore = wfs.searchResultsList(for: .ahe)
        let aheMessageBefore = wfs.searchMessage(for: .ahe)
        let aheRunningBefore = wfs.isSearchRunning(for: .ahe)

        // Restore a 3ω pack; callback writes only to threeOmega canonical.
        let threeHit = makeHit(id: "3w-cb", workflowID: "3w", workflowCanonicalID: "threeOmega")
        let (config, result, pack) = try makeThreeOmegaPack(
            hits: [threeHit], selectedIDs: [threeHit.id]
        )

        wfs.threeOmegaWorkspace.restoreFromPack(config: config, result: result, pack: pack) { hits, query in
            wfs.restoreSearchState(results: hits, queryText: query, for: .threeOmega)
        }

        // AHE canonical must be unchanged by the 3ω restore.
        #expect(wfs.searchQueryText(for: .ahe) == aheQueryBefore,
                "3ω restore must not change AHE canonical query text")
        #expect(wfs.searchResultsList(for: .ahe) == aheResultsBefore,
                "3ω restore must not change AHE canonical results")
        #expect(wfs.searchMessage(for: .ahe) == aheMessageBefore,
                "3ω restore must not change AHE canonical message")
        #expect(wfs.isSearchRunning(for: .ahe) == aheRunningBefore,
                "3ω restore must not change AHE canonical running state")

        // threeOmega canonical must reflect the restore.
        #expect(wfs.searchResultsList(for: .threeOmega) == [threeHit],
                "threeOmega canonical must reflect the restored hits")
    }

    @MainActor
    @Test("XY restore callback only writes xyRotation canonical; pre-seeded 3ω canonical unaffected")
    func xyRestoreDoesNotCorruptThreeOmegaCanonical() throws {
        let wfs = makeWFS()

        // Pre-seed 3ω canonical.
        let threeHit = makeHit(id: "3w-pre", workflowID: "3w", workflowCanonicalID: "threeOmega")
        wfs.restoreSearchState(results: [threeHit], queryText: "3w pre-seeded", for: .threeOmega)
        wfs.searchMessages[.threeOmega] = "3ω pre-seeded message"

        let threeQueryBefore = wfs.searchQueryText(for: .threeOmega)
        let threeResultsBefore = wfs.searchResultsList(for: .threeOmega)
        let threeMessageBefore = wfs.searchMessage(for: .threeOmega)
        let threeRunningBefore = wfs.isSearchRunning(for: .threeOmega)

        // Restore an XY pack; callback writes only to xyRotation canonical.
        let xyHit = makeHit(id: "xy-cb", workflowID: "xy", workflowCanonicalID: "xyRotation")
        let (config, result, pack) = try makeXYPack(hits: [xyHit], selectedIDs: [xyHit.id])

        wfs.xyRotationWorkspace.restoreFromPack(config: config, result: result, pack: pack) { hits, query in
            wfs.restoreSearchState(results: hits, queryText: query, for: .xyRotation)
        }

        // 3ω canonical must be unchanged by the XY restore.
        #expect(wfs.searchQueryText(for: .threeOmega) == threeQueryBefore,
                "XY restore must not change 3ω canonical query text")
        #expect(wfs.searchResultsList(for: .threeOmega) == threeResultsBefore,
                "XY restore must not change 3ω canonical results")
        #expect(wfs.searchMessage(for: .threeOmega) == threeMessageBefore,
                "XY restore must not change 3ω canonical message")
        #expect(wfs.isSearchRunning(for: .threeOmega) == threeRunningBefore,
                "XY restore must not change 3ω canonical running state")

        // XY canonical must reflect the restore.
        #expect(wfs.searchResultsList(for: .xyRotation) == [xyHit],
                "xyRotation canonical must reflect the restored hits")
    }

    // MARK: - 7. activePackID not set by restoreFromPack

    @MainActor
    @Test("3ω restoreFromPack does not set activePackID — loadPack() caller is responsible")
    func threeOmegaRestoreFromPackDoesNotSetActivePackID() throws {
        let store = ThreeOmegaWorkspaceStore()
        let hits = [makeHit(id: "3w-packid", workflowID: "3w", workflowCanonicalID: "threeOmega")]
        let (config, result, pack) = try makeThreeOmegaPack(hits: hits, selectedIDs: [hits[0].id])

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(
            store.activePackID == nil,
            "activePackID must remain nil after restoreFromPack; loadPack() sets it after restore returns"
        )
    }

    @MainActor
    @Test("XY restoreFromPack does not set activePackID — loadPack() caller is responsible")
    func xyRestoreFromPackDoesNotSetActivePackID() throws {
        let store = XYRotationWorkspaceStore()
        let hits = [makeHit(id: "xy-packid", workflowID: "xy", workflowCanonicalID: "xyRotation")]
        let (config, result, pack) = try makeXYPack(hits: hits, selectedIDs: [hits[0].id])

        store.restoreFromPack(config: config, result: result, pack: pack) { _, _ in }

        #expect(
            store.activePackID == nil,
            "activePackID must remain nil after restoreFromPack; loadPack() sets it after restore returns"
        )
    }
}
