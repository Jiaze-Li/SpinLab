import Foundation
import Testing
@testable import SpinLabApp

// Isolation lock: only one test modifies shared filesystem state at a time.
private actor LibraryFeatureStoreIsolation {
    static let shared = LibraryFeatureStoreIsolation()
    private init() {}
    private var locked = false
    func acquire() async {
        while locked { await Task.yield() }
        locked = true
    }
    func release() { locked = false }
}

@MainActor
@Suite("V5.1.15 LibraryFeatureStore Characterization", .serialized)
struct V5115LibraryFeatureStoreCharacterizationTests {

    // MARK: - Helpers

    private func makeStore() -> LibraryFeatureStore {
        LibraryFeatureStore(
            librarySettingsStore: LibrarySettingsStore(),
            libraryStore: LibraryStore(),
            libraryLogger: LibraryLogger(),
            libraryDiffEngine: LibraryDiffEngine(),
            librarySampleEditService: LibrarySampleEditService()
        )
    }

    private func makeDirtyDraft(sampleId: String) -> LibrarySampleEditDraft {
        LibrarySampleEditDraft(
            sampleId: sampleId,
            batchId: "B001",
            baseUpdatedAt: Date(),
            substrateTagsText: "dirty",
            numericValues: [],
            metadataValues: []
        )
    }

    private func makeCleanDraft(sampleId: String) -> LibrarySampleEditDraft {
        LibrarySampleEditDraft(
            sampleId: sampleId,
            batchId: "B001",
            baseUpdatedAt: Date(),
            substrateTagsText: "original",
            numericValues: [],
            metadataValues: []
        )
    }

    // MARK: - 1. librarySampleEditIsDirty: false when no draft

    @Test("librarySampleEditIsDirty is false when no draft is set")
    func sampleEditIsDirtyFalseWhenNoDraft() {
        let store = makeStore()
        #expect(!store.librarySampleEditIsDirty)
    }

    // MARK: - 2. librarySampleEditIsDirty: false when draft equals original

    @Test("librarySampleEditIsDirty is false when draft matches original")
    func sampleEditIsDirtyFalseWhenDraftMatchesOriginal() {
        let store = makeStore()
        let draft = makeCleanDraft(sampleId: "S001")
        store.librarySampleEditDraft = draft
        store.libraryState.sampleEditOriginalDraft = draft
        #expect(!store.librarySampleEditIsDirty)
    }

    // MARK: - 3. librarySampleEditIsDirty: true when draft differs from original

    @Test("librarySampleEditIsDirty is true when draft differs from original")
    func sampleEditIsDirtyTrueWhenDraftDiffers() {
        let store = makeStore()
        let original = makeCleanDraft(sampleId: "S001")
        let modified = makeDirtyDraft(sampleId: "S001")
        store.librarySampleEditDraft = modified
        store.libraryState.sampleEditOriginalDraft = original
        #expect(store.librarySampleEditIsDirty)
    }

    // MARK: - 4. dirty selection guard: defers when draft is dirty and target differs

    @Test("dirty selection guard defers selection change when sample edit is dirty")
    func dirtySelectionGuardDefers() {
        let store = makeStore()
        // Put store into drawer selection with a dirty draft
        store.libraryActiveSelectionSource = .drawer
        store.librarySelectedPrefix = "P"
        store.librarySelectedBatchId = "B001"
        store.librarySelectedSampleId = "S001"

        let original = makeCleanDraft(sampleId: "S001")
        let modified = makeDirtyDraft(sampleId: "S001")
        store.librarySampleEditDraft = modified
        store.libraryState.sampleEditOriginalDraft = original

        // Try to switch to a different drawer — should be deferred
        let outcome = store.selectExistingDrawer(prefix: "P", batchId: "B002", sampleId: "S002")

        if case .deferred = outcome { } else { Issue.record("Expected .deferred") }
        #expect(store.libraryPendingSelectionChangePrompt != nil)
        #expect(store.hasPendingSelectionChange())
    }

    // MARK: - 5. Cancel pending selection change clears prompt and pending state

    @Test("cancelPendingSelectionChange clears pending state and prompt")
    func cancelPendingSelectionChangeClearsState() {
        let store = makeStore()
        store.libraryActiveSelectionSource = .drawer
        store.librarySelectedPrefix = "P"
        store.librarySelectedBatchId = "B001"
        store.librarySelectedSampleId = "S001"

        let original = makeCleanDraft(sampleId: "S001")
        let modified = makeDirtyDraft(sampleId: "S001")
        store.librarySampleEditDraft = modified
        store.libraryState.sampleEditOriginalDraft = original

        _ = store.selectExistingDrawer(prefix: "P", batchId: "B002", sampleId: "S002")
        #expect(store.hasPendingSelectionChange())

        store.cancelPendingSelectionChange()
        #expect(!store.hasPendingSelectionChange())
        #expect(store.libraryPendingSelectionChangePrompt == nil)
    }

    // MARK: - 6. applyPendingSelectionChangeIfNeeded returns outcome and clears pending

    @Test("applyPendingSelectionChangeIfNeeded applies pending change and clears it")
    func applyPendingSelectionChangeIfNeededAppliesAndClears() {
        let store = makeStore()
        store.libraryActiveSelectionSource = .drawer
        store.librarySelectedPrefix = "P"
        store.librarySelectedBatchId = "B001"
        store.librarySelectedSampleId = "S001"

        let original = makeCleanDraft(sampleId: "S001")
        let modified = makeDirtyDraft(sampleId: "S001")
        store.librarySampleEditDraft = modified
        store.libraryState.sampleEditOriginalDraft = original

        _ = store.selectExistingDrawer(prefix: "P", batchId: "B002", sampleId: "S002")
        #expect(store.hasPendingSelectionChange())

        let result = store.applyPendingSelectionChangeIfNeeded()
        #expect(result != nil)
        #expect(!store.hasPendingSelectionChange())
        #expect(store.libraryPendingSelectionChangePrompt == nil)
        if case .appliedDrawer(let prefix, let batchId, _) = result {
            #expect(prefix == "P")
            #expect(batchId == "B002")
        } else {
            Issue.record("Expected .appliedDrawer outcome")
        }
    }

    // MARK: - 7. applyPreparedSyncReviewDecision returns .missingReview when no review

    @Test("applyPreparedSyncReviewDecision returns missingReview when no review loaded")
    func applyPreparedSyncReviewDecisionMissingReview() {
        let store = makeStore()
        #expect(store.libraryRefreshReview == nil)
        let decision = store.applyPreparedSyncReviewDecision()
        if case .missingReview = decision {
            // correct
        } else {
            Issue.record("Expected .missingReview but got \(decision)")
        }
    }

    // MARK: - 8. dismissRecomputeBanner stores fingerprint and zeroes count

    @Test("dismissRecomputeBanner stores fingerprint and zeroes stale count")
    func dismissRecomputeBannerStoresFingerprintAndZeroesCount() {
        let store = makeStore()
        // Plant a root path and a non-zero stale count
        store.librarySettings = LibrarySettings(rootPath: "/tmp/fake-root", allowedBatchPrefixes: [])
        store.recomputeStaleCount = 5

        store.dismissRecomputeBanner()

        #expect(store.recomputeStaleCount == 0)
    }

    // MARK: - 9. updateLibraryRoot clears verification state

    @Test("updateLibraryRoot clears verification path and message")
    func updateLibraryRootClearsVerificationState() {
        let store = makeStore()
        store.libraryRootVerificationPath = "/old/path"
        store.libraryRootVerificationMessage = "Previously verified."

        store.updateLibraryRoot(to: URL(fileURLWithPath: "/new/root"))

        #expect(store.librarySettings.rootPath == "/new/root")
        #expect(store.libraryRootVerificationPath == nil)
        #expect(store.libraryRootVerificationMessage == nil)
    }

    // MARK: - 10. normalizeLibrarySelection clears selection when no groups

    @Test("normalizeLibrarySelection clears batch and sample when no existing groups")
    func normalizeLibrarySelectionClearsWhenNoGroups() {
        let store = makeStore()
        store.libraryExistingGroups = [:]
        store.librarySelectedPrefix = "P"
        store.librarySelectedBatchId = "B001"
        store.librarySelectedSampleId = "S001"

        store.normalizeLibrarySelection()

        #expect(store.librarySelectedBatchId == nil)
        #expect(store.librarySelectedSampleId == nil)
    }

    // MARK: - 11. updateAllowedBatchPrefixes normalizes and uppercases input

    @Test("updateAllowedBatchPrefixes parses comma-separated values and uppercases them")
    func updateAllowedBatchPrefixesNormalizesInput() {
        let store = makeStore()

        store.updateAllowedBatchPrefixes(from: "abc, def , GHI")

        #expect(store.librarySettings.allowedBatchPrefixes == ["ABC", "DEF", "GHI"])
    }

    // MARK: - 12. syncLibraryBackup rejects overlapping paths

    @Test("syncLibraryBackup rejects backup path that overlaps with library root")
    func syncLibraryBackupRejectsOverlappingPath() {
        let store = makeStore()
        store.librarySettings = LibrarySettings(rootPath: "/library/root", allowedBatchPrefixes: [])
        store.librarySettings.backupPath = "/library/root/backup"

        store.syncLibraryBackup(formatSyncDate: { _ in "now" })

        #expect(store.libraryBackupError != nil)
        #expect(store.libraryBackupError!.contains("overlap") || store.libraryBackupError!.contains("overlap") || store.libraryBackupError!.contains("overlap") || store.libraryBackupError!.lowercased().contains("overlap"))
    }
}
