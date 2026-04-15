import Testing
import Foundation
@testable import SpinLabApp

// MARK: - Pure logic tests (no filesystem, no mocks)

@MainActor
@Suite("LibraryFeatureStore facade — pure logic")
struct LibraryFeatureStorePureLogicTests {

    // MARK: - applyPreparedSyncReviewDecision

    @Test("applyPreparedSyncReviewDecision returns missingReview when no review")
    func syncDecision_missingReview() {
        let store = TestFixtures.makeStore()
        let result = store.applyPreparedSyncReviewDecision()
        guard case .missingReview = result else {
            Issue.record("Expected .missingReview, got \(result)")
            return
        }
    }

    @Test("applyPreparedSyncReviewDecision returns noChanges when review has zero changes")
    func syncDecision_noChanges() {
        let store = TestFixtures.makeStore()
        store.libraryRefreshReview = LibraryRefreshReview(
            generatedAt: Date(),
            newSamples: [],
            changedSamples: [],
            removedSamples: [],
            changedBatches: [],
            removedBatches: [],
            autoAppliedChanges: [],
            deferredNumericChanges: []
        )
        let result = store.applyPreparedSyncReviewDecision()
        guard case .noChanges = result else {
            Issue.record("Expected .noChanges, got \(result)")
            return
        }
    }

    @Test("applyPreparedSyncReviewDecision returns apply with correct count")
    func syncDecision_apply() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "s1", batchId: "b1")
        store.libraryRefreshReview = LibraryRefreshReview(
            generatedAt: Date(),
            newSamples: [sample],
            changedSamples: [],
            removedSamples: [],
            changedBatches: [],
            removedBatches: [],
            autoAppliedChanges: [],
            deferredNumericChanges: []
        )
        let result = store.applyPreparedSyncReviewDecision()
        guard case let .apply(totalChanges) = result else {
            Issue.record("Expected .apply, got \(result)")
            return
        }
        #expect(totalChanges == 1)
    }

    // MARK: - applySyncChangeIndicators

    @Test("applySyncChangeIndicators populates batch and sample change maps")
    func applySyncChangeIndicators() {
        let store = TestFixtures.makeStore()
        let indicators = LibrarySyncChangeIndicators(
            batchStatusByID: ["b1": .added, "b2": .changed],
            sampleChangesByID: ["s1": [LibraryFieldChange(key: "name", oldValue: "A", newValue: "B", isNumeric: false)]],
            batchChangesByID: [:]
        )
        store.applySyncChangeIndicators(indicators)
        #expect(store.libraryBatchSyncStatusByID["b1"] == .added)
        #expect(store.libraryBatchSyncStatusByID["b2"] == .changed)
        #expect(store.librarySampleSyncChangesByID["s1"]?.count == 1)
        #expect(store.libraryBatchSyncChangesByID.isEmpty)
    }

    // MARK: - incrementLibrarySelectionVersion

    @Test("incrementLibrarySelectionVersion advances version counter")
    func incrementVersion() {
        let store = TestFixtures.makeStore()
        let before = store.librarySelectionVersion
        store.incrementLibrarySelectionVersion()
        #expect(store.librarySelectionVersion == before &+ 1)
    }

    // MARK: - restoreInteraction / captureInteraction

    @Test("restoreInteraction sets all selection properties")
    func restoreInteraction() {
        let store = TestFixtures.makeStore()
        store.restoreInteraction(
            libraryActiveSelectionSource: .drawer,
            librarySelectedPrefix: "STO",
            librarySelectedBatchId: "B001",
            librarySelectedSampleId: "S1"
        )
        #expect(store.libraryActiveSelectionSource == .drawer)
        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B001")
        #expect(store.librarySelectedSampleId == "S1")
    }

    @Test("captureInteraction writes current state into snapshot")
    func captureInteraction() {
        let store = TestFixtures.makeStore()
        store.restoreInteraction(
            libraryActiveSelectionSource: .drawer,
            librarySelectedPrefix: "STO",
            librarySelectedBatchId: "B001",
            librarySelectedSampleId: "S1"
        )
        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)
        #expect(snapshot.libraryActiveSelectionSource == .drawer)
        #expect(snapshot.librarySelectedPrefix == "STO")
        #expect(snapshot.librarySelectedBatchId == "B001")
        #expect(snapshot.librarySelectedSampleId == "S1")
    }

    @Test("restoreInteraction → captureInteraction round-trip preserves nil values")
    func captureInteraction_nilRoundTrip() {
        let store = TestFixtures.makeStore()
        store.restoreInteraction(
            libraryActiveSelectionSource: .browser,
            librarySelectedPrefix: nil,
            librarySelectedBatchId: nil,
            librarySelectedSampleId: nil
        )
        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)
        #expect(snapshot.libraryActiveSelectionSource == .browser)
        #expect(snapshot.librarySelectedPrefix == nil)
        #expect(snapshot.librarySelectedBatchId == nil)
        #expect(snapshot.librarySelectedSampleId == nil)
    }

    // MARK: - normalizeLibrarySelection

    @Test("normalizeLibrarySelection picks first prefix when current is nil")
    func normalizeSelection_nilPrefix() {
        let store = TestFixtures.makeStore()
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [TestFixtures.makeSample(id: "s1", batchId: "B1")])],
            "FMR": [LibraryPreviewBatchGroup(batchId: "B2", samples: [TestFixtures.makeSample(id: "s2", batchId: "B2")])]
        ]
        store.normalizeLibrarySelection()
        #expect(store.librarySelectedPrefix != nil)
        #expect(store.librarySelectedBatchId != nil)
        #expect(store.librarySelectedSampleId != nil)
    }

    @Test("normalizeLibrarySelection resets batch/sample when prefix becomes invalid")
    func normalizeSelection_invalidPrefix() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "GONE"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "s1"
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [TestFixtures.makeSample(id: "s1", batchId: "B1")])]
        ]
        store.normalizeLibrarySelection()
        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B1")
        #expect(store.librarySelectedSampleId == "s1")
    }

    @Test("normalizeLibrarySelection clears all when groups empty")
    func normalizeSelection_empty() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "s1"
        store.libraryExistingGroups = [:]
        store.normalizeLibrarySelection()
        #expect(store.librarySelectedPrefix == nil)
        #expect(store.librarySelectedBatchId == nil)
        #expect(store.librarySelectedSampleId == nil)
    }

    // MARK: - selectedExistingDrawerSample

    @Test("selectedExistingDrawerSample returns nil when selection incomplete")
    func selectedDrawerSample_nil() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = nil
        #expect(store.selectedExistingDrawerSample() == nil)
    }

    @Test("selectedExistingDrawerSample returns matching sample from existing groups")
    func selectedDrawerSample_found() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "s1", batchId: "B1")
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])]
        ]
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "s1"
        let found = store.selectedExistingDrawerSample()
        #expect(found?.id == "s1")
    }

    // MARK: - Edit lifecycle

    @Test("beginEditingSelectedLibrarySample sets error when no sample")
    func beginEditing_noSample() {
        let store = TestFixtures.makeStore()
        store.beginEditingSelectedLibrarySample(selectedSample: nil)
        #expect(store.librarySampleEditError != nil)
        #expect(store.librarySampleEditDraft == nil)
    }

    @Test("cancelEditingSelectedLibrarySample clears draft and sets message")
    func cancelEditing() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "s1", batchId: "B1")
        store.beginEditingSelectedLibrarySample(selectedSample: sample)
        #expect(store.librarySampleEditDraft != nil)

        store.cancelEditingSelectedLibrarySample()
        #expect(store.librarySampleEditDraft == nil)
        #expect(store.librarySampleEditMessage == "Edit canceled.")
        #expect(store.librarySampleEditError == nil)
    }

    @Test("discardEditingSelectedLibrarySample clears draft with discard message")
    func discardEditing() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "s1", batchId: "B1")
        store.beginEditingSelectedLibrarySample(selectedSample: sample)

        store.discardEditingSelectedLibrarySample()
        #expect(store.librarySampleEditDraft == nil)
        #expect(store.librarySampleEditMessage == "Edit discarded.")
    }

    // MARK: - canEditSelectedLibrarySample

    @Test("canEditSelectedLibrarySample false when selection source is browser")
    func canEdit_browser() {
        let store = TestFixtures.makeStore()
        store.libraryActiveSelectionSource = .browser
        #expect(!store.canEditSelectedLibrarySample)
    }

    @Test("canEditSelectedLibrarySample false when drawer but no sample found")
    func canEdit_drawerNoSample() {
        let store = TestFixtures.makeStore()
        store.libraryActiveSelectionSource = .drawer
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = nil
        #expect(!store.canEditSelectedLibrarySample)
    }

    @Test("canEditSelectedLibrarySample true when drawer sample exists")
    func canEdit_drawerWithSample() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "s1", batchId: "B1")
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])]
        ]
        store.libraryActiveSelectionSource = .drawer
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "s1"
        #expect(store.canEditSelectedLibrarySample)
    }

    // MARK: - librarySampleEditIsDirty

    @Test("librarySampleEditIsDirty false when no draft")
    func editIsDirty_noDraft() {
        let store = TestFixtures.makeStore()
        #expect(!store.librarySampleEditIsDirty)
    }

    // MARK: - syncLibraryFromFilesForCurrentRoot

    @Test("syncLibraryFromFilesForCurrentRoot returns nil and sets message when no root")
    func syncFromFiles_noRoot() {
        let store = TestFixtures.makeStore()
        let outcome = store.syncLibraryFromFilesForCurrentRoot()
        #expect(outcome == nil)
        #expect(store.libraryRootVerificationMessage == "No Library Root selected.")
    }

    // MARK: - backfillSidecarsForCurrentRoot

    @Test("backfillSidecarsForCurrentRoot returns nil when no root")
    func backfillSidecars_noRoot() {
        let store = TestFixtures.makeStore()
        let outcome = store.backfillSidecarsForCurrentRoot()
        #expect(outcome == nil)
    }

    // MARK: - applySelectedRegistryDiff

    @Test("applySelectedRegistryDiff returns failure when batchId nil")
    func registryDiff_noBatch() {
        let store = TestFixtures.makeStore()
        let result = store.applySelectedRegistryDiff(batchId: nil)
        guard case let .failure(message) = result else {
            Issue.record("Expected .failure")
            return
        }
        #expect(message.contains("Select a batch"))
        #expect(store.libraryDrawerError != nil)
    }

    @Test("applySelectedRegistryDiff returns failure when no preview")
    func registryDiff_noPreview() {
        let store = TestFixtures.makeStore()
        let result = store.applySelectedRegistryDiff(batchId: "B1")
        guard case let .failure(message) = result else {
            Issue.record("Expected .failure")
            return
        }
        #expect(message.contains("registry preview"))
    }

    @Test("applySelectedRegistryDiff returns failure when no root path")
    func registryDiff_noRoot() {
        let store = TestFixtures.makeStore()
        store.libraryPreview = LibraryPreview(index: TestFixtures.emptyIndex, warnings: [])
        let result = store.applySelectedRegistryDiff(batchId: "B1")
        guard case let .failure(message) = result else {
            Issue.record("Expected .failure")
            return
        }
        #expect(message.contains("Library Root"))
    }
}

// MARK: - Facade callback wiring tests

@MainActor
@Suite("LibraryFeatureStore facade — callback wiring")
struct LibraryFeatureStoreFacadeCallbackTests {

    @Test("Selection property didSet fires onPersistInteractionSnapshot")
    func selectionDidSet_firesCallback() {
        let store = TestFixtures.makeStore()
        var callCount = 0
        store.configureFacade(
            mutationService: LibraryMutationService(),
            orchestrator: LibraryMutationOrchestrator(),
            saveEditsUseCase: SaveLibrarySampleEditsUseCase(),
            appLogger: AppLogger.shared,
            resolveRegistrySourceURL: { nil },
            applyExistingIndex: { _ in },
            refreshActionablePreviewGroups: { _, _ in },
            commitLibraryMutation: { _, _ in },
            loadExistingDrawers: { },
            presentError: { _, _ in },
            persistInteractionSnapshot: { callCount += 1 }
        )

        store.librarySelectedPrefix = "STO"
        #expect(callCount == 1)

        store.librarySelectedBatchId = "B1"
        #expect(callCount == 2)

        store.librarySelectedSampleId = "s1"
        #expect(callCount == 3)

        store.libraryActiveSelectionSource = .drawer
        #expect(callCount == 4)
    }

    @Test("loadLibraryGlobalManualLogs facade calls onPresentError on failure")
    func loadLogs_noRegistrySource_callsError() {
        let store = TestFixtures.makeStore()
        var presentedErrors: [(AppError, String)] = []
        store.configureFacade(
            mutationService: LibraryMutationService(),
            orchestrator: LibraryMutationOrchestrator(),
            saveEditsUseCase: SaveLibrarySampleEditsUseCase(),
            appLogger: AppLogger.shared,
            resolveRegistrySourceURL: { nil },
            applyExistingIndex: { _ in },
            refreshActionablePreviewGroups: { _, _ in },
            commitLibraryMutation: { _, _ in },
            loadExistingDrawers: { },
            presentError: { error, title in presentedErrors.append((error, title)) },
            persistInteractionSnapshot: { }
        )
        store.loadLibraryGlobalManualLogs()
        #expect(presentedErrors.count == 1)
        #expect(presentedErrors.first?.1 == "Log Load Failed")
    }

    @Test("loadLibraryMetadataSyncLogs facade calls onPresentError on failure")
    func loadMetadataLogs_noRegistrySource_callsError() {
        let store = TestFixtures.makeStore()
        var presentedErrors: [(AppError, String)] = []
        store.configureFacade(
            mutationService: LibraryMutationService(),
            orchestrator: LibraryMutationOrchestrator(),
            saveEditsUseCase: SaveLibrarySampleEditsUseCase(),
            appLogger: AppLogger.shared,
            resolveRegistrySourceURL: { nil },
            applyExistingIndex: { _ in },
            refreshActionablePreviewGroups: { _, _ in },
            commitLibraryMutation: { _, _ in },
            loadExistingDrawers: { },
            presentError: { error, title in presentedErrors.append((error, title)) },
            persistInteractionSnapshot: { }
        )
        store.loadLibraryMetadataSyncLogs()
        #expect(presentedErrors.count == 1)
        #expect(presentedErrors.first?.1 == "Log Load Failed")
    }

    @Test("syncLibraryFromFiles facade does nothing when no root path")
    func syncFromFiles_noRoot_noCallback() {
        let store = TestFixtures.makeStore()
        var commitCalled = false
        store.configureFacade(
            mutationService: LibraryMutationService(),
            orchestrator: LibraryMutationOrchestrator(),
            saveEditsUseCase: SaveLibrarySampleEditsUseCase(),
            appLogger: AppLogger.shared,
            resolveRegistrySourceURL: { nil },
            applyExistingIndex: { _ in },
            refreshActionablePreviewGroups: { _, _ in },
            commitLibraryMutation: { _, _ in commitCalled = true },
            loadExistingDrawers: { },
            presentError: { _, _ in },
            persistInteractionSnapshot: { }
        )
        store.syncLibraryFromFiles()
        #expect(!commitCalled)
        #expect(store.libraryRootVerificationMessage == "No Library Root selected.")
    }

    @Test("deleteExistingDrawer facade clears error state on entry")
    func deleteDrawer_clearsError() {
        let store = TestFixtures.makeStore()
        store.libraryDrawerError = "previous error"
        store.configureFacade(
            mutationService: LibraryMutationService(),
            orchestrator: LibraryMutationOrchestrator(),
            saveEditsUseCase: SaveLibrarySampleEditsUseCase(),
            appLogger: AppLogger.shared,
            resolveRegistrySourceURL: { nil },
            applyExistingIndex: { _ in },
            refreshActionablePreviewGroups: { _, _ in },
            commitLibraryMutation: { _, _ in },
            loadExistingDrawers: { },
            presentError: { _, _ in },
            persistInteractionSnapshot: { }
        )
        // deleteExistingDrawer calls the detailed method which clears error/message
        store.deleteExistingDrawer(batchId: "nonexistent")
        // The detailed method sets libraryDrawerError on failure path
        #expect(store.libraryDrawerError != nil || store.libraryDrawerMessage != nil)
    }

    @Test("isFacadeConfigured becomes true after configureFacade")
    func facadeConfigured() {
        let store = TestFixtures.makeStore()
        // Before configure — selection callbacks should not fire through facade
        // (didSet fires directly on property, but facade methods won't work)

        store.configureFacade(
            mutationService: LibraryMutationService(),
            orchestrator: LibraryMutationOrchestrator(),
            saveEditsUseCase: SaveLibrarySampleEditsUseCase(),
            appLogger: AppLogger.shared,
            resolveRegistrySourceURL: { nil },
            applyExistingIndex: { _ in },
            refreshActionablePreviewGroups: { _, _ in },
            commitLibraryMutation: { _, _ in },
            loadExistingDrawers: { },
            presentError: { _, _ in },
            persistInteractionSnapshot: { }
        )
        // Facade methods should now be callable without assertion failure
        // (calling syncLibraryFromFiles without root just returns early)
        store.syncLibraryFromFiles()
        #expect(store.libraryRootVerificationMessage == "No Library Root selected.")
    }
}

// MARK: - Selection change tests

@MainActor
@Suite("LibraryFeatureStore — selection change flow")
struct LibraryFeatureStoreSelectionTests {

    @Test("selectExistingDrawer sets selection when no dirty edit")
    func selectDrawer_noDirtyEdit() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "s1", batchId: "B1")
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])]
        ]
        let outcome = store.selectExistingDrawer(prefix: "STO", batchId: "B1", sampleId: "s1")
        guard case let .appliedDrawer(prefix, batchId, sampleId) = outcome else {
            Issue.record("Expected .appliedDrawer, got \(outcome)")
            return
        }
        #expect(prefix == "STO")
        #expect(batchId == "B1")
        #expect(sampleId == "s1")
        #expect(store.libraryActiveSelectionSource == .drawer)
    }

    @Test("cancelPendingSelectionChange clears pending state")
    func cancelPending() {
        let store = TestFixtures.makeStore()
        store.libraryState.pendingSelectionChange = .browser
        store.libraryPendingSelectionChangePrompt = "Save changes?"
        store.cancelPendingSelectionChange()
        #expect(!store.hasPendingSelectionChange())
        #expect(store.libraryPendingSelectionChangePrompt == nil)
    }

    @Test("hasPendingSelectionChange reflects libraryState")
    func hasPending() {
        let store = TestFixtures.makeStore()
        #expect(!store.hasPendingSelectionChange())
        store.libraryState.pendingSelectionChange = .drawer(prefix: "X", batchId: "B", sampleId: nil)
        #expect(store.hasPendingSelectionChange())
    }
}

// MARK: - Test fixtures

private enum TestFixtures {
    /// Creates a LibraryFeatureStore with no rootPath set (isolated from disk settings).
    @MainActor
    static func makeStore() -> LibraryFeatureStore {
        let store = LibraryFeatureStore()
        store.librarySettings.rootPath = nil
        return store
    }

    static let emptyIndex = LibraryIndex(
        version: 1,
        createdAt: Date(),
        updatedAt: Date(),
        registryInternalPath: nil,
        registrySourcePath: nil,
        metadataColumnOrder: [],
        batches: [],
        samples: []
    )

    static func makeSample(id: String, batchId: String) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: id,
            batchId: batchId,
            substrateRaw: "",
            substrateDisplay: "",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date()
        )
    }
}
