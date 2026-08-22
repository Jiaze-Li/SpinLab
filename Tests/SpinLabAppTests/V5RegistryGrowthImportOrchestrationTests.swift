import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5B: `LibraryFeatureStore`'s Obsidian → Registry import UI
/// orchestration. Deliberately does not exercise the real
/// vault-parse/Registry-parse/plan-build I/O path (`prepareRegistryGrowthImportPreview`'s
/// success branch) — that pipeline is already covered end-to-end by
/// `V545RegistryGrowthImportPlannerTests`/`V545RegistryGrowthMutationServiceTests`,
/// and routing it through here would mean racing `SpinLabRuleProvider.shared`
/// like any other non-isolated Rules-dependent call
/// (docs/architecture/TESTING_STRATEGY.md). Instead this covers: the
/// transient-state guards/reset behavior around that I/O, and the pure
/// selection/apply-outcome helpers the async apply path delegates to.
@Suite("V5.4.6 LibraryFeatureStore Obsidian→Registry import orchestration")
@MainActor
struct V5RegistryGrowthImportOrchestrationTests {
    private func item(batchId: String, action: RegistryGrowthImportAction) -> RegistryGrowthImportItem {
        RegistryGrowthImportItem(
            batchId: batchId,
            sourceNotePaths: ["\(batchId).md"],
            targetSheetHint: "LNO",
            action: action,
            columnValues: [:],
            provenance: [],
            blankColumns: [],
            expectedSampleKeys: action.isBlockedOrSkip ? [] : ["\(batchId)|o|STO|001"],
            warnings: [],
            blockingReasons: {
                if case let .blocked(reasons) = action { return reasons }
                return []
            }()
        )
    }

    private func makePlan(items: [RegistryGrowthImportItem]) -> RegistryGrowthImportPlan {
        RegistryGrowthImportPlan(
            registryFingerprint: "fingerprint-1",
            registrySourcePath: "/tmp/registry.xlsx",
            builtAt: .now,
            items: items,
            diagnostics: [],
            existingCount: 0
        )
    }

    private func mixedPlan() -> RegistryGrowthImportPlan {
        makePlan(items: [
            item(batchId: "LNO14", action: .appendNewRow(targetSheet: "LNO")),
            item(batchId: "LNO15", action: .fillReservedRow(targetSheet: "LNO", rowNumber: 9)),
            item(batchId: "PN90", action: .skipExisting(targetSheet: "PLD-N样品", rowNumber: 3)),
            item(batchId: "PN106", action: .blocked(reasons: [.missingDate]))
        ])
    }

    // MARK: - 11/12. No Registry / no Obsidian path → preview unavailable

    @Test("11. No Registry path configured → preview unavailable, plan stays nil")
    func noRegistryPathMakesPreviewUnavailable() {
        let store = LibraryFeatureStore()
        store.librarySettings.obsidianExperimentVaultPath = "/tmp/vault"
        store.resolveRegistrySourceURL = { nil }

        store.prepareRegistryGrowthImportPreview()

        #expect(store.registryGrowthImportPlan == nil)
        #expect(store.registryGrowthImportError != nil)
        #expect(store.isRegistryGrowthImportPreviewLoading == false)
    }

    @Test("12. No Obsidian vault path configured → preview unavailable, plan stays nil")
    func noVaultPathMakesPreviewUnavailable() {
        let store = LibraryFeatureStore()
        store.librarySettings.obsidianExperimentVaultPath = nil
        store.resolveRegistrySourceURL = { URL(fileURLWithPath: "/tmp/registry.xlsx") }

        store.prepareRegistryGrowthImportPreview()

        #expect(store.registryGrowthImportPlan == nil)
        #expect(store.registryGrowthImportError != nil)
        #expect(store.isRegistryGrowthImportPreviewLoading == false)
    }

    // MARK: - 5/6/7. Ready default-selected; Existing/Blocked never selectable

    @Test("5/6/7. Select All only ever selects executable (Ready) batch ids")
    func selectAllOnlySelectsReady() {
        let store = LibraryFeatureStore()
        store.registryGrowthImportPlan = mixedPlan()

        store.selectAllRegistryGrowthImportReadyItems()

        #expect(store.registryGrowthImportSelectedReadyBatchIds == ["LNO14", "LNO15"])
    }

    @Test("6/7. Toggling a non-executable batch id never lets it reach the apply set")
    func toggleOnNonExecutableNeverReachesApplySet() {
        let store = LibraryFeatureStore()
        let plan = mixedPlan()
        store.registryGrowthImportPlan = plan

        // Simulate a defensive scenario: something adds an Existing/Blocked
        // batch id into the selection set directly (never via UI, since
        // Existing/Blocked rows render no checkbox) — apply must still
        // exclude it.
        store.registryGrowthImportSelectedReadyBatchIds = ["LNO14", "PN90", "PN106"]

        let applyIds = LibraryFeatureStore.selectedExecutableBatchIds(
            plan: plan, selected: store.registryGrowthImportSelectedReadyBatchIds
        )
        #expect(applyIds == ["LNO14"])
    }

    @Test("Select None clears the ready selection")
    func selectNoneClears() {
        let store = LibraryFeatureStore()
        store.registryGrowthImportPlan = mixedPlan()
        store.selectAllRegistryGrowthImportReadyItems()
        #expect(!store.registryGrowthImportSelectedReadyBatchIds.isEmpty)

        store.selectNoRegistryGrowthImportReadyItems()
        #expect(store.registryGrowthImportSelectedReadyBatchIds.isEmpty)
    }

    // MARK: - 8. Apply only ever passes selected + executable batch ids

    @Test("8. selectedExecutableBatchIds intersects selection with executable items only")
    func selectedExecutableBatchIdsIntersectsCorrectly() {
        let plan = mixedPlan()
        let ids = LibraryFeatureStore.selectedExecutableBatchIds(
            plan: plan, selected: ["LNO14", "LNO15", "PN90", "PN106", "does-not-exist"]
        )
        #expect(Set(ids) == ["LNO14", "LNO15"])
    }

    @Test("8b. An empty selection produces no apply ids")
    func emptySelectionProducesNoIds() {
        let plan = mixedPlan()
        #expect(LibraryFeatureStore.selectedExecutableBatchIds(plan: plan, selected: []).isEmpty)
    }

    // MARK: - 9. Stale fingerprint → refresh-required state

    @Test("9. staleFingerprint apply failure requests a refresh")
    func staleFingerprintRequestsRefresh() {
        let error = RegistryGrowthMutationError.staleFingerprint(planFingerprint: "a", currentFingerprint: "b")
        let outcome = LibraryFeatureStore.applyFailureOutcome(for: error)
        #expect(outcome.needsRefresh)
        #expect(!outcome.message.isEmpty)
    }

    @Test("9b. A non-stale-fingerprint apply failure does not request a refresh")
    func otherFailureDoesNotRequestRefresh() {
        let error = RegistryGrowthMutationError.itemNotFound(batchId: "LNO14")
        let outcome = LibraryFeatureStore.applyFailureOutcome(for: error)
        #expect(!outcome.needsRefresh)
        #expect(!outcome.message.isEmpty)
    }

    // MARK: - 10. Success state keeps the backup path visible

    @Test("10. Apply success message carries the backup path")
    func successMessageCarriesBackupPath() {
        let result = RegistryGrowthApplyResult(appliedBatchIds: ["LNO14", "LNO15"], backupPath: "/tmp/backup.xlsx")
        let message = LibraryFeatureStore.applySuccessMessage(for: result)
        #expect(message.contains("/tmp/backup.xlsx"))
        #expect(message.contains("2"))
    }

    // MARK: - Refresh replaces old plan / dedup guard

    @Test("Refresh while a preview is already in flight is a no-op (dedup guard)")
    func refreshWhileLoadingIsNoOp() {
        let store = LibraryFeatureStore()
        store.librarySettings.obsidianExperimentVaultPath = "/tmp/vault"
        store.resolveRegistrySourceURL = { URL(fileURLWithPath: "/tmp/registry.xlsx") }
        store.isRegistryGrowthImportPreviewLoading = true
        store.registryGrowthImportPlan = mixedPlan()

        store.refreshRegistryGrowthImportPreview()

        // Guarded early-return: the in-flight loading flag and existing plan
        // are left untouched rather than starting a second concurrent build.
        #expect(store.isRegistryGrowthImportPreviewLoading)
        #expect(store.registryGrowthImportPlan != nil)
    }

    // MARK: - Sheet lifecycle: closing never persists the plan (spec §10)

    @Test("Closing the sheet resets every transient preview/selection/apply field")
    func closeResetsTransientState() {
        let store = LibraryFeatureStore()
        store.isShowingRegistryGrowthImportSheet = true
        store.registryGrowthImportPlan = mixedPlan()
        store.registryGrowthImportSelectedReadyBatchIds = ["LNO14"]
        store.registryGrowthImportSelectedItemId = "LNO14|LNO"
        store.registryGrowthImportSelectedFilter = .blocked
        store.registryGrowthImportError = "some error"
        store.registryGrowthImportMessage = "some message"
        store.registryGrowthImportNeedsRefresh = true
        store.registryGrowthImportLastApplyResult = RegistryGrowthApplyResult(appliedBatchIds: ["LNO14"], backupPath: "/tmp/backup.xlsx")

        store.closeRegistryGrowthImportSheet()

        #expect(store.isShowingRegistryGrowthImportSheet == false)
        #expect(store.registryGrowthImportPlan == nil)
        #expect(store.registryGrowthImportSelectedReadyBatchIds.isEmpty)
        #expect(store.registryGrowthImportSelectedItemId == nil)
        #expect(store.registryGrowthImportSelectedFilter == .ready)
        #expect(store.registryGrowthImportError == nil)
        #expect(store.registryGrowthImportMessage == nil)
        #expect(store.registryGrowthImportNeedsRefresh == false)
        #expect(store.registryGrowthImportLastApplyResult == nil)
    }

    // MARK: - Phase 5B review: Refresh must invalidate the old plan immediately

    @Test("A. Starting a refresh immediately invalidates an existing plan, before the async rebuild resolves")
    func refreshImmediatelyInvalidatesOldPlan() {
        let store = LibraryFeatureStore()
        store.librarySettings.obsidianExperimentVaultPath = "/tmp/vault"
        store.resolveRegistrySourceURL = { URL(fileURLWithPath: "/tmp/registry.xlsx") }
        store.registryGrowthImportPlan = mixedPlan()
        store.registryGrowthImportSelectedReadyBatchIds = ["LNO14"]
        store.registryGrowthImportSelectedItemId = "LNO14|LNO"
        store.registryGrowthImportLastApplyResult = RegistryGrowthApplyResult(appliedBatchIds: ["LNO14"], backupPath: "/tmp/backup.xlsx")

        store.prepareRegistryGrowthImportPreview()

        // The invalidation happens synchronously, before the detached rebuild
        // task is even awaited — there is no window where the old plan is
        // still executable while a refresh is in flight.
        #expect(store.registryGrowthImportPlan == nil)
        #expect(store.registryGrowthImportSelectedReadyBatchIds.isEmpty)
        #expect(store.registryGrowthImportSelectedItemId == nil)
        #expect(store.registryGrowthImportLastApplyResult == nil)
        #expect(store.isRegistryGrowthImportPreviewLoading)
    }

    @Test("B. A failed refresh does not restore the old plan or selection")
    func failedRefreshDoesNotRestoreOldPlan() async throws {
        let store = LibraryFeatureStore()
        store.librarySettings.obsidianExperimentVaultPath = "/tmp/vault-does-not-exist-\(UUID().uuidString)"
        store.resolveRegistrySourceURL = { URL(fileURLWithPath: "/tmp/registry-does-not-exist-\(UUID().uuidString).xlsx") }
        store.registryGrowthImportPlan = mixedPlan()
        store.registryGrowthImportSelectedReadyBatchIds = ["LNO14"]

        store.prepareRegistryGrowthImportPreview()

        var iterations = 0
        while store.isRegistryGrowthImportPreviewLoading, iterations < 200 {
            try await Task.sleep(nanoseconds: 25_000_000)
            iterations += 1
        }

        #expect(store.isRegistryGrowthImportPreviewLoading == false)
        #expect(store.registryGrowthImportPlan == nil)
        #expect(store.registryGrowthImportSelectedReadyBatchIds.isEmpty)
        #expect(store.registryGrowthImportError != nil)
        #expect(LibraryFeatureStore.selectedExecutableBatchIds(
            plan: mixedPlan(), selected: store.registryGrowthImportSelectedReadyBatchIds
        ).isEmpty)
    }

    @Test("C. Apply is rejected while a preview refresh is in flight")
    func applyRejectedWhilePreviewLoading() {
        let store = LibraryFeatureStore()
        store.resolveRegistrySourceURL = { URL(fileURLWithPath: "/tmp/registry.xlsx") }
        store.registryGrowthImportPlan = mixedPlan()
        store.registryGrowthImportSelectedReadyBatchIds = ["LNO14"]
        store.isRegistryGrowthImportPreviewLoading = true

        store.applyRegistryGrowthImport()

        #expect(store.isRegistryGrowthImportApplying == false)
        #expect(store.registryGrowthImportPlan != nil)
    }

    // MARK: - Phase 5B review: sheet cannot be closed mid-apply

    @Test("Closing the sheet while a mutation is applying is a no-op")
    func closeIsNoOpWhileApplying() {
        let store = LibraryFeatureStore()
        store.isShowingRegistryGrowthImportSheet = true
        store.registryGrowthImportPlan = mixedPlan()
        store.isRegistryGrowthImportApplying = true

        store.closeRegistryGrowthImportSheet()

        #expect(store.isShowingRegistryGrowthImportSheet)
        #expect(store.registryGrowthImportPlan != nil)
    }

    // MARK: - Choosing a vault path persists into LibrarySettings

    @Test("Choosing an Obsidian vault path updates and persists librarySettings")
    func choosingVaultPathPersists() {
        let tempSettingsURL = FileManager.default.temporaryDirectory.appending(path: "V5-obsidian-settings-\(UUID().uuidString).json")
        let store = LibraryFeatureStore(librarySettingsStore: LibrarySettingsStore(settingsURL: tempSettingsURL))
        defer { try? FileManager.default.removeItem(at: tempSettingsURL) }

        store.updateObsidianExperimentVaultPath(to: URL(fileURLWithPath: "/tmp/my-vault"))

        #expect(store.librarySettings.obsidianExperimentVaultPath == "/tmp/my-vault")
        let reloaded = LibrarySettingsStore(settingsURL: tempSettingsURL).load()
        #expect(reloaded.obsidianExperimentVaultPath == "/tmp/my-vault")
    }
}

private extension RegistryGrowthImportAction {
    var isBlockedOrSkip: Bool {
        switch self {
        case .appendNewRow, .fillReservedRow: return false
        case .skipExisting, .blocked: return true
        }
    }
}
