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
        registryGrowthImportExistingFieldEdits = [:]
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
        // Existing field edits are scoped to one preview's plan (spec §5):
        // a rebuild — including a stale-fingerprint-triggered refresh —
        // must never carry a pending edit forward into a plan it was never
        // validated against.
        registryGrowthImportExistingFieldEdits = [:]
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

    // MARK: - Existing field reconciliation (Phase 5C)
    //
    // Transient per-preview edit state — see `registryGrowthImportExistingFieldEdits`.
    // Every entry point here only ever mutates that one dictionary; the
    // authoritative field identity/original value always comes back from
    // the current plan's `RegistryGrowthExistingDifference`, never from
    // caller-supplied values, so a stale/mistargeted call is a silent no-op
    // rather than corrupting state.

    /// Sets the confirmed Final value for one Existing field. Trims
    /// surrounding whitespace. Existing Final never supports clearing a
    /// Registry cell to blank in this pass: an empty/whitespace-only Final
    /// is treated the same as "Use Registry" — it resets/removes any
    /// pending edit for this field rather than leaving a stale edit behind
    /// (spec: emptying the field is Reset, never a silent no-op). A Final
    /// equal to the plan's Registry value likewise clears any pending edit
    /// (spec: "Final == Registry value → no mutation").
    func setRegistryGrowthImportExistingFieldFinal(batchId: String, header: String, finalValue: String) {
        guard let plan = registryGrowthImportPlan,
              let item = plan.items.first(where: { $0.batchId == batchId }),
              let diff = item.existingDifferences.first(where: { $0.header == header }) else { return }
        let trimmed = finalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == diff.registryValue {
            resetRegistryGrowthImportExistingField(batchId: batchId, header: header)
        } else {
            registryGrowthImportExistingFieldEdits[batchId, default: [:]][header] = trimmed
        }
    }

    /// "Use Obsidian" quick action.
    func useObsidianValueForRegistryGrowthImportExistingField(batchId: String, header: String) {
        guard let plan = registryGrowthImportPlan,
              let item = plan.items.first(where: { $0.batchId == batchId }),
              let diff = item.existingDifferences.first(where: { $0.header == header }) else { return }
        setRegistryGrowthImportExistingFieldFinal(batchId: batchId, header: header, finalValue: diff.obsidianValue)
    }

    /// "Use Registry" / Reset quick action — restores zero-pending-edit
    /// state for this one field.
    func resetRegistryGrowthImportExistingField(batchId: String, header: String) {
        registryGrowthImportExistingFieldEdits[batchId]?.removeValue(forKey: header)
        if registryGrowthImportExistingFieldEdits[batchId]?.isEmpty == true {
            registryGrowthImportExistingFieldEdits.removeValue(forKey: batchId)
        }
    }

    /// The value the Final field should display for one structured
    /// difference — the pending edit if one exists, otherwise the plan's
    /// own Registry value (the default, per spec §4).
    func finalValueForRegistryGrowthImportExistingField(batchId: String, diff: RegistryGrowthExistingDifference) -> String {
        registryGrowthImportExistingFieldEdits[batchId]?[diff.header] ?? diff.registryValue
    }

    /// Footer "Apply N" count — Ready batches selected via checkbox, plus
    /// Existing batches carrying at least one pending field edit (spec §10:
    /// counts BATCH operations, not individual edited fields).
    var registryGrowthImportApplyCount: Int {
        guard let plan = registryGrowthImportPlan else { return 0 }
        return Self.applyBatchCount(
            plan: plan, selectedReady: registryGrowthImportSelectedReadyBatchIds,
            existingFieldEdits: registryGrowthImportExistingFieldEdits
        )
    }

    /// Just the Ready half of `registryGrowthImportApplyCount` — split out so
    /// UI copy (e.g. the Apply confirmation dialog) can say "add/fill N new,
    /// update M existing" without re-deriving the split itself.
    var registryGrowthImportSelectedReadyCount: Int {
        guard let plan = registryGrowthImportPlan else { return 0 }
        return Self.selectedExecutableBatchIds(plan: plan, selected: registryGrowthImportSelectedReadyBatchIds).count
    }

    // MARK: - Apply

    /// Executes the mutation for the currently selected executable batch
    /// ids AND any pending Existing field edits. On success, triggers the
    /// existing Registry reload pipeline (`onReloadSampleRegistry`) rather
    /// than building a second sync path — the resulting Registry state
    /// still flows through the normal Registry → Library review the user
    /// already knows — and rebuilds this sheet's own preview (spec §11) so
    /// fields that now match Obsidian disappear from Existing differences.
    func applyRegistryGrowthImport() {
        guard !isRegistryGrowthImportPreviewLoading else { return }
        guard let plan = registryGrowthImportPlan, !isRegistryGrowthImportApplying else { return }
        guard let registryURL = resolveRegistrySourceURL?() else {
            registryGrowthImportError = "Registry not loaded. Load a Registry file first."
            return
        }
        let selectedBatchIds = Self.selectedExecutableBatchIds(plan: plan, selected: registryGrowthImportSelectedReadyBatchIds)
        let existingFieldEdits = Self.buildExistingFieldEdits(plan: plan, pending: registryGrowthImportExistingFieldEdits)
        guard !selectedBatchIds.isEmpty || !existingFieldEdits.isEmpty else { return }

        isRegistryGrowthImportApplying = true
        registryGrowthImportError = nil
        registryGrowthImportMessage = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<RegistryGrowthApplyResult, Error> in
                do {
                    let result = try RegistryGrowthMutationService().apply(
                        plan: plan, selectedBatchIds: selectedBatchIds, existingFieldEdits: existingFieldEdits, registryURL: registryURL
                    )
                    return .success(result)
                } catch {
                    return .failure(error)
                }
            }.value

            isRegistryGrowthImportApplying = false
            switch outcome {
            case let .success(result):
                let successMessage = Self.applySuccessMessage(for: result)
                registryGrowthImportLastApplyResult = result
                registryGrowthImportSelectedReadyBatchIds = []
                registryGrowthImportSelectedItemId = nil
                registryGrowthImportExistingFieldEdits = [:]
                onReloadSampleRegistry?()
                prepareRegistryGrowthImportPreview()
                registryGrowthImportMessage = successMessage
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

    /// Reconciles transient per-header pending edits against the current
    /// plan's own `existingDifferences`, dropping any entry that no longer
    /// names a real `.skipExisting` item or a real planned difference — a
    /// stale/mistargeted edit is silently excluded rather than sent to the
    /// mutation service (which would reject it anyway, but never even
    /// attempts to smuggle a caller-only sheet/row/original-value through).
    nonisolated static func buildExistingFieldEdits(
        plan: RegistryGrowthImportPlan, pending: [String: [String: String]]
    ) -> [RegistryGrowthExistingFieldEdit] {
        let itemsByBatchId = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.batchId, $0) })
        var result: [RegistryGrowthExistingFieldEdit] = []
        for (batchId, headerEdits) in pending {
            guard let item = itemsByBatchId[batchId], case let .skipExisting(sheet, row) = item.action else { continue }
            for (header, finalValue) in headerEdits {
                guard let diff = item.existingDifferences.first(where: { $0.header == header }) else { continue }
                result.append(RegistryGrowthExistingFieldEdit(
                    batchId: batchId, targetSheet: sheet, rowNumber: row, columnHeader: header,
                    field: diff.field, originalRegistryValue: diff.registryValue, finalValue: finalValue
                ))
            }
        }
        return result
    }

    /// Apply-count semantics — spec §10: one Existing batch with N edited
    /// fields still counts as ONE Apply operation.
    nonisolated static func applyBatchCount(
        plan: RegistryGrowthImportPlan, selectedReady: Set<String>, existingFieldEdits: [String: [String: String]]
    ) -> Int {
        let readyCount = selectedExecutableBatchIds(plan: plan, selected: selectedReady).count
        let existingBatchCount = buildExistingFieldEdits(plan: plan, pending: existingFieldEdits)
            .map(\.batchId)
        return readyCount + Set(existingBatchCount).count
    }

    nonisolated static func applySuccessMessage(for result: RegistryGrowthApplyResult) -> String {
        var parts: [String] = []
        if !result.appliedBatchIds.isEmpty {
            parts.append("Imported \(result.appliedBatchIds.count) batch(es)")
        }
        if !result.enrichedBatchIds.isEmpty {
            parts.append("Enriched \(result.enrichedBatchIds.count) existing Registry record(s)")
        }
        if !result.existingFieldEditBatchIds.isEmpty {
            parts.append("Manually updated \(result.existingFieldEditBatchIds.count) existing Registry record(s)")
        }
        let summary = parts.isEmpty ? "No changes applied" : parts.joined(separator: ". ")
        return "\(summary). Backup created at \(result.backupPath). Registry updated. Library preview refreshed."
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
