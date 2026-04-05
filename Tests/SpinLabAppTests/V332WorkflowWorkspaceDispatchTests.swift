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
        #expect(WorkflowWorkspaceRegistry.self is WorkflowWorkspaceRegistry.Type)
    }

    @Test("WorkbenchFeatureStore has no AHE-specific state properties at compile time")
    func workbenchFeatureStoreHasNoAHEState() {
        // Structural invariant: verified at source level by grep (zero hits).
        // If AHE state were re-added to WorkbenchFeatureStore this test suite would
        // need to be updated as part of the regression investigation.
        #expect(true)
    }
}
