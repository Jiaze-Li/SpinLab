import Foundation
import Testing
@testable import SpinLabApp

@Suite("Workbench Readiness Projection")
struct V538WorkbenchReadinessProjectionTests {
    @Test("Empty readiness when no workflow signals exist")
    func emptyWhenNoSignalsExist() {
        let projection = WorkbenchReadinessProjection(
            searchResultCount: 0,
            selectedCount: 0,
            isRunning: false,
            hasResultReady: false,
            hasSaved: false
        )

        #expect(projection.readiness == .empty)
        #expect(projection.hasFoundData == false)
        #expect(projection.hasSelectedData == false)
    }

    @Test("Found Data readiness when search results exist")
    func foundDataWhenSearchResultsExist() {
        let projection = WorkbenchReadinessProjection(
            searchResultCount: 4,
            selectedCount: 0,
            isRunning: false,
            hasResultReady: false,
            hasSaved: false
        )

        #expect(projection.readiness == .foundData)
        #expect(projection.hasFoundData)
    }

    @Test("Selected Data readiness when selected IDs exist")
    func selectedDataWhenSelectionsExist() {
        let projection = WorkbenchReadinessProjection(
            searchResultCount: 4,
            selectedCount: 2,
            isRunning: false,
            hasResultReady: false,
            hasSaved: false
        )

        #expect(projection.readiness == .selectedData)
        #expect(projection.hasSelectedData)
    }

    @Test("Running readiness overrides lower states")
    func runningOverridesOtherStates() {
        let projection = WorkbenchReadinessProjection(
            searchResultCount: 4,
            selectedCount: 2,
            isRunning: true,
            hasResultReady: true,
            hasSaved: true
        )

        #expect(projection.readiness == .running)
        #expect(projection.isRunning)
        #expect(projection.hasResultReady)
        #expect(projection.hasSaved)
    }

    @Test("Result Ready readiness when render output exists")
    func resultReadyWhenRenderOutputExists() {
        let projection = WorkbenchReadinessProjection(
            searchResultCount: 0,
            selectedCount: 0,
            isRunning: false,
            hasResultReady: true,
            hasSaved: false
        )

        #expect(projection.readiness == .resultReady)
        #expect(projection.hasResultReady)
    }

    @Test("Saved readiness when persistence outcome exists")
    func savedWhenPersistenceOutcomeExists() {
        let projection = WorkbenchReadinessProjection(
            searchResultCount: 0,
            selectedCount: 0,
            isRunning: false,
            hasResultReady: false,
            hasSaved: true
        )

        #expect(projection.readiness == .saved)
        #expect(projection.hasSaved)
    }

    @Test("Readiness is derived from inputs and not stored state")
    func readinessIsDerivedFromInputs() {
        var inputs = (
            searchResultCount: 0,
            selectedCount: 0,
            isRunning: false,
            hasResultReady: false,
            hasSaved: false
        )

        let initial = WorkbenchReadinessProjection(
            searchResultCount: inputs.searchResultCount,
            selectedCount: inputs.selectedCount,
            isRunning: inputs.isRunning,
            hasResultReady: inputs.hasResultReady,
            hasSaved: inputs.hasSaved
        )

        inputs.searchResultCount = 3
        inputs.selectedCount = 1
        inputs.hasResultReady = true
        let updated = WorkbenchReadinessProjection(
            searchResultCount: inputs.searchResultCount,
            selectedCount: inputs.selectedCount,
            isRunning: inputs.isRunning,
            hasResultReady: inputs.hasResultReady,
            hasSaved: inputs.hasSaved
        )

        #expect(initial.readiness == .empty)
        #expect(updated.readiness == .resultReady)
        #expect(initial != updated)
    }
}
