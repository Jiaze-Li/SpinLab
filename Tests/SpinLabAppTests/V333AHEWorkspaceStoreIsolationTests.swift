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
        #expect(store.currentPlotImageData == nil)
        #expect(store.isPlotRendering == false)
        #expect(store.plotMessage == nil)
        #expect(store.currentCandidateAxisFields.isEmpty)
        #expect(store.currentRunTrace == nil)
        #expect(store.isLoadingArtifact == false)
        #expect(store.artifactLoadMessage == nil)
        #expect(store.plotAxisXOverride == "")
        #expect(store.plotAxisYOverride == "")
        #expect(store.plotTitleOverride == "")
        #expect(store.showPlotGrid == false)
        #expect(store.plotLegendAnchor == "")
        #expect(store.plotLegendPoint == nil)
        #expect(store.plotSeriesLabelOverrides.isEmpty)
        #expect(store.plotXLabelOverride == "")
        #expect(store.plotYLabelOverride == "")
        #expect(store.currentPlotLayout == nil)
        #expect(store.lastLibraryRootPath == "")
        #expect(store.cachedSearchResults.isEmpty)
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
    @Test("clearPlot resets all plot state and clears selection")
    func clearPlotResetsState() {
        let store = AHEWorkspaceStore()

        // Seed some state
        store.toggleSearchHitSelection("id-1")
        store.plotAxisXOverride = "Temperature (K)"
        store.plotTitleOverride = "My Plot"
        store.showPlotGrid = true
        store.plotLegendAnchor = "top-left"
        store.plotSeriesLabelOverrides = [0: "Custom A"]
        store.plotXLabelOverride = "X"
        store.plotYLabelOverride = "Y"

        store.clearPlot()

        #expect(store.selectedSearchResultIDs.isEmpty)
        #expect(store.currentPlotImageData == nil)
        #expect(store.isPlotRendering == false)
        #expect(store.plotMessage == nil)
        #expect(store.currentCandidateAxisFields.isEmpty)
        #expect(store.currentRunTrace == nil)
        #expect(store.plotAxisXOverride == "")
        #expect(store.plotAxisYOverride == "")
        #expect(store.plotTitleOverride == "")
        #expect(store.showPlotGrid == false)
        #expect(store.plotLegendAnchor == "")
        #expect(store.plotLegendPoint == nil)
        #expect(store.plotSeriesLabelOverrides.isEmpty)
        #expect(store.plotXLabelOverride == "")
        #expect(store.plotYLabelOverride == "")
        #expect(store.currentPlotLayout == nil)
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
