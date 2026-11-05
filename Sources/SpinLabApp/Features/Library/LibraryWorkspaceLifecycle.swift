import SwiftUI

// MARK: - Stable Library lifecycle owner
//
// Everything below used to run from `LibraryPrimaryView` (onAppear/onChange/
// onDisappear), which meant it only ran while the legacy Library page was the
// mounted Primary view — and re-ran on every remount (e.g. Gallery → Samples).
// `LibraryWorkspaceState` is owned by `RootSplitView`, which never unmounts, so
// the lifecycle is hosted here and driven by `LibraryWorkspaceHost`.

extension LibraryWorkspaceState {

    /// One-time initialisation. Idempotent: route switches never call this again.
    func start(appState: SpinLabAppState) {
        viewModel.bindActions(from: appState)
        guard !hasStarted else {
            return
        }
        markStarted()
        applyRestoredInteractionState(appState: appState)
        rebuildPreviewDerivedData(appState: appState)
        syncSelection(appState: appState)
        if appState.selectedArea == .library {
            didEnterLibraryArea(appState: appState)
        }
    }

    /// Work that used to happen each time the Library page appeared. Now keyed
    /// to entering the Library *area* (not any one route's view).
    func didEnterLibraryArea(appState: SpinLabAppState) {
        viewModel.validateLibraryCacheOnAppear()
        // onChange(of: selectedSampleId) does not fire for a value that was
        // already set (restored/initial selection), so load explicitly.
        appState.library.loadWorkbenchResultsForCurrentSelection()
        appState.library.loadMeasurementDataForCurrentSelection()
        appState.library.refreshRecomputeStaleCount()
    }

    // MARK: Selection reconciliation

    func syncSelection(appState: SpinLabAppState) {
        // Browser and drawer selections are independent full triples — each is
        // reconciled against its own data source regardless of which pane is
        // focused. Neither call touches the other's fields.
        syncBrowserSelection(appState: appState)
        syncDrawerSelection(appState: appState)
    }

    // Validate browser selection against combined groups (preview + changed existing batches),
    // the same data source rebuildPreviewDerivedData() and the Pending Queue render from.
    func syncBrowserSelection(appState: SpinLabAppState) {
        let lib = appState.library
        let output = LibrarySelectionSync.syncBrowserSelection(
            input: .init(
                selectedPrefix: lib.libraryBrowserSelectedPrefix,
                selectedBatchId: lib.libraryBrowserSelectedBatchId,
                selectedSampleId: lib.libraryBrowserSelectedSampleId
            ),
            previewGroupsByPrefix: computeCombinedPreviewGroupsByPrefix(appState: appState)
        )
        lib.libraryBrowserSelectedPrefix = output.selectedPrefix
        lib.libraryBrowserSelectedBatchId = output.selectedBatchId
        lib.libraryBrowserSelectedSampleId = output.selectedSampleId
    }

    func syncDrawerSelection(appState: SpinLabAppState) {
        let lib = appState.library
        let output = LibrarySelectionSync.syncDrawerSelection(
            input: .init(
                selectedPrefix: lib.librarySelectedPrefix,
                selectedBatchId: lib.librarySelectedBatchId,
                selectedSampleId: lib.librarySelectedSampleId
            ),
            existingGroupsByPrefix: lib.libraryExistingGroups
        )
        lib.librarySelectedPrefix = output.selectedPrefix
        lib.librarySelectedBatchId = output.selectedBatchId
        lib.librarySelectedSampleId = output.selectedSampleId
    }

    // MARK: Preview-derived data

    func rebuildPreviewDerivedData(appState: SpinLabAppState) {
        let combined = computeCombinedPreviewGroupsByPrefix(appState: appState)
        let prefixes = computePreviewPrefixes(from: combined, appState: appState)
        let browserPrefix = appState.library.libraryBrowserSelectedPrefix
        let effectivePrefix = (browserPrefix.flatMap { combined.keys.contains($0) ? $0 : nil }) ?? prefixes.first
        previewDerivedData = PreviewDerivedData(
            previewPrefixes: prefixes,
            previewGroupsForSelectedPrefix: combined[effectivePrefix ?? ""] ?? []
        )
    }

    func computeCombinedPreviewGroupsByPrefix(appState: SpinLabAppState) -> [String: [LibraryPreviewBatchGroup]] {
        let lib = appState.library
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

    func computePreviewPrefixes(
        from groups: [String: [LibraryPreviewBatchGroup]],
        appState: SpinLabAppState
    ) -> [String] {
        let configured = appState.library.librarySettings.allowedBatchPrefixes
        let available = Array(groups.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    // MARK: Interaction state (restore + persist; schema unchanged)

    func interactionSnapshot(appState: SpinLabAppState) -> LibraryInteractionState {
        let lib = appState.library
        return LibraryInteractionState(
            selectedPrefix: lib.librarySelectedPrefix,
            selectedBatchId: lib.librarySelectedBatchId,
            selectedSampleId: lib.librarySelectedSampleId,
            browserSelectedPrefix: lib.libraryBrowserSelectedPrefix,
            browserSelectedBatchId: lib.libraryBrowserSelectedBatchId,
            browserSelectedSampleId: lib.libraryBrowserSelectedSampleId,
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

    func applyRestoredInteractionState(appState: SpinLabAppState) {
        let restored = viewModel.restoredInteractionState()
        let lib = appState.library
        lib.librarySelectedPrefix = restored.selectedPrefix
        lib.librarySelectedBatchId = restored.selectedBatchId
        lib.librarySelectedSampleId = restored.selectedSampleId
        lib.libraryBrowserSelectedPrefix = restored.browserSelectedPrefix
        lib.libraryBrowserSelectedBatchId = restored.browserSelectedBatchId
        lib.libraryBrowserSelectedSampleId = restored.browserSelectedSampleId
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
        // Search *results* are page-local; the Search page re-executes when it
        // mounts with `searchHasExecuted` restored.
        searchHasExecuted = restored.searchHasExecuted
    }

    func scheduleInteractionStatePersist(appState: SpinLabAppState, immediate: Bool = false) {
        interactionPersistTask?.cancel()
        interactionPersistTask = Task { @MainActor [weak appState, weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled else {
                    return
                }
            }
            guard let self, let appState else {
                return
            }
            self.viewModel.persistInteractionState(self.interactionSnapshot(appState: appState))
        }
    }

    func flushInteractionState(appState: SpinLabAppState) {
        interactionPersistTask?.cancel()
        interactionPersistTask = nil
        viewModel.persistInteractionState(interactionSnapshot(appState: appState))
    }
}

// MARK: - Host modifier (root-level observation + global dialogs/sheets)

/// Applied once at `RootSplitView` level, above `AppWorkspaceShell`. Hosts every
/// Library observer and every dialog/sheet that must survive a route change.
/// No Library Primary/Detail view presents a global dialog or sheet itself.
struct LibraryWorkspaceHost: ViewModifier {
    @Environment(SpinLabAppState.self) private var appState
    @Bindable var state: LibraryWorkspaceState

    private var lib: LibraryFeatureStore { appState.library }

    func body(content: Content) -> some View {
        content
            .modifier(LibraryWorkspaceObservers(state: state))
            .modifier(LibraryDialogsModifier(
                pendingSelectionChangeDialogBinding: Binding(
                    get: { appState.library.hasPendingSelectionChange() },
                    set: { isPresented in
                        if !isPresented {
                            appState.library.cancelPendingSelectionChange()
                        }
                    }
                ),
                pendingPrompt: appState.library.libraryPendingSelectionChangePrompt,
                onSaveAndSwitch: { state.viewModel.saveAndContinuePendingSelectionChange() },
                onDiscardAndSwitch: { state.viewModel.discardAndContinuePendingSelectionChange() },
                onCancelSwitch: { appState.library.cancelPendingSelectionChange() },
                isShowingSampleChangeLog: $state.isShowingSampleChangeLog,
                selectedSample: state.selectedSample(appState),
                changeLogEntries: state.selectedSample(appState).map { appState.library.sampleChangeLog(for: $0) } ?? [],
                isShowingGlobalManualLog: $state.isShowingGlobalManualLog,
                globalManualLogs: appState.library.libraryGlobalManualLogs,
                globalManualLogError: appState.library.libraryGlobalManualLogError,
                globalManualLogMessage: appState.library.libraryGlobalManualLogMessage,
                onRefreshGlobalManualLog: { appState.library.loadLibraryGlobalManualLogs() },
                onMarkStatus: { appState.library.markLibraryGlobalManualLogStatus(rowIndex: $0, status: $1) },
                isShowingMetadataSyncLog: $state.isShowingMetadataSyncLog,
                metadataSyncEntries: appState.library.libraryMetadataSyncLogs,
                metadataSyncLogError: appState.library.libraryMetadataSyncLogError,
                metadataSyncLogMessage: appState.library.libraryMetadataSyncLogMessage,
                onRefreshMetadataSyncLog: { appState.library.loadLibraryMetadataSyncLogs() }
            ))
            .alert(
                "Unable to Switch Sample",
                isPresented: Binding(
                    get: { appState.library.libraryNavigationFailureMessage != nil },
                    set: { if !$0 { appState.library.libraryNavigationFailureMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appState.library.libraryNavigationFailureMessage ?? "The sample switch was not completed. Your pending changes are preserved.")
            }
            .sheet(item: $state.conditionDetailMeasurement) { measurement in
                MeasurementConditionDetailView(
                    measurement: measurement,
                    onLoadSidecar: { appState.library.loadSidecar(for: measurement) },
                    onSaveOverride: { id, value in
                        appState.library.saveConditionOverride(measurement: measurement, conditionId: id, value: value)
                    },
                    onRemoveOverride: { id in
                        appState.library.removeConditionOverride(measurement: measurement, conditionId: id)
                    },
                    onDismiss: { state.conditionDetailMeasurement = nil }
                )
            }
            .sheet(isPresented: Binding(
                get: { appState.library.isShowingChartAudit },
                set: { appState.library.isShowingChartAudit = $0 }
            )) {
                ChartAssetAuditView(
                    report: appState.library.chartAuditReport,
                    isRunning: appState.library.isChartAuditRunning,
                    message: appState.library.chartAuditMessage,
                    onRefresh: { appState.library.runChartAssetAudit() },
                    onDeleteSelected: { paths in
                        appState.library.deleteOrphanCharts(relativePaths: paths)
                    },
                    onDeleteAll: {
                        let report = appState.library.chartAuditReport
                        let allPaths = (report?.orphanImages ?? []).map(\.relativePath)
                            + (report?.orphanManifests ?? []).map(\.relativePath)
                        appState.library.deleteOrphanCharts(relativePaths: allPaths)
                    },
                    onCleanMissingRefs: { appState.library.cleanMissingReferences() },
                    onDismiss: { appState.library.isShowingChartAudit = false }
                )
            }
            .sheet(isPresented: Binding(
                get: { appState.library.isShowingRegistryGrowthImportSheet },
                set: { isPresented in
                    if !isPresented {
                        appState.library.closeRegistryGrowthImportSheet()
                    }
                }
            )) {
                RegistryGrowthImportSheet(
                    library: appState.library,
                    vaultPath: appState.library.librarySettings.obsidianExperimentVaultPath,
                    registryPath: appState.library.librarySettings.registrySourcePath,
                    onRefresh: { appState.library.refreshRegistryGrowthImportPreview() },
                    onToggleSelection: { batchId in appState.library.toggleRegistryGrowthImportSelection(batchId: batchId) },
                    onSelectAll: { appState.library.selectAllRegistryGrowthImportReadyItems() },
                    onSelectNone: { appState.library.selectNoRegistryGrowthImportReadyItems() },
                    onSelectFilter: { filter in appState.library.registryGrowthImportSelectedFilter = filter },
                    onSelectItem: { itemId in appState.library.registryGrowthImportSelectedItemId = itemId },
                    onApply: { appState.library.applyRegistryGrowthImport() },
                    onDismiss: { appState.library.closeRegistryGrowthImportSheet() }
                )
                .interactiveDismissDisabled(appState.library.isRegistryGrowthImportApplying)
            }
    }
}

/// Root-level `onChange` observers: selection reconciliation, projection
/// loading, preview-derived data and interaction-state persistence.
private struct LibraryWorkspaceObservers: ViewModifier {
    @Environment(SpinLabAppState.self) private var appState
    let state: LibraryWorkspaceState

    private var lib: LibraryFeatureStore { appState.library }

    func body(content: Content) -> some View {
        content
            .onChange(of: lib.libraryPreviewGroups) { _, _ in refreshAndPersist() }
            .onChange(of: lib.libraryBatchSyncStatusByID) { _, _ in refreshAndPersist() }
            .onChange(of: lib.libraryExistingGroups) { _, _ in refreshAndPersist() }
            .onChange(of: lib.libraryBrowserSelectedPrefix) { _, _ in
                state.rebuildPreviewDerivedData(appState: appState)
                persist()
            }
            .onChange(of: lib.libraryBrowserSelectedBatchId) { _, _ in persist() }
            .onChange(of: lib.libraryBrowserSelectedSampleId) { _, _ in
                if lib.libraryActiveSelectionSource == .browser {
                    reloadProjection()
                }
                persist()
            }
            .onChange(of: lib.librarySelectedPrefix) { _, _ in persist() }
            .onChange(of: lib.librarySelectedBatchId) { _, _ in persist() }
            .onChange(of: lib.librarySelectedSampleId) { _, _ in
                if lib.libraryActiveSelectionSource == .drawer {
                    reloadProjection()
                }
                persist()
            }
            .onChange(of: state.interactionSnapshot(appState: appState)) { _, _ in persist() }
            .onChange(of: appState.selectedArea) { oldArea, newArea in
                if newArea == .library, oldArea != .library {
                    state.didEnterLibraryArea(appState: appState)
                }
                if oldArea == .library, newArea != .library {
                    state.flushInteractionState(appState: appState)
                }
            }
    }

    private func refreshAndPersist() {
        appState.library.reconcileRouteWithLoadedData()
        state.rebuildPreviewDerivedData(appState: appState)
        state.syncSelection(appState: appState)
        persist()
    }

    private func reloadProjection() {
        appState.library.loadWorkbenchResultsForCurrentSelection()
        appState.library.loadMeasurementDataForCurrentSelection()
    }

    private func persist() {
        state.scheduleInteractionStatePersist(appState: appState)
    }
}
