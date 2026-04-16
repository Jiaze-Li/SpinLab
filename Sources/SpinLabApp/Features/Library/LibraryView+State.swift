import SwiftUI

extension LibraryView {
    var pendingSelectionChangeDialogBinding: Binding<Bool> {
        Binding(
            get: { appState.library.hasPendingSelectionChange() },
            set: { isPresented in
                if !isPresented {
                    appState.library.cancelPendingSelectionChange()
                }
            }
        )
    }
    var previewPrefixes: [String] {
        previewDerivedData.previewPrefixes
    }

    var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] {
        previewDerivedData.previewGroupsForSelectedPrefix
    }

    var selectedBatchSamples: [LibrarySample] {
        guard let bid = selectedBatchId else { return [] }
        return previewDerivedData.previewGroupsForSelectedPrefix
            .first(where: { $0.batchId == bid })?.samples ?? []
    }

    var selectedSample: LibrarySample? {
        resolveSelectedSample(from: selectionEntry)
    }

    var selectedExistingSample: LibrarySample? {
        guard let prefix = lib.librarySelectedPrefix,
              let batchId = lib.librarySelectedBatchId,
              let sampleId = lib.librarySelectedSampleId else {
            return nil
        }
        let groups = lib.libraryExistingGroups[prefix] ?? []
        let samples = groups.first(where: { $0.batchId == batchId })?.samples ?? []
        return samples.first(where: { $0.id == sampleId })
    }

    var selectedExistingBatchSamples: [LibrarySample] {
        guard let prefix = lib.librarySelectedPrefix,
              let batchId = lib.librarySelectedBatchId else {
            return []
        }
        let groups = lib.libraryExistingGroups[prefix] ?? []
        return groups.first(where: { $0.batchId == batchId })?.samples ?? []
    }
    var interactionStateSnapshot: LibraryInteractionState {
        LibraryInteractionState(
            selectedPrefix: selectedPrefix,
            selectedBatchId: selectedBatchId,
            selectedSampleId: selectedSampleId,
            isLibrarySettingsExpanded: isLibrarySettingsExpanded,
            isRegistryWorkspaceExpanded: isRegistryWorkspaceExpanded,
            isSearchWorkspaceExpanded: isSearchWorkspaceExpanded,
            isMetadataSectionExpanded: isMetadataSectionExpanded,
            searchBatchIdText: searchBatchIdText,
            searchSubstrateText: searchSubstrateText,
            searchKeywordText: searchKeywordText,
            searchThicknessText: searchThicknessText,
            searchOxygenText: searchOxygenText,
            searchTemperatureText: searchTemperatureText,
            searchEnergyText: searchEnergyText,
            searchThicknessToleranceText: searchThicknessToleranceText,
            searchOxygenToleranceText: searchOxygenToleranceText,
            searchTemperatureToleranceText: searchTemperatureToleranceText,
            searchEnergyToleranceText: searchEnergyToleranceText,
            searchHasExecuted: searchHasExecuted,
            expandedWorkflowIDs: expandedWorkflows.isEmpty ? nil : expandedWorkflows,
            expandedSetIDs: expandedSets.isEmpty ? nil : expandedSets,
            expandedUncategorizedIDs: expandedUncategorized.isEmpty ? nil : expandedUncategorized
        )
    }

    func applyRestoredInteractionState() {
        let restored = viewModel.restoredInteractionState()
        selectedPrefix = restored.selectedPrefix
        selectedBatchId = restored.selectedBatchId
        selectedSampleId = restored.selectedSampleId
        isLibrarySettingsExpanded = restored.isLibrarySettingsExpanded
        isRegistryWorkspaceExpanded = restored.isRegistryWorkspaceExpanded
        isSearchWorkspaceExpanded = restored.isSearchWorkspaceExpanded
        isMetadataSectionExpanded = restored.isMetadataSectionExpanded
        searchBatchIdText = restored.searchBatchIdText
        searchSubstrateText = restored.searchSubstrateText
        searchKeywordText = restored.searchKeywordText
        searchThicknessText = restored.searchThicknessText
        searchOxygenText = restored.searchOxygenText
        searchTemperatureText = restored.searchTemperatureText
        searchEnergyText = restored.searchEnergyText
        searchThicknessToleranceText = restored.searchThicknessToleranceText
        searchOxygenToleranceText = restored.searchOxygenToleranceText
        searchTemperatureToleranceText = restored.searchTemperatureToleranceText
        searchEnergyToleranceText = restored.searchEnergyToleranceText

        expandedWorkflows = restored.expandedWorkflowIDs ?? []
        expandedSets = restored.expandedSetIDs ?? []
        expandedUncategorized = restored.expandedUncategorizedIDs ?? []

        if restored.searchHasExecuted {
            executeSearch()
        } else {
            searchMatchedResults = []
            searchHasExecuted = false
        }
    }

    func syncSelection() {
        // When the active source is .drawer, validate against existing groups
        // (not preview-derived data) so that unchanged batches stay selected.
        if lib.libraryActiveSelectionSource == .drawer {
            syncDrawerSelection()
            return
        }
        syncBrowserSelection()
    }

    // Validate browser selection against combined groups (preview + changed existing batches),
    // which is the same data source that rebuildPreviewDerivedData() and the Pending Queue render from.
    // If a future requirement needs strict "preview-only" validation, this should be split.
    func syncBrowserSelection() {
        let output = LibrarySelectionSync.syncBrowserSelection(
            input: .init(
                selectedPrefix: selectedPrefix,
                selectedBatchId: selectedBatchId,
                selectedSampleId: selectedSampleId
            ),
            previewGroupsByPrefix: computeCombinedPreviewGroupsByPrefix()
        )
        selectedPrefix = output.selectedPrefix
        selectedBatchId = output.selectedBatchId
        selectedSampleId = output.selectedSampleId
    }

    func syncDrawerSelection() {
        let output = LibrarySelectionSync.syncDrawerSelection(
            input: .init(
                selectedPrefix: selectedPrefix,
                selectedBatchId: selectedBatchId,
                selectedSampleId: selectedSampleId
            ),
            existingGroupsByPrefix: lib.libraryExistingGroups
        )
        selectedPrefix = output.selectedPrefix
        selectedBatchId = output.selectedBatchId
        selectedSampleId = output.selectedSampleId
    }
    func scheduleInteractionStatePersist(immediate: Bool = false) {
        interactionPersistTask?.cancel()
        interactionPersistTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled else {
                    return
                }
            }
            viewModel.persistInteractionState(interactionStateSnapshot)
        }
    }
    var selectionEntry: SelectionEntry {
        SelectionEntry(
            source: lib.libraryActiveSelectionSource,
            browserSampleId: selectedSampleId,
            drawerPrefix: lib.librarySelectedPrefix,
            drawerBatchId: lib.librarySelectedBatchId,
            drawerSampleId: lib.librarySelectedSampleId
        )
    }

    func resolveSelectedSample(from entry: SelectionEntry) -> LibrarySample? {
        switch entry.source {
        case .browser:
            guard let sampleId = entry.browserSampleId else {
                return nil
            }
            return selectedBatchSamples.first(where: { $0.id == sampleId })
        case .drawer:
            return selectedExistingSample
        }
    }

    func makeDetailSections(for sample: LibrarySample) -> SampleDetailSections {
        computationService.makeDetailSections(for: sample)
    }

    func rebuildPreviewDerivedData() {
        let combined = computeCombinedPreviewGroupsByPrefix()
        let prefixes = computePreviewPrefixes(from: combined)
        let effectivePrefix = (selectedPrefix.flatMap { combined.keys.contains($0) ? $0 : nil }) ?? prefixes.first
        let groupsForPrefix = combined[effectivePrefix ?? ""] ?? []
        previewDerivedData = PreviewDerivedData(
            previewPrefixes: prefixes,
            previewGroupsForSelectedPrefix: groupsForPrefix
        )
    }

    func computeCombinedPreviewGroupsByPrefix() -> [String: [LibraryPreviewBatchGroup]] {
        var groups = lib.libraryPreviewGroups
        for (batchID, status) in lib.libraryBatchSyncStatusByID where status != .unchanged {
            let prefix = LibrarySort.batchSortKey(batchID).prefix
            let alreadyExists = groups[prefix]?.contains(where: { $0.batchId == batchID }) == true
            if alreadyExists {
                continue
            }
            let existingSamples = lib.libraryExistingGroups[prefix]?
                .first(where: { $0.batchId == batchID })?
                .samples ?? []
            groups[prefix, default: []].append(
                LibraryPreviewBatchGroup(batchId: batchID, samples: existingSamples)
            )
        }
        for prefix in groups.keys {
            groups[prefix] = groups[prefix]?.sorted { LibrarySort.compareBatch($0.batchId, $1.batchId) }
        }
        return groups
    }

    func computePreviewPrefixes(from groups: [String: [LibraryPreviewBatchGroup]]) -> [String] {
        let configured = lib.librarySettings.allowedBatchPrefixes
        let available = Array(groups.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }
}
