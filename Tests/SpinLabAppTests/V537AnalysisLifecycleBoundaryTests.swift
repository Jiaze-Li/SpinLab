import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.3.7 Analysis Lifecycle Boundary", .serialized)
struct V537AnalysisLifecycleBoundaryTests {

    // MARK: - Fixtures

    private struct CanonicalSearchState: Equatable {
        var query: String
        var results: [WorkflowMeasurementSearchHit]
        var message: String?
        var running: Bool
    }

    private func makeHit(
        id: String,
        workflowID: String,
        workflowDisplayName: String,
        workflowCanonicalID: String,
        sampleKey: String = "PN31|b|STO|111",
        measurementFilePath: String? = nil,
        sourceFilePath: String? = nil
    ) -> WorkflowMeasurementSearchHit {
        let resolvedMeasurementPath = measurementFilePath ?? "/tmp/\(id).dat"
        let resolvedSourcePath = sourceFilePath ?? resolvedMeasurementPath
        return WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: resolvedMeasurementPath,
            sourceFilePath: resolvedSourcePath,
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
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
    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    @MainActor
    private func seedCanonicalSearch(
        _ wfs: WorkbenchFeatureStore,
        workflow: WorkflowKey,
        query: String,
        results: [WorkflowMeasurementSearchHit],
        message: String,
        running: Bool
    ) {
        wfs.restoreSearchState(results: results, queryText: query, for: workflow)
        wfs.searchMessages[workflow] = message
        _ = running
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

    private func makeSelectedHitsSnapshot(
        workflow: WorkflowKey,
        queryText: String,
        selectedHits: [WorkflowMeasurementSearchHit]
    ) -> WorkbenchSelectedHitsSnapshot {
        WorkbenchSelectedHitsSnapshot(
            workflowID: workflow,
            queryText: queryText,
            selectedIDs: Set(selectedHits.map(\.id)),
            selectedHits: selectedHits,
            sourceHitCount: selectedHits.count,
            selectionSource: .canonicalSnapshot
        )
    }

    private func makeSeedPlotPayload(
        workflowID: String,
        workflowDisplayName: String,
        title: String
    ) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(
                    label: "seed",
                    x: [0],
                    y: [0],
                    sampleID: "seed"
                )
            ],
            semanticParams: ["state": "seeded"]
        )
    }

    private func makeSeedTrace(runID: String, workflowID: String) -> WorkbenchRunTraceProjection {
        WorkbenchRunTraceProjection(
            runID: runID,
            workflowID: workflowID,
            inputFiles: ["/tmp/seed.dat"],
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            semanticParams: ["state": "seeded"],
            outputImagePath: "/tmp/seed.png",
            manifestPath: "/tmp/seed.json",
            generatedAt: .distantPast
        )
    }

    @MainActor
    private func seedAnalysisOutput(
        _ store: XYRotationWorkspaceStore,
        payload: WorkbenchPlotPayload,
        trace: WorkbenchRunTraceProjection,
        analysisMessage: String
    ) {
        store.tabs.setOutput(
            TabRenderOutput(
                imageData: Data([0x01]),
                layout: nil,
                manifestPayload: payload
            ),
            for: store.tabs.activeTab
        )
        store.currentRunTrace = trace
        store.analysisMessage = analysisMessage
        store.warningLog.append(source: "Test", message: "seed warning")
    }

    @MainActor
    private func seedAnalysisOutput(
        _ store: ThreeOmegaWorkspaceStore,
        payload: WorkbenchPlotPayload,
        trace: WorkbenchRunTraceProjection,
        analysisMessage: String
    ) {
        store.tabs.setOutput(
            TabRenderOutput(
                imageData: Data([0x01]),
                layout: nil,
                manifestPayload: payload
            ),
            for: store.tabs.activeTab
        )
        store.currentRunTrace = trace
        store.analysisMessage = analysisMessage
        store.warningLog.append(source: "Test", message: "seed warning")
    }

    private func waitForAHEAnalysis(_ store: AHEWorkspaceStore, timeoutMS: UInt64 = 30000) async {
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

    private func waitUntil(
        timeoutMS: UInt64,
        predicate: @escaping @Sendable () async -> Bool
    ) async {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await predicate() {
                return
            }
            try? await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for analysis to complete.")
    }

    // MARK: - AHE

    @MainActor
    @Test("AHE runAnalysis(selectedHitsSnapshot:) preserves canonical search and produces output")
    func aheRunAnalysisPreservesSearchAndProducesOutput() async {
        let wfs = makeWorkbenchStore()
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let hit = makeHit(
            id: "ahe-hit",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe"
        )

        seedCanonicalSearch(
            wfs,
            workflow: .ahe,
            query: "ahe pn31 80k",
            results: [hit],
            message: "Searching AHE",
            running: false
        )
        let before = canonicalSearchState(wfs, workflow: .ahe)

        let snapshot = makeSelectedHitsSnapshot(workflow: .ahe, queryText: "ahe pn31 80k", selectedHits: [hit])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        await waitForAHEAnalysis(store)

        let after = canonicalSearchState(wfs, workflow: .ahe)
        #expect(after == before)
        #expect(store.isPlotRendering == false)
        #expect(store.activeImageData != nil)
        #expect(store.activeChartManifestPayload != nil)
        #expect(store.currentRunTrace != nil)
        #expect(store.plotMessage == "Rendered 1 series.")
    }

    @MainActor
    @Test("AHE clearResults and clearPlot stay inside their current boundaries")
    func aheClearBoundaries() async {
        let wfs = makeWorkbenchStore()
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let hit = makeHit(
            id: "ahe-clear",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe"
        )

        seedCanonicalSearch(
            wfs,
            workflow: .ahe,
            query: "ahe pn31",
            results: [hit],
            message: "Searching AHE",
            running: false
        )
        store.cachedSearchResults = [hit]
        let snapshot = makeSelectedHitsSnapshot(workflow: .ahe, queryText: "ahe pn31", selectedHits: [hit])
        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitForAHEAnalysis(store)

        store.clearPlot()
        #expect(store.activeImageData == nil)
        #expect(store.activeChartManifestPayload == nil)
        #expect(store.currentRunTrace == nil)
        #expect(store.warningLog.isEmpty)
        #expect(store.plotMessage == nil)

        store.cachedSearchResults = [hit]
        store.clearResults()
        #expect(store.cachedSearchResults.isEmpty)
        #expect(wfs.searchResultsList(for: .ahe) == [hit])
    }

    // MARK: - XY Rotation

    @MainActor
    @Test("XY runAnalysis(selectedHitsSnapshot:) preserves canonical search and produces output")
    func xyRunAnalysisPreservesSearchAndProducesOutput() async {
        let wfs = makeWorkbenchStore()
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let hit = makeHit(
            id: "xy-hit",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xyRotation",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm"
        )

        seedCanonicalSearch(
            wfs,
            workflow: .xyRotation,
            query: "xy pn31 80k",
            results: [hit],
            message: "Searching XY",
            running: false
        )
        let before = canonicalSearchState(wfs, workflow: .xyRotation)

        let snapshot = makeSelectedHitsSnapshot(workflow: .xyRotation, queryText: "xy pn31 80k", selectedHits: [hit])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        await waitForXYAnalysis(store)

        let after = canonicalSearchState(wfs, workflow: .xyRotation)
        #expect(after == before)
        #expect(store.isAnalyzing == false)
        #expect(store.activeImageData != nil)
        #expect(store.activeChartManifestPayload != nil)
        #expect(store.currentRunTrace != nil)
        #expect(store.analysisMessage == "Analyzed 1 angle-sweep file(s).")
    }

    @MainActor
    @Test("XY clearResults and clearPlot stay inside their current boundaries")
    func xyClearBoundaries() async {
        let wfs = makeWorkbenchStore()
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let hit = makeHit(
            id: "xy-clear",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xyRotation",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/XYRotation/xy_rotation_80K_sample.lvm"
        )

        seedCanonicalSearch(
            wfs,
            workflow: .xyRotation,
            query: "xy pn31",
            results: [hit],
            message: "Searching XY",
            running: false
        )
        let canonicalBefore = canonicalSearchState(wfs, workflow: .xyRotation)
        store.cachedSearchResults = [hit]
        seedAnalysisOutput(
            store,
            payload: makeSeedPlotPayload(
                workflowID: "xyRotation",
                workflowDisplayName: "XY Rotation",
                title: "Seeded XY"
            ),
            trace: makeSeedTrace(runID: "xy-clear-trace", workflowID: "xyRotation"),
            analysisMessage: "Analyzed 1 angle-sweep file(s)."
        )

        store.clearPlot()
        #expect(store.activeImageData == nil)
        #expect(store.activeChartManifestPayload == nil)
        #expect(store.currentRunTrace == nil)
        #expect(store.warningLog.isEmpty)
        #expect(store.analysisMessage == nil)
        #expect(canonicalSearchState(wfs, workflow: .xyRotation) == canonicalBefore)

        store.cachedSearchResults = [hit]
        store.clearResults()
        #expect(store.cachedSearchResults.isEmpty)
        #expect(canonicalSearchState(wfs, workflow: .xyRotation) == canonicalBefore)
    }

    // MARK: - 3ω

    @MainActor
    @Test("3ω runAnalysis(selectedHitsSnapshot:) preserves canonical search and produces output")
    func threeOmegaRunAnalysisPreservesSearchAndProducesOutput() async {
        let wfs = makeWorkbenchStore()
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let hit = makeHit(
            id: "3w-hit",
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: "threeOmega",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm"
        )

        seedCanonicalSearch(
            wfs,
            workflow: .threeOmega,
            query: "3w pn31 80k",
            results: [hit],
            message: "Searching 3w",
            running: false
        )
        let before = canonicalSearchState(wfs, workflow: .threeOmega)

        let snapshot = makeSelectedHitsSnapshot(workflow: .threeOmega, queryText: "3w pn31 80k", selectedHits: [hit])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        await waitForThreeOmegaAnalysis(store)

        let after = canonicalSearchState(wfs, workflow: .threeOmega)
        #expect(after == before)
        #expect(store.isAnalyzing == false)
        #expect(store.activeImageData != nil)
        #expect(store.activeChartManifestPayload != nil)
        #expect(store.currentRunTrace != nil)
        #expect(store.analysisMessage == "Analyzed 1 field-sweep file(s).")
    }

    @MainActor
    @Test("3ω clearResults and clearPlot stay inside their current boundaries")
    func threeOmegaClearBoundaries() async {
        let wfs = makeWorkbenchStore()
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let hit = makeHit(
            id: "3w-clear",
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: "threeOmega",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/3w_0deg_T_4.999 K_Iac_0.001000 A.lvm"
        )
        let rtHit = makeHit(
            id: "3w-rt",
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: "threeOmega",
            measurementFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/RT_0deg_H_-0.029814 Oe_Iac_0.000200 A.lvm",
            sourceFilePath: "Tests/SpinLabAppTests/TestData/ThreeOmega/RT_0deg_H_-0.029814 Oe_Iac_0.000200 A.lvm"
        )

        seedCanonicalSearch(
            wfs,
            workflow: .threeOmega,
            query: "3w pn31",
            results: [hit],
            message: "Searching 3w",
            running: false
        )
        let canonicalBefore = canonicalSearchState(wfs, workflow: .threeOmega)
        store.cachedSearchResults = [hit]
        store.rtQuery = "rt pn31"
        store.rtSearchResults = [rtHit]
        store.rtSearchMessage = "RT search message"
        store.isRTSearching = true
        store.showRTPopover = true
        store.selectedRTHit = rtHit
        seedAnalysisOutput(
            store,
            payload: makeSeedPlotPayload(
                workflowID: "threeOmega",
                workflowDisplayName: "3w",
                title: "Seeded 3ω"
            ),
            trace: makeSeedTrace(runID: "3w-clear-trace", workflowID: "threeOmega"),
            analysisMessage: "Analyzed 1 field-sweep file(s)."
        )

        let rtQueryBeforeClearPlot = store.rtQuery
        let rtResultsBeforeClearPlot = store.rtSearchResults
        let rtMessageBeforeClearPlot = store.rtSearchMessage
        let rtSearchingBeforeClearPlot = store.isRTSearching
        let rtPopoverBeforeClearPlot = store.showRTPopover
        let rtSelectedBeforeClearPlot = store.selectedRTHit

        store.clearPlot()
        #expect(store.activeImageData == nil)
        #expect(store.activeChartManifestPayload == nil)
        #expect(store.currentRunTrace == nil)
        #expect(store.warningLog.isEmpty)
        #expect(store.analysisMessage == nil)
        #expect(store.rtQuery == rtQueryBeforeClearPlot)
        #expect(store.rtSearchResults == rtResultsBeforeClearPlot)
        #expect(store.rtSearchMessage == rtMessageBeforeClearPlot)
        #expect(store.isRTSearching == rtSearchingBeforeClearPlot)
        #expect(store.showRTPopover == rtPopoverBeforeClearPlot)
        #expect(store.selectedRTHit?.id == rtSelectedBeforeClearPlot?.id)
        #expect(canonicalSearchState(wfs, workflow: .threeOmega) == canonicalBefore)

        store.cachedSearchResults = [hit]
        store.rtQuery = "rt pn31"
        store.rtSearchResults = [rtHit]
        store.rtSearchMessage = "RT search message"
        store.isRTSearching = true
        store.showRTPopover = true
        store.selectedRTHit = rtHit

        store.clearResults()
        #expect(store.cachedSearchResults.isEmpty)
        #expect(store.cachedSampleNumericDisplay.isEmpty)
        #expect(store.rtQuery.isEmpty)
        #expect(store.rtSearchResults.isEmpty)
        #expect(store.rtSearchMessage == nil)
        #expect(store.isRTSearching == false)
        #expect(store.showRTPopover == false)
        #expect(store.selectedRTHit == nil)
        #expect(canonicalSearchState(wfs, workflow: .threeOmega) == canonicalBefore)
    }

    // MARK: - Trace and warning boundaries

    @MainActor
    @Test("3ω guard failure does not replace the current run trace")
    func threeOmegaGuardFailureDoesNotCommitTrace() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sentinel = WorkbenchRunTraceProjection(
            runID: "sentinel",
            workflowID: "3w",
            inputFiles: [],
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            semanticParams: ["state": "sentinel"],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: .distantPast
        )
        store.currentRunTrace = sentinel

        let emptySnapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .threeOmega,
            queryText: "3w pn31",
            selectedIDs: [],
            selectedHits: [],
            sourceHitCount: 0,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: emptySnapshot)

        #expect(store.isAnalyzing == false)
        #expect(store.analysisMessage == "Select at least one 3w measurement file.")
        #expect(store.currentRunTrace?.runID == sentinel.runID)
    }

    @MainActor
    @Test("Workbench warning log coalesces duplicates and clearPlot clears warnings")
    func warningsCoalesceAndClear() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)

        store.appendWarning(source: "Analysis", message: "duplicate warning")
        store.appendWarning(source: "Analysis", message: "duplicate warning")
        #expect(store.warningLog.count == 1)

        store.warningLog.append(source: "Other", message: "second warning")
        #expect(store.warningLog.count == 2)

        store.clearPlot()
        #expect(store.warningLog.isEmpty)
    }
}
