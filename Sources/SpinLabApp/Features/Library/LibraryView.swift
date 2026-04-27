import SwiftUI

struct LibraryView: View {
    @Environment(SpinLabAppState.self) var appState
    @State var allowedPrefixesDraft: String = ""
    @State var isLibrarySettingsExpanded = true
    @State var isRegistryWorkspaceExpanded = true
    @State var isSearchWorkspaceExpanded = true
    @State var isMetadataSectionExpanded = true
    @State var isShowingSampleChangeLog = false
    @State var isShowingGlobalManualLog = false
    @State var isShowingMetadataSyncLog = false
    @State var conditionDetailMeasurement: AppliedMeasurement? = nil
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
    @State var previewDerivedData = PreviewDerivedData()
    @State var expandedWorkflows: Set<String> = []
    @State var expandedSets: Set<String> = []
    @State var expandedUncategorized: Set<String> = []
    @State var viewModel = LibraryViewModel()
    let computationService = LibraryViewComputationService()
    var workflowDisplayNameByID: [String: String] {
        Dictionary(uniqueKeysWithValues: appState.workflowDefinitions.map { ($0.id, $0.displayName) })
    }
    var workflowConditionOrderByID: [String: [String]] {
        Dictionary(uniqueKeysWithValues: appState.workflowDefinitions.map { definition in
            (definition.id, definition.conditionFields.map(\.definitionID))
        })
    }

    var body: some View {
        AppColumnShell(columnKey: "library", defaults: .library) {
            librarySettingsColumn
        } right: {
            libraryDetailColumn
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.bindActions(from: appState)
            viewModel.validateLibraryCacheOnAppear()
            applyRestoredInteractionState()
            rebuildPreviewDerivedData()
            syncSelection()
            // Load Workbench Results and Measurement Data for the restored/initial selection.
            // onChange(of: selectedSampleId) does not fire when the value is
            // already set before onAppear, so we must call these explicitly here.
            appState.library.loadWorkbenchResultsForCurrentSelection()
            appState.library.loadMeasurementDataForCurrentSelection()
            scheduleInteractionStatePersist(immediate: true)
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
        .onChange(of: selectedPrefix) { _, _ in
            rebuildPreviewDerivedData()
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedBatchId) { _, _ in
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedSampleId) { _, _ in
            appState.library.loadWorkbenchResultsForCurrentSelection()
            appState.library.loadMeasurementDataForCurrentSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: interactionStateSnapshot) { _, newValue in
            scheduleInteractionStatePersist()
        }
        .onChange(of: searchFingerprint) { _, _ in
            scheduleDebouncedSearchIfNeeded()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            interactionPersistTask?.cancel()
            interactionPersistTask = nil
            viewModel.persistInteractionState(interactionStateSnapshot)
        }
        .modifier(LibraryDialogsModifier(
            pendingSelectionChangeDialogBinding: pendingSelectionChangeDialogBinding,
            pendingPrompt: appState.library.libraryPendingSelectionChangePrompt,
            onSaveAndSwitch: { viewModel.saveAndContinuePendingSelectionChange() },
            onDiscardAndSwitch: { viewModel.discardAndContinuePendingSelectionChange() },
            onCancelSwitch: { appState.library.cancelPendingSelectionChange() },
            isShowingSampleChangeLog: $isShowingSampleChangeLog,
            selectedSample: selectedSample,
            changeLogEntries: selectedSample.map { appState.library.sampleChangeLog(for: $0) } ?? [],
            isShowingGlobalManualLog: $isShowingGlobalManualLog,
            globalManualLogs: appState.library.libraryGlobalManualLogs,
            globalManualLogError: appState.library.libraryGlobalManualLogError,
            globalManualLogMessage: appState.library.libraryGlobalManualLogMessage,
            onRefreshGlobalManualLog: { appState.library.loadLibraryGlobalManualLogs() },
            onMarkStatus: { appState.library.markLibraryGlobalManualLogStatus(rowIndex: $0, status: $1) },
            isShowingMetadataSyncLog: $isShowingMetadataSyncLog,
            metadataSyncEntries: appState.library.libraryMetadataSyncLogs,
            metadataSyncLogError: appState.library.libraryMetadataSyncLogError,
            metadataSyncLogMessage: appState.library.libraryMetadataSyncLogMessage,
            onRefreshMetadataSyncLog: { appState.library.loadLibraryMetadataSyncLogs() }
        ))
        .sheet(isPresented: Binding(
            get: { appState.library.isShowingRecomputePreview },
            set: { appState.library.isShowingRecomputePreview = $0 }
        )) {
            RecomputePreviewPanel(library: appState.library)
        }
        .sheet(item: $conditionDetailMeasurement) { measurement in
            MeasurementConditionDetailView(
                measurement: measurement,
                onSaveOverride: { id, value in
                    appState.library.saveConditionOverride(measurement: measurement, conditionId: id, value: value)
                },
                onRemoveOverride: { id in
                    appState.library.removeConditionOverride(measurement: measurement, conditionId: id)
                },
                onDismiss: { conditionDetailMeasurement = nil }
            )
        }
    }

    var librarySettingsColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                libraryColumnHeader

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
    }

    var lib: LibraryFeatureStore {
        appState.library
    }

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

    var libraryColumnHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library")
                .font(AppFontScale.sectionTitle)
            Button("Export Audit") {
                presentAuditTrailExportPanel()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            Spacer()
            Text(AppVersion.current)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
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
                appState.library.backfillLibraryMeasurementSidecars()
            },
            onChooseBackupPath: {
                presentBackupPathPanel()
            },
            onSyncBackup: {
                viewModel.syncLibraryBackup()
            }
        )
    }

    private var registryWorkspaceSection: some View {
        RegistryWorkspaceSectionView(
            isExpanded: $isRegistryWorkspaceExpanded,
            allowedPrefixesDraft: $allowedPrefixesDraft,
            library: lib,
            canReloadSampleRegistry: appState.canReloadSampleRegistry,
            selectedPrefix: selectedPrefix,
            selectedBatchId: selectedBatchId,
            selectedSampleId: selectedSampleId,
            previewPrefixes: previewPrefixes,
            previewGroupsForSelectedPrefix: previewGroupsForSelectedPrefix,
            selectedBatchSamples: selectedBatchSamples,
            onLoadRegistry: {
                presentSampleRegistryPanel()
            },
            onReloadRegistry: {
                viewModel.reloadSampleRegistry()
            },
            onSavePrefixes: { value in
                appState.library.updateAllowedBatchPrefixes(from: value)
            },
            onSelectPrefix: { newValue in
                selectedPrefix = newValue
                let groupsForNew = computeCombinedPreviewGroupsByPrefix()[newValue] ?? []
                selectedBatchId = groupsForNew.first?.batchId
                selectedSampleId = groupsForNew.first?.samples.first?.id
                viewModel.selectBrowserSample()
            },
            onSelectBatch: { group in
                selectedBatchId = group.batchId
                selectedSampleId = group.samples.first?.id
                viewModel.selectBrowserSample()
            },
            onSelectSample: { sample in
                selectedSampleId = sample.id
                viewModel.selectBrowserSample()
            },
            onSyncRegistry: {
                viewModel.syncLibraryFromRegistry()
            },
            onApplyAll: {
                viewModel.applyPreparedLibrarySyncReview()
            },
            onApplySelected: {
                viewModel.applySelectedRegistryDiff(batchId: selectedBatchId)
            },
            syncStatusSymbol: { status in
                syncStatusSymbol(for: status)
            },
            syncStatusColor: { status in
                syncStatusColor(for: status)
            }
        )
    }


}

struct PreviewDerivedData {
    var previewPrefixes: [String] = []
    var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] = []
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        let registry = WorkflowRegistry.shared
        let bundle = registry.bundle(for: .dummy) ?? registry.defaultBundle()
        let appState = SpinLabAppState(
            workflowBundle: bundle,
            persistence: LocalJSONPersistence(),
            managedStorage: SpinLabManagedStorage(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("spinlab-library-preview", isDirectory: true)
            )
        )

        return LibraryView()
            .environment(appState)
            .frame(width: 1200, height: 760)
    }
}
#endif
