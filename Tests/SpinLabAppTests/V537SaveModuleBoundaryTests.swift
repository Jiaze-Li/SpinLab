import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.3.7 Save Module Boundary", .serialized)
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
        workflow: WorkflowKey
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

    private func waitForAHEAnalysis(_ store: AHEWorkspaceStore, timeoutMS: UInt64 = 60000) async {
        await waitUntil(timeoutMS: timeoutMS) {
            await MainActor.run { !store.isPlotRendering }
        }
    }

    private func waitForXYAnalysis(_ store: XYRotationWorkspaceStore, timeoutMS: UInt64 = 60000) async {
        await waitUntil(timeoutMS: timeoutMS) {
            await MainActor.run { !store.isAnalyzing }
        }
    }

    private func waitForThreeOmegaAnalysis(_ store: ThreeOmegaWorkspaceStore, timeoutMS: UInt64 = 60000) async {
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

        // No PNG available — synchronous early return; no Task created
        store.persistToLibrary()

        #expect(canonicalSearchState(wfs, workflow: .ahe) == before)
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

        store.persistToLibrary()

        #expect(canonicalSearchState(wfs, workflow: .xyRotation) == before)
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

        store.persistToLibrary()

        #expect(canonicalSearchState(wfs, workflow: .threeOmega) == before)
        #expect(store.cachedSearchResults == [hit])
    }

    // MARK: - 3: Nil PNG guard — save fields contained

    @MainActor
    @Test("AHE nil PNG guard sets only saveMessage; plotMessage and other state unchanged")
    func ahePersistNilPNGIsContained() {
        let store = AHEWorkspaceStore()
        store.currentRunTrace = sentinelTrace(runID: "sentinel-ahe-png", workflowID: "ahe")

        store.persistToLibrary()

        // Save guard writes to saveMessage; plotMessage (analysis field) is untouched
        #expect(store.saveMessage == "No chart to save. Render first.")
        #expect(store.plotMessage == nil)
        // Save-side fields unchanged
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-ahe-png")
        // Analysis output untouched
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("XY nil PNG guard sets only saveMessage; analysisMessage and other state unchanged")
    func xyPersistNilPNGIsContained() {
        let store = XYRotationWorkspaceStore()
        store.currentRunTrace = sentinelTrace(runID: "sentinel-xy-png", workflowID: "xy")

        store.persistToLibrary()

        // Save guard writes to saveMessage; analysisMessage (analysis field) is untouched
        #expect(store.saveMessage == "No chart to save. Run analysis first.")
        #expect(store.analysisMessage == nil)
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-xy-png")
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("3ω nil PNG guard sets only saveMessage; analysisMessage and other state unchanged")
    func threeOmegaPersistNilPNGIsContained() {
        let store = ThreeOmegaWorkspaceStore()
        store.currentRunTrace = sentinelTrace(runID: "sentinel-3w-png", workflowID: "3w")

        store.persistToLibrary()

        // Save guard writes to saveMessage; analysisMessage (analysis field) is untouched
        #expect(store.saveMessage == "No chart to save. Run analysis first.")
        #expect(store.analysisMessage == nil)
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-3w-png")
        #expect(store.ingestionResult == nil)
    }

    // MARK: - 3: Nil manifest guard — save fields contained

    @MainActor
    @Test("AHE nil manifest guard sets only saveMessage; plotMessage and other state unchanged")
    func ahePersistNilManifestIsContained() {
        let store = AHEWorkspaceStore()
        // PNG present, manifest absent
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xFF, 0xD8]), layout: nil, manifestPayload: nil),
            for: .ahe
        )
        store.currentRunTrace = sentinelTrace(runID: "sentinel-ahe-mfst", workflowID: "ahe")

        store.persistToLibrary()

        #expect(store.saveMessage == "No manifest payload available.")
        #expect(store.plotMessage == nil)
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-ahe-mfst")
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("XY nil manifest guard sets only saveMessage; analysisMessage and other state unchanged")
    func xyPersistNilManifestIsContained() {
        let store = XYRotationWorkspaceStore()
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xFF, 0xD8]), layout: nil, manifestPayload: nil),
            for: .rxxVsPhi
        )
        store.currentRunTrace = sentinelTrace(runID: "sentinel-xy-mfst", workflowID: "xy")

        store.persistToLibrary()

        #expect(store.saveMessage == "No manifest payload available for the active tab.")
        #expect(store.analysisMessage == nil)
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-xy-mfst")
        #expect(store.ingestionResult == nil)
    }

    @MainActor
    @Test("3ω nil manifest guard sets only saveMessage; analysisMessage and other state unchanged")
    func threeOmegaPersistNilManifestIsContained() {
        let store = ThreeOmegaWorkspaceStore()
        store.tabs.setOutput(
            TabRenderOutput(imageData: Data([0xFF, 0xD8]), layout: nil, manifestPayload: nil),
            for: .fieldSweep1omega
        )
        store.currentRunTrace = sentinelTrace(runID: "sentinel-3w-mfst", workflowID: "3w")

        store.persistToLibrary()

        #expect(store.saveMessage == "No manifest payload available for the active tab.")
        #expect(store.analysisMessage == nil)
        #expect(store.persistenceOutcome == nil)
        #expect(store.currentRunTrace?.runID == "sentinel-3w-mfst")
        #expect(store.ingestionResult == nil)
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
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .ahe,
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

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
        await waitUntil(timeoutMS: 60000) {
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
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .xyRotation,
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
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
        await waitUntil(timeoutMS: 60000) {
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
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .threeOmega,
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
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
        await waitUntil(timeoutMS: 60000) {
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

    @Test("save coordinator sets currentRunTrace from outcome.trace; workflow persistToLibrary delegates")
    func saveCoordinatorSetsTraceFromOutcome() throws {
        // After Gate 7.5B extraction: trace assignment lives in coordinator, not per-workflow
        let coordinator = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        #expect(coordinator.contains("currentRunTrace = outcome.trace"))

        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        // Each workflow delegates; does not set currentRunTrace directly
        #expect(!ahePersist.contains("currentRunTrace"))
        #expect(!xyPersist.contains("currentRunTrace"))
        #expect(!threePersist.contains("currentRunTrace"))
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

    // MARK: - 6: Message field routing (source inspection, Phase 5E-3 aligned)

    @Test("All workflows persistToLibrary write to saveMessage; not to analysisMessage or plotMessage")
    func messageFieldRoutingByWorkflow() throws {
        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        // All workflows: saveMessage receives save status
        #expect(ahePersist.contains("saveMessage"))
        #expect(xyPersist.contains("saveMessage"))
        #expect(threePersist.contains("saveMessage"))

        // No workflow writes save status to the analysis message fields
        #expect(!ahePersist.contains("plotMessage"))
        #expect(!xyPersist.contains("analysisMessage"))
        #expect(!threePersist.contains("analysisMessage"))
    }

    // MARK: - 7: Related charts refresh routing (source inspection, Phase 5E-3 aligned)

    @Test("coordinator calls refreshRelatedCharts on success/partial; workflow guard paths exit before coordinator")
    func relatedChartsRefreshRouting() throws {
        // After Gate 7.5B extraction: refreshRelatedCharts lives in coordinator, not per-workflow
        let coordinator = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        #expect(coordinator.contains("refreshRelatedCharts()"))

        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let threeOmega = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")

        let ahePersist = try #require(extractFunction("persistToLibrary", from: ahe))
        let xyPersist = try #require(extractFunction("persistToLibrary", from: xy))
        let threePersist = try #require(extractFunction("persistToLibrary", from: threeOmega))

        // Guard paths return before executeSave is reached — confirmed by guard presence
        #expect(ahePersist.contains("guard let png"))
        #expect(xyPersist.contains("guard let png"))
        #expect(threePersist.contains("guard let png"))

        // No workflow directly calls refreshRelatedCharts — coordinator-owned
        #expect(!ahePersist.contains("refreshRelatedCharts()"))
        #expect(!xyPersist.contains("refreshRelatedCharts()"))
        #expect(!threePersist.contains("refreshRelatedCharts()"))
    }

    // MARK: - 8: saveMessage separation from analysisMessage (Phase 5E-3)

    @MainActor
    @Test("XY save outcome goes to saveMessage; analysisMessage retains analysis summary")
    func xySaveMessageDoesNotClobberAnalysisMessage() async {
        let store = XYRotationWorkspaceStore()
        let hit = makeHit(
            id: "xy-save-msg-sep",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xyRotation",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm"
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .xyRotation,
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitForXYAnalysis(store)

        guard store.activeImageData != nil else {
            Issue.record("XY analysis produced no chart; cannot test saveMessage separation")
            return
        }

        let analysisMessageBeforeSave = store.analysisMessage

        store.persistToLibrary()
        await waitUntil(timeoutMS: 60000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        // saveMessage received the save outcome
        #expect(store.saveMessage != nil)
        // analysisMessage is unchanged from the analysis result
        #expect(store.analysisMessage == analysisMessageBeforeSave)
        // The two fields are separate
        #expect(store.saveMessage != store.analysisMessage)
    }

    @MainActor
    @Test("3ω save outcome goes to saveMessage; analysisMessage retains analysis summary")
    func threeOmegaSaveMessageDoesNotClobberAnalysisMessage() async {
        let store = ThreeOmegaWorkspaceStore()
        let hit = makeHit(
            id: "3w-save-msg-sep",
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: "threeOmega",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm"
        )
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .threeOmega,
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitForThreeOmegaAnalysis(store)

        guard store.activeImageData != nil else {
            Issue.record("3ω analysis produced no chart; cannot test saveMessage separation")
            return
        }

        let analysisMessageBeforeSave = store.analysisMessage

        store.persistToLibrary()
        await waitUntil(timeoutMS: 60000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        #expect(store.saveMessage != nil)
        #expect(store.analysisMessage == analysisMessageBeforeSave)
        #expect(store.saveMessage != store.analysisMessage)
    }

    // MARK: - 9: clearPlot clears saveMessage (Phase 5E-3)

    @MainActor
    @Test("clearPlot clears saveMessage for AHE")
    func clearPlotClearsSaveMessageAHE() {
        let store = AHEWorkspaceStore()
        // Guard path sets saveMessage
        store.persistToLibrary()
        #expect(store.saveMessage != nil)
        store.clearPlot()
        #expect(store.saveMessage == nil)
    }

    @MainActor
    @Test("clearPlot clears saveMessage for XY")
    func clearPlotClearsSaveMessageXY() {
        let store = XYRotationWorkspaceStore()
        store.persistToLibrary()
        #expect(store.saveMessage != nil)
        store.clearPlot()
        #expect(store.saveMessage == nil)
    }

    @MainActor
    @Test("clearPlot clears saveMessage for 3ω")
    func clearPlotClearsSaveMessageThreeOmega() {
        let store = ThreeOmegaWorkspaceStore()
        store.persistToLibrary()
        #expect(store.saveMessage != nil)
        store.clearPlot()
        #expect(store.saveMessage == nil)
    }

    // MARK: - 10: runAnalysis clears saveMessage (source inspection, Phase 5E-3)

    @Test("runAnalysis start path sets saveMessage = nil in all three workflows")
    func runAnalysisClearsSaveMessageSourceInspection() throws {
        let ahe = try loadSource(file: "AHEWorkspaceStore.swift")
        let xy = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let analysis3w = try loadSource(file: "ThreeOmegaWorkspaceStore+Analysis.swift")

        // saveMessage = nil appears in analysis start path of each workflow
        #expect(ahe.contains("saveMessage = nil"))
        #expect(xy.contains("saveMessage = nil"))
        #expect(analysis3w.contains("saveMessage = nil"))
    }
}
