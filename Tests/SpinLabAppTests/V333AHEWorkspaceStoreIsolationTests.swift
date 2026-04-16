import CoreGraphics
import Testing
@testable import SpinLabApp

/// V3.3.3 — AHE state fully isolated into AHEWorkspaceStore.
///
/// Acceptance record: AHEWorkspaceStore owns all AHE-specific state and actions;
/// WorkbenchFeatureStore contains zero AHE-specific symbols (verified by grep DoD).
@Suite("V3.3.3 AHEWorkspaceStore Isolation")
struct V333AHEWorkspaceStoreIsolationTests {

    @MainActor
    @Test("AHEWorkspaceStore initialises with correct zero state")
    func initialStateIsZero() {
        let store = AHEWorkspaceStore()

        #expect(store.selectedSearchResultIDs.isEmpty)
        #expect(store.tabs.activeImageData == nil)
        #expect(store.isPlotRendering == false)
        #expect(store.plotMessage == nil)
        #expect(store.currentCandidateAxisFields.isEmpty)
        #expect(store.currentRunTrace == nil)
        #expect(store.plotAxisXOverride == "")
        #expect(store.plotAxisYOverride == "")
        #expect(store.tabs.activeState.titleOverride == "")
        #expect(store.tabs.showPlotGrid == false)
        #expect(store.tabs.legendAnchor == "")
        #expect(store.tabs.activeState.legendPoint == nil)
        #expect(store.tabs.activeSeriesLabelOverrides.isEmpty)
        #expect(store.tabs.activeState.xLabelOverride == "")
        #expect(store.tabs.activeState.yLabelOverride == "")
        #expect(store.tabs.activeLayout == nil)
        #expect(store.lastLibraryRootPath == "")
        #expect(store.cachedSearchResults.isEmpty)
        #expect(store.lastExtractedMetrics.isEmpty)
        #expect(store.lastExtractedHc == nil)
        #expect(store.lastExtractedRAHE == nil)
    }

    @MainActor
    @Test("toggleSearchHitSelection adds and removes IDs correctly")
    func toggleSelectionRoundTrips() {
        let store = AHEWorkspaceStore()

        store.toggleSearchHitSelection("id-1")
        #expect(store.selectedSearchResultIDs == ["id-1"])

        store.toggleSearchHitSelection("id-2")
        #expect(store.selectedSearchResultIDs == ["id-1", "id-2"])

        store.toggleSearchHitSelection("id-1")
        #expect(store.selectedSearchResultIDs == ["id-2"])
    }

    @MainActor
    @Test("clearPlot resets plot state; selection and manager-level settings preserved")
    func clearPlotResetsState() {
        let store = AHEWorkspaceStore()

        // Seed some state
        store.toggleSearchHitSelection("id-1")
        store.plotAxisXOverride = "Temperature (K)"
        store.tabs.updateTitleOverride("My Plot")
        store.tabs.showPlotGrid = true
        store.tabs.legendAnchor = "top-left"
        store.tabs.tabStates[.ahe, default: TabRenderState()].seriesLabelOverrides = [0: "Custom A"]
        store.tabs.updateXLabelOverride("X")
        store.tabs.updateYLabelOverride("Y")

        store.clearPlot()

        // clearPlot resets per-tab render state and plot artifacts
        #expect(store.tabs.activeImageData == nil)
        #expect(store.isPlotRendering == false)
        #expect(store.plotMessage == nil)
        #expect(store.currentCandidateAxisFields.isEmpty)
        #expect(store.currentRunTrace == nil)
        #expect(store.plotAxisXOverride == "")
        #expect(store.plotAxisYOverride == "")
        #expect(store.tabs.activeState.titleOverride == "")
        #expect(store.tabs.activeState.legendPoint == nil)
        #expect(store.tabs.activeSeriesLabelOverrides.isEmpty)
        #expect(store.tabs.activeState.xLabelOverride == "")
        #expect(store.tabs.activeState.yLabelOverride == "")
        #expect(store.tabs.activeLayout == nil)

        // selection is NOT cleared by clearPlot (clearResults handles that)
        #expect(!store.selectedSearchResultIDs.isEmpty)
        // manager-level settings (grid, legendAnchor) persist across clear
        #expect(store.tabs.showPlotGrid == true)
        #expect(store.tabs.legendAnchor == "top-left")
    }

    @MainActor
    @Test("WorkbenchFeatureStore exposes aheWorkspace property")
    func workbenchFeatureStoreExposesAHEWorkspace() throws {
        // Structural check: if aheWorkspace were removed from WFS, this would not compile.
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let repository = LibraryRepository(persistence: persistence)
        let store = WorkbenchFeatureStore(
            libraryRepository: repository,
            workflowRegistryStore: WorkflowRegistryStore()
        )
        let _: AHEWorkspaceStore = store.aheWorkspace
    }
}
