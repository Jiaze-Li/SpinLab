import Foundation

/// Phase 5B UI orchestration for the Obsidian → Registry import preview.
/// Every step here only calls the existing Phase 1–5A read-only pipeline
/// (`ObsidianVaultParser` → `SampleDossierBuilder` →
/// `RegistryGrowthImportPlanner`) and the one write path
/// (`RegistryGrowthMutationService.apply`) — this file never re-implements
/// any planner/mutation business rule, and never persists the generated
/// plan (spec §10: transient UI state only, regenerated on each open).
@MainActor extension LibraryFeatureStore {

    // MARK: - Sheet lifecycle

    func openRegistryGrowthImportSheet() {
        isShowingRegistryGrowthImportSheet = true
        prepareRegistryGrowthImportPreview()
    }

    func closeRegistryGrowthImportSheet() {
        guard !isRegistryGrowthImportApplying else { return }
        isShowingRegistryGrowthImportSheet = false
        registryGrowthImportPlan = nil
        registryGrowthImportSelectedReadyBatchIds = []
        registryGrowthImportSelectedItemId = nil
        registryGrowthImportSelectedFilter = .ready
        registryGrowthImportError = nil
        registryGrowthImportMessage = nil
        registryGrowthImportNeedsRefresh = false
        registryGrowthImportLastApplyResult = nil
        isRegistryGrowthImportPreviewLoading = false
        isRegistryGrowthImportApplying = false
    }

    func updateObsidianExperimentVaultPath(to url: URL) {
        librarySettings.obsidianExperimentVaultPath = url.path
        librarySettingsStore.save(librarySettings)
    }

    // MARK: - Preview generation

    /// Rebuilds the plan from scratch: reads the Obsidian vault, reads the
    /// Registry, builds the dossier, then hands both to
    /// `RegistryGrowthImportPlanner`. Read-only — nothing here can write to
    /// either the vault or the Registry (the planner has no write path).
    func prepareRegistryGrowthImportPreview() {
        guard !isRegistryGrowthImportPreviewLoading else { return }
        guard let vaultPath = librarySettings.obsidianExperimentVaultPath, !vaultPath.isEmpty else {
            registryGrowthImportError = "Obsidian vault not set. Choose a vault folder first."
            return
        }
        guard let registryURL = resolveRegistrySourceURL?() else {
            registryGrowthImportError = "Registry not loaded. Load a Registry file first."
            return
        }

        registryGrowthImportPlan = nil
        registryGrowthImportSelectedReadyBatchIds = []
        registryGrowthImportSelectedItemId = nil
        registryGrowthImportLastApplyResult = nil
        isRegistryGrowthImportPreviewLoading = true
        registryGrowthImportError = nil
        registryGrowthImportMessage = nil
        registryGrowthImportNeedsRefresh = false

        let vaultURL = URL(fileURLWithPath: vaultPath)

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<RegistryGrowthImportPlan, Error> in
                do {
                    let ruleProvider = SpinLabRuleProvider.shared
                    let obsidian = ObsidianVaultParser.parseVault(at: vaultURL, ruleProvider: ruleProvider)
                    let parseSettings = LibrarySettings(
                        rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil,
                        registrySourcePath: registryURL.path, backupPath: nil, backupLastSyncedAt: nil,
                        allowedBatchPrefixes: [], lastRefreshAt: nil
                    )
                    let library = try LibraryRegistryParser(ruleProvider: ruleProvider).parse(
                        xlsxURL: registryURL, settings: parseSettings
                    ).index
                    let dossier = SampleDossierBuilder.build(library: library, obsidian: obsidian)
                    let plan = try RegistryGrowthImportPlanner(ruleProvider: ruleProvider).build(
                        vault: obsidian, dossier: dossier, registryURL: registryURL
                    )
                    return .success(plan)
                } catch {
                    return .failure(error)
                }
            }.value

            isRegistryGrowthImportPreviewLoading = false
            switch outcome {
            case let .success(plan):
                registryGrowthImportPlan = plan
                registryGrowthImportSelectedReadyBatchIds = Set(plan.items.filter(\.isExecutable).map(\.batchId))
                registryGrowthImportSelectedItemId = nil
            case let .failure(error):
                registryGrowthImportError = error.localizedDescription
            }
        }
    }

    func refreshRegistryGrowthImportPreview() {
        prepareRegistryGrowthImportPreview()
    }

    // MARK: - Selection (Ready tab only — Existing/Blocked are never selectable)

    func toggleRegistryGrowthImportSelection(batchId: String) {
        if registryGrowthImportSelectedReadyBatchIds.contains(batchId) {
            registryGrowthImportSelectedReadyBatchIds.remove(batchId)
        } else {
            registryGrowthImportSelectedReadyBatchIds.insert(batchId)
        }
    }

    func selectAllRegistryGrowthImportReadyItems() {
        guard let plan = registryGrowthImportPlan else { return }
        registryGrowthImportSelectedReadyBatchIds = Set(plan.items.filter(\.isExecutable).map(\.batchId))
    }

    func selectNoRegistryGrowthImportReadyItems() {
        registryGrowthImportSelectedReadyBatchIds = []
    }

    // MARK: - Apply

    /// Executes the mutation for the currently selected executable batch
    /// ids only. On success, triggers the existing Registry reload pipeline
    /// (`onReloadSampleRegistry`) rather than building a second sync path —
    /// the resulting Registry state still flows through the normal
    /// Registry → Library review the user already knows.
    func applyRegistryGrowthImport() {
        guard !isRegistryGrowthImportPreviewLoading else { return }
        guard let plan = registryGrowthImportPlan, !isRegistryGrowthImportApplying else { return }
        guard let registryURL = resolveRegistrySourceURL?() else {
            registryGrowthImportError = "Registry not loaded. Load a Registry file first."
            return
        }
        let selectedBatchIds = Self.selectedExecutableBatchIds(plan: plan, selected: registryGrowthImportSelectedReadyBatchIds)
        guard !selectedBatchIds.isEmpty else { return }

        isRegistryGrowthImportApplying = true
        registryGrowthImportError = nil
        registryGrowthImportMessage = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<RegistryGrowthApplyResult, Error> in
                do {
                    let result = try RegistryGrowthMutationService().apply(
                        plan: plan, selectedBatchIds: selectedBatchIds, registryURL: registryURL
                    )
                    return .success(result)
                } catch {
                    return .failure(error)
                }
            }.value

            isRegistryGrowthImportApplying = false
            switch outcome {
            case let .success(result):
                registryGrowthImportLastApplyResult = result
                registryGrowthImportMessage = Self.applySuccessMessage(for: result)
                registryGrowthImportPlan = nil
                registryGrowthImportSelectedReadyBatchIds = []
                registryGrowthImportSelectedItemId = nil
                onReloadSampleRegistry?()
            case let .failure(error):
                let failure = Self.applyFailureOutcome(for: error)
                registryGrowthImportNeedsRefresh = failure.needsRefresh
                registryGrowthImportError = failure.message
            }
        }
    }

    // MARK: - Pure helpers (spec §14/§16/§17 — no I/O, directly testable)

    /// Only ever includes batch ids that are both currently selected *and*
    /// still executable in `plan` — a stale/tampered selection set can never
    /// smuggle a `.skipExisting`/`.blocked` batch id into an apply call.
    nonisolated static func selectedExecutableBatchIds(plan: RegistryGrowthImportPlan, selected: Set<String>) -> [String] {
        plan.items
            .filter { $0.isExecutable && selected.contains($0.batchId) }
            .map(\.batchId)
    }

    nonisolated static func applySuccessMessage(for result: RegistryGrowthApplyResult) -> String {
        "Imported \(result.appliedBatchIds.count) batch(es). Backup created at \(result.backupPath). Registry updated. Library preview refreshed."
    }

    /// Maps an apply failure to (a) whether the UI should demand a refresh
    /// before allowing another apply, and (b) the message to show. A stale
    /// fingerprint is the only case that sets `needsRefresh` — every other
    /// failure keeps the existing plan/selection visible so the user can see
    /// which item failed.
    nonisolated static func applyFailureOutcome(for error: Error) -> (needsRefresh: Bool, message: String) {
        if let mutationError = error as? RegistryGrowthMutationError, case .staleFingerprint = mutationError {
            return (true, mutationError.localizedDescription)
        }
        return (false, error.localizedDescription)
    }
}
