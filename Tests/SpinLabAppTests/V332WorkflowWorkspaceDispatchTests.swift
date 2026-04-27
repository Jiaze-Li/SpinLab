import Testing
@testable import SpinLabApp

/// V3.3.2 — Generic workspace dispatch via WorkflowWorkspaceRegistry.
///
/// Acceptance record: WorkbenchView delegates to registry; unknown IDs get fallback;
/// no AHE-specific symbols remain in WorkbenchView.swift.
@Suite("V3.3.2 Workflow Workspace Dispatch")
struct V332WorkflowWorkspaceDispatchTests {

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
}
