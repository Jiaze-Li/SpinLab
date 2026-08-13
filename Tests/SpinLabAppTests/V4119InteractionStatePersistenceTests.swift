import Foundation
import Testing
@testable import SpinLabApp

@Suite("v4.1.19 Interaction State Persistence")
struct V4119InteractionStatePersistenceTests {

    // MARK: - InboxInteractionState backward compatibility

    @Test("InboxInteractionState decodes without fileFilter (old snapshot)")
    func inboxStateDecodesWithoutFileFilter() throws {
        let json = """
        {
            "isPendingQueueExpanded": false
        }
        """
        let data = Data(json.utf8)
        let state = try JSONDecoder().decode(InboxInteractionState.self, from: data)
        #expect(state.isPendingQueueExpanded == false)
        #expect(state.fileFilter == nil)
    }

    @Test("InboxInteractionState decodes legacy snapshot with now-removed expansion flags")
    func inboxStateDecodesLegacySnapshotWithRemovedFlags() throws {
        let json = """
        {
            "isImportSourceExpanded": true,
            "isPendingQueueExpanded": false,
            "isRoutingReviewExpanded": true,
            "isApplyExpanded": false
        }
        """
        let data = Data(json.utf8)
        let state = try JSONDecoder().decode(InboxInteractionState.self, from: data)
        #expect(state.isPendingQueueExpanded == false)
    }

    @Test("InboxInteractionState round-trips fileFilter")
    func inboxStateRoundTripsFileFilter() throws {
        let state = InboxInteractionState(
            isPendingQueueExpanded: true,
            fileFilter: "Library Matched"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(InboxInteractionState.self, from: data)
        #expect(decoded.fileFilter == "Library Matched")
    }

    // MARK: - LibraryInteractionState backward compatibility

    @Test("LibraryInteractionState decodes without expansion Sets (old snapshot)")
    func libraryStateDecodesWithoutExpansionSets() throws {
        let json = """
        {
            "isLibrarySettingsExpanded": true,
            "isRegistryWorkspaceExpanded": true,
            "isSearchWorkspaceExpanded": false,
            "isMetadataSectionExpanded": true,
            "searchBatchIdText": "",
            "searchSubstrateText": "",
            "searchKeywordText": "",
            "searchThicknessText": "",
            "searchOxygenText": "",
            "searchTemperatureText": "",
            "searchEnergyText": "",
            "searchThicknessToleranceText": "",
            "searchOxygenToleranceText": "",
            "searchTemperatureToleranceText": "",
            "searchEnergyToleranceText": "",
            "searchHasExecuted": false
        }
        """
        let data = Data(json.utf8)
        let state = try JSONDecoder().decode(LibraryInteractionState.self, from: data)
        #expect(state.isSearchWorkspaceExpanded == false)
        #expect(state.expandedWorkflowIDs == nil)
        #expect(state.expandedSetIDs == nil)
        #expect(state.expandedUncategorizedIDs == nil)
    }

    @Test("LibraryInteractionState round-trips expansion Sets")
    func libraryStateRoundTripsExpansionSets() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let decoder = JSONDecoder()

        let state = LibraryInteractionState(
            expandedWorkflowIDs: ["3w", "ahe"],
            expandedSetIDs: ["set1"],
            expandedUncategorizedIDs: ["unc1"]
        )
        let data = try encoder.encode(state)
        let decoded = try decoder.decode(LibraryInteractionState.self, from: data)
        #expect(decoded.expandedWorkflowIDs == Set(["3w", "ahe"]))
        #expect(decoded.expandedSetIDs == Set(["set1"]))
        #expect(decoded.expandedUncategorizedIDs == Set(["unc1"]))
    }

    @Test("LibraryInteractionState nil Sets are not encoded")
    func libraryStateNilSetsNotEncoded() throws {
        let state = LibraryInteractionState()
        let data = try JSONEncoder().encode(state)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("expandedWorkflowIDs"))
        #expect(!json.contains("expandedSetIDs"))
        #expect(!json.contains("expandedUncategorizedIDs"))
    }
}
