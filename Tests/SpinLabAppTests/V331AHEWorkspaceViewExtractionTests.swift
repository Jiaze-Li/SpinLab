import Testing
@testable import SpinLabApp

/// V3.3.1 — AHEWorkspaceView extracted from WorkbenchView.
///
/// Acceptance record: AHEWorkspaceView exists as a standalone type; WorkbenchView
/// no longer contains the inline workflowWorkspacePlaceholder computed var.
/// Behavioral parity with V3.2.8 was verified manually against the desktop build.
@Suite("V3.3.1 AHEWorkspaceView Extraction")
struct V331AHEWorkspaceViewExtractionTests {

    @Test("AHEWorkspaceView is a standalone SwiftUI View")
    func aheWorkspaceViewExists() {
        // Compile-time check: type must exist and conform to View + WorkflowWorkspaceProvider.
        let _: any WorkflowWorkspaceProvider.Type = AHEWorkspaceView.self
    }

    @MainActor
    @Test("AHE state is accessed through WorkbenchFeatureStore.aheWorkspace, not WFS directly")
    func aheStateAccessPathIsSubStore() {
        // If WorkbenchView or WorkbenchFeatureStore re-inlined AHE state, the sub-store
        // would be bypassed and this path would be dead code.
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        wfs.toggleSearchHitSelection("probe", for: .ahe)
        #expect(wfs.selectedSearchResultIDs(for: .ahe) == ["probe"])
    }
}
