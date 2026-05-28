import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.3.7 Save Module Boundary")
struct V537SaveModuleBoundaryTests {

    // MARK: - Shared fixtures

    private struct CanonicalSearchState: Equatable {
        var query: String
        var results: [WorkflowMeasurementSearchHit]
        var message: String?
        var running: Bool
    }

    @MainActor
    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    private func makeHit(
        id: String,
        workflowID: String,
        workflowDisplayName: String,
        workflowCanonicalID: String,
        measurementFilePath: String? = nil,
        sourceFilePath: String? = nil
    ) -> WorkflowMeasurementSearchHit {
        let path = measurementFilePath ?? "/tmp/\(id).dat"
        let src = sourceFilePath ?? path
        return WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: path,
            sourceFilePath: src,
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
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
    private func canonicalSearchState(
        _ wfs: WorkbenchFeatureStore,
        workflow: WorkbenchWorkflowID
    ) -> CanonicalSearchState {
        CanonicalSearchState(
            query: wfs.searchQueryText(for: workflow),
            results: wfs.searchResultsList(for: workflow),
            message: wfs.searchMessage(for: workflow),
            running: wfs.isSearchRunning(for: workflow)
        )
    }

    private func waitUntil(
        timeoutMS: UInt64,
        predicate: @escaping @Sendable () async -> Bool
    ) async {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for condition.")
    }

    private func waitForAHEAnalysis(_ store: AHEWorkspaceStore, timeoutMS: UInt64 = 1500) async {
        await waitUntil(timeoutMS: timeoutMS) {
            await MainActor.run { !store.isPlotRendering }
        }
    }

    private func waitForXYAnalysis(_ store: XYRotationWorkspaceStore, timeoutMS: UInt64 = 1500) async {
        await waitUntil(timeoutMS: timeoutMS) {
            await MainActor.run { !store.isAnalyzing }
        }
    }

    private func waitForThreeOmegaAnalysis(_ store: ThreeOmegaWorkspaceStore, timeoutMS: UInt64 = 1500) async {
        await waitUntil(timeoutMS: timeoutMS) {
            await MainActor.run { !store.isAnalyzing }
        }
    }

    private func sentinelTrace(runID: String, workflowID: String) -> WorkbenchRunTraceProjection {
        WorkbenchRunTraceProjection(
            runID: runID,
            workflowID: workflowID,
            inputFiles: [],
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            semanticParams: [:],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: .distantPast
        )
    }

    // Source inspection helpers

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

    // MARK: - 1+2: Nil PNG guard — Search and Selection isolation

    @MainActor
    @Test("AHE persistToLibrary with nil PNG preserves canonical search and selection state")
    func ahePersistNilPNGPreservesSearchAndSelection() {
        let wfs = makeWorkbenchStore()
        let store = AHEWorkspaceStore()
        let hit = makeHit(
            id: "ahe-save-search",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe"
        )

        wfs.restoreSearchState(results: [hit], queryText: "ahe save boundary", for: .ahe)
        wfs.searchMessages[.ahe] = "AHE search message"
        let before = canonicalSearchState(wfs, workflow: .ahe)

        store.cachedSearchResults = [hit]
        store.selectedSearchResultIDs = [hit.id]

        // No PNG available — synchronous early return; no Task created
        store.persistToLibrary()

        #expect(canonicalSearchState(wfs, workflow: .ahe) == before)
        #expect(store.selectedSearchResultIDs == [hit.id])
        #expect(store.cachedSearchResults == [hit])
    }

    @MainActor
    @Test("XY persistToLibrary with nil PNG preserves canonical search and selection state")
    func xyPersistNilPNGPreservesSearchAndSelection() {
        let wfs = makeWorkbenchStore()
        let store = XYRotationWorkspaceStore()
        let hit = makeHit(
            id: "xy-save-search",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xyRotation"
        )

        wfs.restoreSearchState(results: [hit], queryText: "xy save boundary", for: .xyRotation)
        wfs.searchMessages[.xyRotation] = "XY search message"
        let before = canonicalSearchState(wfs, workflow: .xyRotation)

        store.cachedSearchResults = [hit]
        store.selectedSearchResultIDs = [hit.id]

        store.persistToLibrary()

        #expect(canonicalSearchState(wfs, workflow: .xyRotation) == before)
        #expect(store.selectedSearchResultIDs == [hit.id])
        #expect(store.cachedSearchResults == [hit])
    }

    @MainActor
    @Test("3ω persistToLibrary with nil PNG preserves canonical search and selection state")
    func threeOmegaPersistNilPNGPreservesSearchAndSelection() {
        let wfs = makeWorkbenchStore()
        let store = ThreeOmegaWorkspaceStore()
        let hit = makeHit(
            id: "3w-save-search",
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: "threeOmega"
        )

        wfs.restoreSearchState(results: [hit], queryText: "3w save boundary", for: .threeOmega)
        wfs.searchMessages[.threeOmega] = "3w search message"
        let before = canonicalSearchState(wfs, workflow: .threeOmega)

        store.cachedSearchResults = [hit]
        store.selectedSearchResultIDs = [hit.id]

        store.persistToLibrary()

        #expect(canonicalSearchState(wfs, workflow: .threeOmega) == before)
        #expect(store.selectedSearchResultIDs == [hit.id])
        #expect(store.cachedSearchResults == [hit])
    }

    // MARK: - 3: Nil PNG guard — save fields contained

    @MainActor
    @Test("AHE nil PNG guard sets only plotMessage; persistenceOutcome and currentRunTrace unchanged")
    func ahePersistNilPNGIsContained() {
        let store = AHEWorkspaceStore()
        store.currentRunTrace = sentinelTrace(runID: "sentinel-ahe-png", workflowID: "ahe")
        store.selectedSearchResultIDs = ["id-ahe"]

        store.persistToLibrary()

        // Message field: AHE uses plotMessage (documents test-6 routing)
        #expect(store.plotMessage == "No chart to save. Render first.")
        // Save-side fields unchanged
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-ahe-png")
        // Analysis output untouched
        #expect(store.ingestionResult == nil)
        // Selection untouched
        #expect(store.selectedSearchResultIDs == ["id-ahe"])
    }

    @MainActor
    @Test("XY nil PNG guard sets only analysisMessage; persistenceOutcome and currentRunTrace unchanged")
    func xyPersistNilPNGIsContained() {
        let store = XYRotationWorkspaceStore()
        store.currentRunTrace = sentinelTrace(runID: "sentinel-xy-png", workflowID: "xy")
        store.selectedSearchResultIDs = ["id-xy"]

        store.persistToLibrary()

        // Message field: XY uses analysisMessage (documents test-6 routing)
        #expect(store.analysisMessage == "No chart to save. Run analysis first.")
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-xy-png")
        #expect(store.ingestionResult == nil)
        #expect(store.selectedSearchResultIDs == ["id-xy"])
    }

    @MainActor
    @Test("3ω nil PNG guard sets only analysisMessage; persistenceOutcome and currentRunTrace unchanged")
    func threeOmegaPersistNilPNGIsContained() {
        let store = ThreeOmegaWorkspaceStore()
        store.currentRunTrace = sentinelTrace(runID: "sentinel-3w-png", workflowID: "3w")
        store.selectedSearchResultIDs = ["id-3w"]

        store.persistToLibrary()

        // Message field: 3ω uses analysisMessage (documents test-6 routing)
        #expect(store.analysisMessage == "No chart to save. Run analysis first.")
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-3w-png")
        #expect(store.ingestionResult == nil)
        #expect(store.selectedSearchResultIDs == ["id-3w"])
    }

    // MARK: - 3: Nil manifest guard — save fields contained

    @MainActor
    @Test("AHE nil manifest guard sets only plotMessage; all other state unchanged")
    func ahePersistNilManifestIsContained() {
        let store = AHEWorkspaceStore()
        // PNG present, manifest absent
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xFF, 0xD8]), layout: nil, manifestPayload: nil),
            for: .ahe
        )
        store.currentRunTrace = sentinelTrace(runID: "sentinel-ahe-mfst", workflowID: "ahe")
        store.selectedSearchResultIDs = ["id-ahe-mfst"]

        store.persistToLibrary()

        #expect(store.plotMessage == "No manifest payload available.")
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-ahe-mfst")
        #expect(store.ingestionResult == nil)
        #expect(store.selectedSearchResultIDs == ["id-ahe-mfst"])
    }

    @MainActor
    @Test("XY nil manifest guard sets only analysisMessage; all other state unchanged")
    func xyPersistNilManifestIsContained() {
        let store = XYRotationWorkspaceStore()
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xFF, 0xD8]), layout: nil, manifestPayload: nil),
            for: .rxxVsPhi
        )
        store.currentRunTrace = sentinelTrace(runID: "sentinel-xy-mfst", workflowID: "xy")
        store.selectedSearchResultIDs = ["id-xy-mfst"]

        store.persistToLibrary()

        #expect(store.analysisMessage == "No manifest payload available for the active tab.")
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-xy-mfst")
        #expect(store.ingestionResult == nil)
        #expect(store.selectedSearchResultIDs == ["id-xy-mfst"])
    }

    @MainActor
    @Test("3ω nil manifest guard sets only analysisMessage; all other state unchanged")
    func threeOmegaPersistNilManifestIsContained() {
        let store = ThreeOmegaWorkspaceStore()
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xFF, 0xD8]), layout: nil, manifestPayload: nil),
            for: .fieldSweep1omega
        )
        store.currentRunTrace = sentinelTrace(runID: "sentinel-3w-mfst", workflowID: "3w")
        store.selectedSearchResultIDs = ["id-3w-mfst"]

        store.persistToLibrary()

        #expect(store.analysisMessage == "No manifest payload available for the active tab.")
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-3w-mfst")
        #expect(store.ingestionResult == nil)
        #expect(store.selectedSearchResultIDs == ["id-3w-mfst"])
    }

    // MARK: - 4: Analysis output preserved after save failure (async UseCase path)

    @MainActor
    @Test("AHE: ingestionResult, chart output, and tab overrides survive a save failure")
    func aheAnalysisOutputPreservedAfterSaveFailure() async {
        let store = AHEWorkspaceStore()
        let hit = makeHit(
            id: "ahe-save-output",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe"
        )
        let wfs = makeWorkbenchStore()
        let snapshot = wfs.selectedHitsSnapshot(for: .ahe, selectedIDs: [hit.id], legacyHits: [hit])

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitForAHEAnalysis(store)

        let preIngestion = store.ingestionResult
        let preImageData = store.activeImageData
        // Place a tab override as a change-detection marker
        store.tabs.tabStates[.ahe] = TabRenderState(titleOverride: "save-boundary-ahe")

        guard preImageData != nil else {
            Issue.record("AHE analysis produced no chart output; cannot test save-path preservation")
            return
        }

        // persistToLibrary passes guards, spawns Task, UseCase fails (empty lastLibraryRootPath)
        store.persistToLibrary()
        await waitUntil(timeoutMS: 2000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        // Analysis output unchanged by save
        #expect(store.ingestionResult == preIngestion)
        #expect(store.activeImageData == preImageData)
        #expect(store.activeChartManifestPayload != nil)
        // Tab overrides survive
        #expect(store.tabs.state(for: .ahe).titleOverride == "save-boundary-ahe")
        // Save outcome reflects failure (not analysis)
        guard case .failure(_)? = store.persistenceOutcome else {
            Issue.record("Expected .failure persistenceOutcome; got \(String(describing: store.persistenceOutcome))")
            return
        }
    }

    @MainActor
    @Test("XY: ingestionResult, chart output, and tab overrides survive a save failure")
    func xyAnalysisOutputPreservedAfterSaveFailure() async {
        let store = XYRotationWorkspaceStore()
        let hit = makeHit(
            id: "xy-save-output",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xyRotation",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm"
        )
        let wfs = makeWorkbenchStore()
        let snapshot = wfs.selectedHitsSnapshot(
            for: .xyRotation,
            selectedIDs: [hit.id],
            legacyHits: [hit]
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitForXYAnalysis(store)

        let preIngestion = store.ingestionResult
        let preImageData = store.activeImageData
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(titleOverride: "save-boundary-xy")

        guard preImageData != nil else {
            Issue.record("XY analysis produced no chart output; cannot test save-path preservation")
            return
        }

        store.persistToLibrary()
        await waitUntil(timeoutMS: 2000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        #expect(store.ingestionResult == preIngestion)
        #expect(store.activeImageData == preImageData)
        #expect(store.activeChartManifestPayload != nil)
        #expect(store.tabs.state(for: .rxxVsPhi).titleOverride == "save-boundary-xy")
        guard case .failure(_)? = store.persistenceOutcome else {
            Issue.record("Expected .failure persistenceOutcome; got \(String(describing: store.persistenceOutcome))")
            return
        }
    }

    @MainActor
    @Test("3ω: ingestionResult, chart output, and tab overrides survive a save failure")
    func threeOmegaAnalysisOutputPreservedAfterSaveFailure() async {
        let store = ThreeOmegaWorkspaceStore()
        let hit = makeHit(
            id: "3w-save-output",
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: "threeOmega",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm"
        )
        let wfs = makeWorkbenchStore()
        let snapshot = wfs.selectedHitsSnapshot(
            for: .threeOmega,
            selectedIDs: [hit.id],
            legacyHits: [hit]
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitForThreeOmegaAnalysis(store)

        let preIngestion = store.ingestionResult
        let preImageData = store.activeImageData
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(titleOverride: "save-boundary-3w")

        guard preImageData != nil else {
            Issue.record("3ω analysis produced no chart output; cannot test save-path preservation")
            return
        }

        store.persistToLibrary()
        await waitUntil(timeoutMS: 2000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        #expect(store.ingestionResult == preIngestion)
        #expect(store.activeImageData == preImageData)
        #expect(store.activeChartManifestPayload != nil)
        #expect(store.tabs.state(for: .fieldSweep1omega).titleOverride == "save-boundary-3w")
        guard case .failure(_)? = store.persistenceOutcome else {
            Issue.record("Expected .failure persistenceOutcome; got \(String(describing: store.persistenceOutcome))")
            return
        }
    }

    // MARK: - 5: Save-side trace (source inspection)

    @Test("persistToLibrary sets currentRunTrace from outcome.trace in all workflows")
    func persistToLibrarySetsTraceFromOutcome() throws {
        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        #expect(ahePersist.contains("currentRunTrace = outcome.trace"))
        #expect(xyPersist.contains("currentRunTrace = outcome.trace"))
        #expect(threePersist.contains("currentRunTrace = outcome.trace"))
    }

    @Test("persistToLibrary never calls commitRunTrace() in any workflow")
    func persistToLibraryNeverCallsCommitRunTrace() throws {
        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        #expect(!ahePersist.contains("commitRunTrace()"))
        #expect(!xyPersist.contains("commitRunTrace()"))
        #expect(!threePersist.contains("commitRunTrace()"))
    }

    // MARK: - 6: Message field routing (source inspection, locks current behavior for 5E-3)

    @Test("AHE persistToLibrary uses plotMessage; XY and 3ω use analysisMessage")
    func messageFieldRoutingByWorkflow() throws {
        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        // AHE: plotMessage only (analysisMessage is a computed alias — not written directly)
        #expect(ahePersist.contains("plotMessage"))
        #expect(!ahePersist.contains("analysisMessage"))

        // XY and 3ω: analysisMessage (no plotMessage)
        #expect(xyPersist.contains("analysisMessage"))
        #expect(!xyPersist.contains("plotMessage"))
        #expect(threePersist.contains("analysisMessage"))
        #expect(!threePersist.contains("plotMessage"))
    }

    // MARK: - 7: Related charts refresh routing (source inspection, 5E-3 target for AHE alignment)

    @Test("XY and 3ω persistToLibrary call refreshRelatedCharts on success/partial; AHE does not (5E-3 target)")
    func relatedChartsRefreshRouting() throws {
        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        // XY and 3ω call refreshRelatedCharts after success or partial save
        #expect(xyPersist.contains("refreshRelatedCharts()"))
        #expect(threePersist.contains("refreshRelatedCharts()"))

        // AHE currently does not — intentional divergence locked here until 5E-3 alignment
        #expect(!ahePersist.contains("refreshRelatedCharts()"))
    }
}
