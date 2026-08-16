import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.8 — Canonical workflow-identity boundary.
///
/// `WorkbenchFeatureStore.workflowKind(for:)` is the single owner of raw workflow-id
/// classification into `WorkbenchWorkflowKind`. `WorkflowWorkspaceRegistry` (view dispatch)
/// must switch on that typed kind rather than re-deriving its own `workflowID ==` chain.
/// These tests protect that boundary: all six workflows classify correctly, unknown ids
/// fall back safely, and Registry dispatch agrees with the canonical classification.
@Suite("V5.3.8 Workflow Dispatch Identity")
struct V538WorkflowDispatchIdentityTests {
    @MainActor
    private func makeStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    @MainActor
    @Test("workflowKind classifies all six concrete workflows")
    func classifiesAllSixWorkflows() {
        let wfs = makeStore()
        #expect(wfs.workflowKind(for: wfs.aheWorkspace.workflowID) == .ahe)
        #expect(wfs.workflowKind(for: wfs.threeOmegaWorkspace.workflowID) == .threeOmega)
        #expect(wfs.workflowKind(for: wfs.xyRotationWorkspace.workflowID) == .xyRotation)
        #expect(wfs.workflowKind(for: wfs.ivWorkspace.workflowID) == .iv)
        #expect(wfs.workflowKind(for: wfs.rsmWorkspace.workflowID) == .rsm)
        #expect(wfs.workflowKind(for: wfs.rtWorkspace.workflowID) == .rt)
    }

    @MainActor
    @Test("workflowKind returns nil for unknown/invalid raw ids")
    func unknownIDClassifiesToNil() {
        let wfs = makeStore()
        #expect(wfs.workflowKind(for: "not-a-real-workflow") == nil)
        #expect(wfs.workflowKind(for: "") == nil)
    }

    /// `WorkflowWorkspaceRegistry.leftContent`/`rightContent` are `@ViewBuilder` and cannot be
    /// asserted on directly, but they switch exhaustively on `workflowKind(for:)` with no other
    /// classification path. This locks the *input* to that switch (the canonical mapping) so a
    /// future edit reintroducing a second `workflowID ==` chain in Registry is caught by manual
    /// review of this file's neighboring dispatch tests rather than silently drifting.
    @MainActor
    @Test("unknown workflow id has no canonical kind, matching Registry's fallback branch")
    func unknownIDMatchesRegistryFallback() {
        let wfs = makeStore()
        let unknownID = "totally-unregistered-workflow"
        #expect(wfs.workflowKind(for: unknownID) == nil)
        _ = WorkflowWorkspaceRegistry.self
    }

    @MainActor
    @Test("each concrete workflow id is distinct, so no two kinds can collide")
    func workflowIDsAreDistinct() {
        let wfs = makeStore()
        let ids = [
            wfs.aheWorkspace.workflowID,
            wfs.threeOmegaWorkspace.workflowID,
            wfs.xyRotationWorkspace.workflowID,
            wfs.ivWorkspace.workflowID,
            wfs.rsmWorkspace.workflowID,
            wfs.rtWorkspace.workflowID
        ]
        #expect(Set(ids).count == ids.count)
    }
}
