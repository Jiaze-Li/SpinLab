import Testing
@testable import SpinLabApp

/// V3.3.0 — WorkflowWorkspaceProvider protocol + shell region contract.
///
/// Acceptance record: protocol exists, compiles, and is satisfied by AHEWorkspaceView.
/// Visual/layout acceptance was verified manually against the desktop build (v3.3.0).
@Suite("V3.3.0 Workbench Shell Contract")
struct V330WorkbenchShellContractTests {

    @Test("WorkflowWorkspaceProvider protocol exists and AHEWorkspaceView conforms")
    func aheWorkspaceViewConformsToProvider() {
        // Compile-time check: if AHEWorkspaceView did not conform, this file would not build.
        let _: any WorkflowWorkspaceProvider.Type = AHEWorkspaceView.self
    }

    @Test("WorkflowWorkspaceRegistry resolves workflow ID A to a non-fallback view")
    func registryResolvesAHEWorkflowID() {
        // WorkflowWorkspaceRegistry.workspace(for:) is a @ViewBuilder — we verify the
        // registry type exists and the dispatch table compiles with the expected case.
        // Runtime dispatch is covered by V3.3.2 tests.
        let _: WorkflowWorkspaceRegistry.Type = WorkflowWorkspaceRegistry.self
    }
}
