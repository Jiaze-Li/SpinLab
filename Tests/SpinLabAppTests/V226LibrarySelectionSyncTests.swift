import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.6 Library Selection Sync")
struct V226LibrarySelectionSyncTests {
    @Test("drawer sync keeps valid existing selection even when preview is unrelated")
    func drawerSyncKeepsExistingSelection() {
        let existingGroups = [
            "PN20": [
                LibraryPreviewBatchGroup(
                    batchId: "PN20-A",
                    samples: [sample(id: "PN20|o|STO|111", batchId: "PN20-A")]
                )
            ]
        ]
        let output = LibrarySelectionSync.syncDrawerSelection(
            input: .init(
                selectedPrefix: "PN20",
                selectedBatchId: "PN20-A",
                selectedSampleId: "PN20|o|STO|111"
            ),
            existingGroupsByPrefix: existingGroups
        )

        #expect(output.selectedPrefix == "PN20")
        #expect(output.selectedBatchId == "PN20-A")
        #expect(output.selectedSampleId == "PN20|o|STO|111")
    }

    @Test("drawer sync clears selection when no existing groups remain")
    func drawerSyncClearsSelectionWhenEmpty() {
        let output = LibrarySelectionSync.syncDrawerSelection(
            input: .init(
                selectedPrefix: "PN20",
                selectedBatchId: "PN20-A",
                selectedSampleId: "PN20|o|STO|111"
            ),
            existingGroupsByPrefix: [:]
        )

        #expect(output.selectedPrefix == nil)
        #expect(output.selectedBatchId == nil)
        #expect(output.selectedSampleId == nil)
    }

    private func sample(id: String, batchId: String) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: id,
            batchId: batchId,
            substrateRaw: "STO(111)",
            substrateDisplay: "STO(111)",
            substrateTokens: ["STO", "111"],
            substrateTags: ["STO111"],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: .now
        )
    }
}
