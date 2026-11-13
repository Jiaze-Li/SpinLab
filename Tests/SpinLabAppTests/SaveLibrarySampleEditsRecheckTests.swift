import Foundation
import Testing
@testable import SpinLabApp

@Suite("Save sample edits re-checks the version before writing")
struct SaveLibrarySampleEditsRecheckTests {
    private let baseDate = Date(timeIntervalSince1970: 1_000_000)

    private func sample(updatedAt: Date) -> LibrarySample {
        LibrarySample(
            id: "S1", displayName: "S1", batchId: "B1", substrateRaw: "STO", substrateDisplay: "STO",
            substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [],
            numericTags: [:], numericDisplay: [:], updatedAt: updatedAt
        )
    }

    private func index(_ sample: LibrarySample?) -> LibraryIndex {
        LibraryIndex(
            createdAt: baseDate, updatedAt: baseDate, registryInternalPath: nil, registrySourcePath: nil,
            batches: [], samples: sample.map { [$0] } ?? []
        )
    }

    private func run(secondSnapshot: LibrarySample?) -> (result: Result<SaveLibrarySampleEditsUseCase.Output, AppError>, writes: Int) {
        let first = sample(updatedAt: baseDate)
        let draft = LibrarySampleEditDraft(
            sampleId: "S1", batchId: "B1", baseUpdatedAt: baseDate, substrateTagsText: "",
            numericValues: [], metadataValues: []
        )
        var snapshots = 0
        var writes = 0
        let result = SaveLibrarySampleEditsUseCase().execute(
            input: .init(rootPath: "/tmp/spinlab-recheck", draft: draft, baseSample: first),
            snapshotIndexFromFilesystem: { _ in
                snapshots += 1
                return snapshots == 1 ? self.index(first) : self.index(secondSnapshot)
            },
            applyDraft: { _, current in current },
            updateSample: { _, _ in writes += 1 },
            resolveRegistrySourceURL: { nil },
            syncRegistrySource: { _, _, _ in
                LibraryRegistrySourceSyncResult(
                    metadataWrittenCount: 0, metadataFailedCount: 0, manualLoggedCount: 0,
                    metadataLogSheetName: "", manualLogSheetName: "")
            }
        )
        return (result, writes)
    }

    @Test("A change that lands between the first snapshot and the write is not overwritten")
    func changedBeforeWriteIsRejected() {
        let outcome = run(secondSnapshot: sample(updatedAt: baseDate.addingTimeInterval(60)))
        guard case .failure = outcome.result else {
            Issue.record("Expected a failure when the sample changed before the write")
            return
        }
        #expect(outcome.writes == 0)
    }

    @Test("A sample removed before the write is not recreated")
    func removedBeforeWriteIsRejected() {
        let outcome = run(secondSnapshot: nil)
        guard case .failure = outcome.result else {
            Issue.record("Expected a failure when the sample disappeared before the write")
            return
        }
        #expect(outcome.writes == 0)
    }

    @Test("An unchanged sample is written exactly once")
    func unchangedIsWritten() {
        let outcome = run(secondSnapshot: sample(updatedAt: baseDate))
        guard case .success = outcome.result else {
            Issue.record("Expected success when nothing changed")
            return
        }
        #expect(outcome.writes == 1)
    }
}
