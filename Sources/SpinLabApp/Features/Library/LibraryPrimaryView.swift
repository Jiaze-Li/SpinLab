import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Library's Primary-pane content. Owns Primary-only leaf state (search
/// fields, section-collapse flags read only here, transient task handles)
/// directly as `@State`, and shares cross-pane state through `state`
/// (`LibraryWorkspaceState`, owned by `RootSplitView`).
@MainActor
struct LibraryPrimaryView: View {
    @Environment(SpinLabAppState.self) var appState
    @Environment(\.openWindow) private var openWindow
    @Bindable var state: LibraryWorkspaceState

    @State var allowedPrefixesDraft: String = ""
    @State var isLibrarySettingsExpanded = true
    @State var isRegistryWorkspaceExpanded = true
    @State var isSearchWorkspaceExpanded = true
    @State var searchBatchIdText: String = ""
    @State var searchSubstrateText: String = ""
    @State var searchKeywordText: String = ""
    @State var searchThicknessText: String = ""
    @State var searchOxygenText: String = ""
    @State var searchTemperatureText: String = ""
    @State var searchEnergyText: String = ""
    @State var searchThicknessToleranceText: String = ""
    @State var searchOxygenToleranceText: String = ""
    @State var searchTemperatureToleranceText: String = ""
    @State var searchEnergyToleranceText: String = ""
    @State var searchMatchedResults: [SearchResultItem] = []
    @State var searchHasExecuted = false
    @State var searchDebounceTask: Task<Void, Never>?
    @State var interactionPersistTask: Task<Void, Never>?
    @State var isWebLibraryPublishDetailsExpanded = false
    let computationService = LibraryViewComputationService()

    var body: some View {
        librarySettingsColumn
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.viewModel.bindActions(from: appState)
            state.viewModel.validateLibraryCacheOnAppear()
            applyRestoredInteractionState()
            rebuildPreviewDerivedData()
            syncSelection()
            // Load Workbench Results and Measurement Data for the restored/initial selection.
            // onChange(of: selectedSampleId) does not fire when the value is
            // already set before onAppear, so we must call these explicitly here.
            appState.library.loadWorkbenchResultsForCurrentSelection()
            appState.library.loadMeasurementDataForCurrentSelection()
            // Not persisted here: applyRestoredInteractionState() just loaded this exact
            // state from disk, so writing it back immediately would be a no-op save.
            appState.library.refreshRecomputeStaleCount()
        }
        .onChange(of: appState.library.libraryPreviewGroups) { _, _ in
            rebuildPreviewDerivedData()
            syncSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: appState.library.libraryBatchSyncStatusByID) { _, _ in
            rebuildPreviewDerivedData()
            syncSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: appState.library.libraryExistingGroups) { _, _ in
            rebuildPreviewDerivedData()
            syncSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: browserSelectedPrefix) { _, _ in
            rebuildPreviewDerivedData()
            scheduleInteractionStatePersist()
        }
        .onChange(of: browserSelectedBatchId) { _, newValue in
            print("[PERF][library] selectBatch id=\(newValue ?? "nil")")
            scheduleInteractionStatePersist()
        }
        .onChange(of: browserSelectedSampleId) { _, _ in
            if lib.libraryActiveSelectionSource == .browser {
                appState.library.loadWorkbenchResultsForCurrentSelection()
                appState.library.loadMeasurementDataForCurrentSelection()
            }
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedPrefix) { _, _ in
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedBatchId) { _, newValue in
            print("[PERF][library] selectBatch id=\(newValue ?? "nil")")
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedSampleId) { _, _ in
            if lib.libraryActiveSelectionSource == .drawer {
                appState.library.loadWorkbenchResultsForCurrentSelection()
                appState.library.loadMeasurementDataForCurrentSelection()
            }
            scheduleInteractionStatePersist()
        }
        .onChange(of: interactionStateSnapshot) { _, newValue in
            scheduleInteractionStatePersist()
        }
        .onChange(of: lib.webLibraryPublishState.presentationRevision) { _, _ in
            isWebLibraryPublishDetailsExpanded = false
        }
        .onChange(of: searchFingerprint) { _, _ in
            scheduleDebouncedSearchIfNeeded()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            interactionPersistTask?.cancel()
            interactionPersistTask = nil
            state.viewModel.persistInteractionState(interactionStateSnapshot)
        }
        .modifier(LibraryDialogsModifier(
            pendingSelectionChangeDialogBinding: pendingSelectionChangeDialogBinding,
            pendingPrompt: appState.library.libraryPendingSelectionChangePrompt,
            onSaveAndSwitch: { state.viewModel.saveAndContinuePendingSelectionChange() },
            onDiscardAndSwitch: { state.viewModel.discardAndContinuePendingSelectionChange() },
            onCancelSwitch: { appState.library.cancelPendingSelectionChange() },
            isShowingSampleChangeLog: $state.isShowingSampleChangeLog,
            selectedSample: selectedSample,
            changeLogEntries: selectedSample.map { appState.library.sampleChangeLog(for: $0) } ?? [],
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

    var librarySettingsColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                libraryColumnHeader
                webLibraryPublishStatusView

                librarySettingsSection
                registryWorkspaceSection
                searchWorkspaceSection
                existingDrawerSampleSection
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .animation(nil, value: selectedBatchId)
        .animation(nil, value: selectedSampleId)
        .animation(nil, value: browserSelectedBatchId)
        .animation(nil, value: browserSelectedSampleId)
    }

    var lib: LibraryFeatureStore {
        appState.library
    }

    func openRecomputeWindow() {
        appState.library.openRecomputePreview()
        openWindow(id: "recompute-preview")
    }

    // Drawer selection (Existing Drawer / search list).
    var selectedPrefix: String? {
        get { appState.library.librarySelectedPrefix }
        nonmutating set { appState.library.librarySelectedPrefix = newValue }
    }

    var selectedBatchId: String? {
        get { appState.library.librarySelectedBatchId }
        nonmutating set { appState.library.librarySelectedBatchId = newValue }
    }

    var selectedSampleId: String? {
        get { appState.library.librarySelectedSampleId }
        nonmutating set { appState.library.librarySelectedSampleId = newValue }
    }

    // Browser selection (Registry/Preview tree). Independent of the drawer
    // triple above — writing here never mutates drawer selection.
    var browserSelectedPrefix: String? {
        get { appState.library.libraryBrowserSelectedPrefix }
        nonmutating set { appState.library.libraryBrowserSelectedPrefix = newValue }
    }

    var browserSelectedBatchId: String? {
        get { appState.library.libraryBrowserSelectedBatchId }
        nonmutating set { appState.library.libraryBrowserSelectedBatchId = newValue }
    }

    var browserSelectedSampleId: String? {
        get { appState.library.libraryBrowserSelectedSampleId }
        nonmutating set { appState.library.libraryBrowserSelectedSampleId = newValue }
    }

    var selectedSample: LibrarySample? {
        state.selectedSample(appState)
    }

    var libraryColumnHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library")
                .font(AppFontScale.sectionTitle)
            Button("Export Audit") {
                presentAuditTrailExportPanel()
            }
            .font(.callout)
            .buttonStyle(.bordered)
            Button("Chart Audit") {
                appState.library.isShowingChartAudit = true
                appState.library.runChartAssetAudit()
            }
            .font(.callout)
            .buttonStyle(.bordered)
            Button("public to html") {
                state.viewModel.publishWebLibrary()
            }
            .font(.callout)
            .buttonStyle(.borderedProminent)
            .disabled(lib.webLibraryPublishState.isRunning)
            Spacer()
            Text(AppVersion.current)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    var webLibraryPublishStatusView: some View {
        let publishState = lib.webLibraryPublishState
        if publishState.isRunning || publishState.statusMessage != nil {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Image(systemName: publishState.isRunning ? "arrow.triangle.2.circlepath" : publishStatusIconName(for: publishState.statusMessage))
                        .font(.callout.weight(.semibold))
                    Text(publishState.statusMessage ?? "")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(publishStatusColor(for: publishState.statusMessage))
                    if publishState.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }

                if let summaryMessage = publishState.summaryMessage {
                    Text(summaryMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let completedAt = publishState.completedAt,
                   publishState.statusMessage == LibraryFeatureStore.WebLibraryPublishState.publishedSuccessfullyMessage {
                    Text("Updated \(completedAt, format: .dateTime.year().month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if publishState.statusMessage == LibraryFeatureStore.WebLibraryPublishState.publishFailedMessage,
                   !publishState.outputLines.isEmpty {
                    DisclosureGroup(isExpanded: $isWebLibraryPublishDetailsExpanded) {
                        ScrollView {
                            Text(formattedPublishDetails(publishState.outputLines))
                                .font(.callout.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } label: {
                        Text("Show details")
                            .font(.callout)
                    }
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    func publishStatusIconName(for statusMessage: String?) -> String {
        switch statusMessage {
        case LibraryFeatureStore.WebLibraryPublishState.publishedSuccessfullyMessage:
            return "checkmark.circle"
        case LibraryFeatureStore.WebLibraryPublishState.noChangesMessage:
            return "checkmark.circle"
        case LibraryFeatureStore.WebLibraryPublishState.publishFailedMessage:
            return "exclamationmark.triangle"
        default:
            return "square.and.arrow.up"
        }
    }

    func publishStatusColor(for statusMessage: String?) -> Color {
        switch statusMessage {
        case LibraryFeatureStore.WebLibraryPublishState.publishFailedMessage:
            return .red
        default:
            return .primary
        }
    }

    func formattedPublishDetails(_ lines: [LibraryFeatureStore.WebLibraryPublishOutputLine]) -> String {
        lines.map { entry in
            let prefix: String
            switch entry.kind {
            case .stdout:
                prefix = "stdout"
            case .stderr:
                prefix = "stderr"
            }
            return "\(prefix): \(entry.line)"
        }
        .joined(separator: "\n")
    }

    var librarySettingsSection: some View {
        LibrarySettingsSectionView(
            isExpanded: $isLibrarySettingsExpanded,
            library: lib,
            onChooseLibraryRoot: {
                presentLibraryRootPanel()
            },
            onVerifyRoot: {
                appState.library.verifyLibraryRoot()
            },
            onSyncFiles: {
                appState.library.syncLibraryFromFiles()
            },
            onBackfillSidecars: {
                openRecomputeWindow()
            },
            onChooseBackupPath: {
                presentBackupPathPanel()
            },
            onSyncBackup: {
                state.viewModel.syncLibraryBackup()
            }
        )
    }

    var registryWorkspaceSection: some View {
        RegistryWorkspaceSectionView(
            isExpanded: $isRegistryWorkspaceExpanded,
            allowedPrefixesDraft: $allowedPrefixesDraft,
            library: lib,
            canReloadSampleRegistry: appState.canReloadSampleRegistry,
            selectedPrefix: browserSelectedPrefix,
            selectedBatchId: browserSelectedBatchId,
            selectedSampleId: browserSelectedSampleId,
            previewPrefixes: previewPrefixes,
            previewGroupsForSelectedPrefix: previewGroupsForSelectedPrefix,
            selectedBatchSamples: selectedBatchSamples,
            onLoadRegistry: {
                presentSampleRegistryPanel()
            },
            onReloadRegistry: {
                state.viewModel.reloadSampleRegistry()
            },
            onSavePrefixes: { value in
                appState.library.updateAllowedBatchPrefixes(from: value)
            },
            onSelectPrefix: { newValue in
                browserSelectedPrefix = newValue
                let groupsForNew = computeCombinedPreviewGroupsByPrefix()[newValue] ?? []
                browserSelectedBatchId = groupsForNew.first?.batchId
                browserSelectedSampleId = groupsForNew.first?.samples.first?.id
                state.viewModel.selectBrowserSample()
            },
            onSelectBatch: { group in
                browserSelectedBatchId = group.batchId
                browserSelectedSampleId = group.samples.first?.id
                state.viewModel.selectBrowserSample()
            },
            onSelectSample: { sample in
                browserSelectedSampleId = sample.id
                state.viewModel.selectBrowserSample()
            },
            onSyncRegistry: {
                state.viewModel.syncLibraryFromRegistry()
            },
            onApplyAll: {
                state.viewModel.applyPreparedLibrarySyncReview()
            },
            onApplySelected: {
                state.viewModel.applySelectedRegistryDiff(batchId: browserSelectedBatchId)
            },
            obsidianVaultPath: lib.librarySettings.obsidianExperimentVaultPath,
            onChooseObsidianVault: {
                presentObsidianVaultPanel()
            },
            onOpenObsidianRegistryImport: {
                appState.library.openRegistryGrowthImportSheet()
            },
            syncStatusSymbol: { status in
                syncStatusSymbol(for: status)
            },
            syncStatusColor: { status in
                syncStatusColor(for: status)
            }
        )
    }

    func syncStatusSymbol(for status: LibrarySyncBatchStatus) -> String {
        switch status {
        case .added:
            return "plus.circle.fill"
        case .changed:
            return "circle.fill"
        case .removed:
            return "minus.circle.fill"
        case .unchanged:
            return "circle"
        }
    }

    func syncStatusColor(for status: LibrarySyncBatchStatus) -> Color {
        switch status {
        case .added:
            return .green
        case .changed:
            return .yellow
        case .removed:
            return .red
        case .unchanged:
            return .secondary
        }
    }
}

// MARK: - Selection / interaction-state persistence

extension LibraryPrimaryView {
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
        state.previewDerivedData.previewPrefixes
    }

    var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] {
        state.previewDerivedData.previewGroupsForSelectedPrefix
    }

    var selectedBatchSamples: [LibrarySample] {
        state.selectedBatchSamples(appState)
    }

    var selectedExistingBatchSamples: [LibrarySample] {
        state.selectedExistingBatchSamples(appState)
    }

    var interactionStateSnapshot: LibraryInteractionState {
        LibraryInteractionState(
            selectedPrefix: selectedPrefix,
            selectedBatchId: selectedBatchId,
            selectedSampleId: selectedSampleId,
            browserSelectedPrefix: browserSelectedPrefix,
            browserSelectedBatchId: browserSelectedBatchId,
            browserSelectedSampleId: browserSelectedSampleId,
            isLibrarySettingsExpanded: isLibrarySettingsExpanded,
            isRegistryWorkspaceExpanded: isRegistryWorkspaceExpanded,
            isSearchWorkspaceExpanded: isSearchWorkspaceExpanded,
            isMetadataSectionExpanded: state.isMetadataSectionExpanded,
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
            expandedWorkflowIDs: state.expandedWorkflows.isEmpty ? nil : state.expandedWorkflows,
            expandedSetIDs: state.expandedSets.isEmpty ? nil : state.expandedSets,
            expandedUncategorizedIDs: state.expandedUncategorized.isEmpty ? nil : state.expandedUncategorized
        )
    }

    func applyRestoredInteractionState() {
        let restored = state.viewModel.restoredInteractionState()
        selectedPrefix = restored.selectedPrefix
        selectedBatchId = restored.selectedBatchId
        selectedSampleId = restored.selectedSampleId
        browserSelectedPrefix = restored.browserSelectedPrefix
        browserSelectedBatchId = restored.browserSelectedBatchId
        browserSelectedSampleId = restored.browserSelectedSampleId
        isLibrarySettingsExpanded = restored.isLibrarySettingsExpanded
        isRegistryWorkspaceExpanded = restored.isRegistryWorkspaceExpanded
        isSearchWorkspaceExpanded = restored.isSearchWorkspaceExpanded
        state.isMetadataSectionExpanded = restored.isMetadataSectionExpanded
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

        state.expandedWorkflows = restored.expandedWorkflowIDs ?? []
        state.expandedSets = restored.expandedSetIDs ?? []
        state.expandedUncategorized = restored.expandedUncategorizedIDs ?? []

        if restored.searchHasExecuted {
            executeSearch()
        } else {
            searchMatchedResults = []
            searchHasExecuted = false
        }
    }

    func syncSelection() {
        // Browser and drawer selections are independent full triples — each is
        // reconciled against its own data source regardless of which pane is
        // currently focused in Detail, so the inactive pane's selection never
        // goes stale while unfocused. Neither call touches the other's fields.
        syncBrowserSelection()
        syncDrawerSelection()
    }

    // Validate browser selection against combined groups (preview + changed existing batches),
    // which is the same data source that rebuildPreviewDerivedData() and the Pending Queue render from.
    // If a future requirement needs strict "preview-only" validation, this should be split.
    func syncBrowserSelection() {
        let output = LibrarySelectionSync.syncBrowserSelection(
            input: .init(
                selectedPrefix: browserSelectedPrefix,
                selectedBatchId: browserSelectedBatchId,
                selectedSampleId: browserSelectedSampleId
            ),
            previewGroupsByPrefix: computeCombinedPreviewGroupsByPrefix()
        )
        browserSelectedPrefix = output.selectedPrefix
        browserSelectedBatchId = output.selectedBatchId
        browserSelectedSampleId = output.selectedSampleId
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
            state.viewModel.persistInteractionState(interactionStateSnapshot)
        }
    }

    func rebuildPreviewDerivedData() {
        let combined = computeCombinedPreviewGroupsByPrefix()
        let prefixes = computePreviewPrefixes(from: combined)
        let effectivePrefix = (browserSelectedPrefix.flatMap { combined.keys.contains($0) ? $0 : nil }) ?? prefixes.first
        let groupsForPrefix = combined[effectivePrefix ?? ""] ?? []
        state.previewDerivedData = PreviewDerivedData(
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

// MARK: - Search

extension LibraryPrimaryView {
    var searchWorkspaceSection: some View {
        SearchWorkspaceSectionView(
            isExpanded: $isSearchWorkspaceExpanded,
            batchIdText: $searchBatchIdText,
            substrateText: $searchSubstrateText,
            keywordText: $searchKeywordText,
            thicknessText: $searchThicknessText,
            oxygenText: $searchOxygenText,
            temperatureText: $searchTemperatureText,
            energyText: $searchEnergyText,
            thicknessToleranceText: $searchThicknessToleranceText,
            oxygenToleranceText: $searchOxygenToleranceText,
            temperatureToleranceText: $searchTemperatureToleranceText,
            energyToleranceText: $searchEnergyToleranceText,
            searchHasExecuted: searchHasExecuted,
            searchMatchedResults: searchMatchedResults,
            onSearch: {
                executeSearch()
            },
            onClear: {
                clearSearchFilters()
            },
            onSelectResult: { result in
                selectSearchResultSample(result)
            },
            isSelectedResult: { result in
                isSelectedSearchResult(result)
            }
        )
    }

    var existingDrawerSampleSection: some View {
        LibraryExistingDrawerSampleSectionView(
            selectedPrefix: lib.librarySelectedPrefix,
            selectedBatchId: lib.librarySelectedBatchId,
            selectedSampleId: lib.librarySelectedSampleId,
            selectedExistingBatchSamples: selectedExistingBatchSamples
        ) { sample in
            guard let prefix = lib.librarySelectedPrefix,
                  let batchId = lib.librarySelectedBatchId else {
                return
            }
            state.viewModel.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sample.id)
        }
    }

    var allExistingDrawerSamples: [SearchResultItem] {
        let flat = lib.libraryExistingGroups.flatMap { prefix, batchGroups in
            batchGroups.flatMap { group in
                group.samples.map { SearchResultItem(prefix: prefix, sample: $0) }
            }
        }
        return LibrarySort.sortedExistingDrawerSamples(flat, prefix: \.prefix, batchId: \.sample.batchId, substrate: \.sample.substrateDisplay)
    }

    var searchThicknessValue: Double? {
        Double(searchThicknessText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchOxygenValue: Double? {
        Double(searchOxygenText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchTemperatureValue: Double? {
        Double(searchTemperatureText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchEnergyValue: Double? {
        Double(searchEnergyText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchThicknessToleranceValue: Double? {
        Double(searchThicknessToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchOxygenToleranceValue: Double? {
        Double(searchOxygenToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchTemperatureToleranceValue: Double? {
        Double(searchTemperatureToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchEnergyToleranceValue: Double? {
        Double(searchEnergyToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clearSearchFilters() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        searchBatchIdText = ""
        searchSubstrateText = ""
        searchKeywordText = ""
        searchThicknessText = ""
        searchOxygenText = ""
        searchTemperatureText = ""
        searchEnergyText = ""
        searchThicknessToleranceText = ""
        searchOxygenToleranceText = ""
        searchTemperatureToleranceText = ""
        searchEnergyToleranceText = ""
        searchMatchedResults = []
        searchHasExecuted = false
    }

    func executeSearch() {
        searchMatchedResults = allExistingDrawerSamples.filter { result in
            computationService.matchesSearch(sample: result.sample, filters: searchFilters)
        }
        searchHasExecuted = true
    }

    var searchFingerprint: String {
        [
            searchBatchIdText,
            searchSubstrateText,
            searchKeywordText,
            searchThicknessText,
            searchOxygenText,
            searchTemperatureText,
            searchEnergyText,
            searchThicknessToleranceText,
            searchOxygenToleranceText,
            searchTemperatureToleranceText,
            searchEnergyToleranceText
        ].joined(separator: "|")
    }

    func scheduleDebouncedSearchIfNeeded() {
        guard searchHasExecuted else {
            return
        }

        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
                return
            }
            executeSearch()
        }
    }

    var searchFilters: LibrarySearchFilters {
        LibrarySearchFilters(
            batchText: searchBatchIdText,
            substrateText: searchSubstrateText,
            keywordText: searchKeywordText,
            thickness: searchThicknessValue,
            oxygen: searchOxygenValue,
            temperature: searchTemperatureValue,
            energy: searchEnergyValue,
            thicknessTolerance: searchThicknessToleranceValue,
            oxygenTolerance: searchOxygenToleranceValue,
            temperatureTolerance: searchTemperatureToleranceValue,
            energyTolerance: searchEnergyToleranceValue
        )
    }

    func selectSearchResultSample(_ result: SearchResultItem) {
        state.viewModel.selectExistingDrawer(prefix: result.prefix, batchId: result.sample.batchId, sampleId: result.sample.id)
    }

    func isSelectedSearchResult(_ result: SearchResultItem) -> Bool {
        lib.libraryActiveSelectionSource == .drawer
            && lib.librarySelectedPrefix == result.prefix
            && lib.librarySelectedBatchId == result.sample.batchId
            && lib.librarySelectedSampleId == result.sample.id
    }
}

// MARK: - File panels

extension LibraryPrimaryView {
    func presentLibraryRootPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Library Root"
        panel.message = "Select a folder for the SpinLab library store."
        if panel.runModal() == .OK, let url = panel.url {
            state.viewModel.updateLibraryRoot(to: url)
        }
    }

    func presentBackupPathPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Backup Path"
        panel.message = "Select a folder for Library backup sync."
        if panel.runModal() == .OK, let url = panel.url {
            appState.library.updateLibraryBackupPath(to: url)
        }
    }

    func presentSampleRegistryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let xlsxType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsxType]
        }
        panel.title = "Load Sample Registry"
        panel.message = "Choose an XLSX registry file."

        if panel.runModal() == .OK, let url = panel.url {
            state.viewModel.loadSampleRegistry(from: url)
        }
    }

    func presentObsidianVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Obsidian Vault"
        panel.message = "Select the Obsidian experiment vault folder to preview for Registry import."
        if panel.runModal() == .OK, let url = panel.url {
            appState.library.updateObsidianExperimentVaultPath(to: url)
        }
    }

    func presentAuditTrailExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Audit Trail"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "spinlab_audit_trail.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() != .OK {
            return
        }
        guard let destinationURL = panel.url else {
            return
        }

        do {
            let summary = try appState.exportAuditTrail(to: destinationURL)
            appState.presentAlert(
                title: "Audit Trail Exported",
                message: "Saved \(summary.entryCount) log entries to \(destinationURL.path)."
            )
        } catch {
            appState.presentAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }
}

#if DEBUG
struct LibraryPrimaryView_Previews: PreviewProvider {
    static var previews: some View {
        let registry = WorkflowRegistry.shared
        let bundle = registry.defaultBundle()
        let appState = SpinLabAppState(
            workflowBundle: bundle,
            persistence: LocalJSONPersistence(),
            libraryArchiveScan: LibraryArchiveScanService(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("spinlab-library-preview", isDirectory: true)
            )
        )
        let state = LibraryWorkspaceState()

        return HStack(spacing: 0) {
            LibraryPrimaryView(state: state)
            LibraryDetailView(state: state)
        }
            .environment(appState)
            .frame(width: 1200, height: 760)
    }
}
#endif
