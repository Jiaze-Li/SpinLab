import SwiftUI

struct LibraryView: View {
    @Environment(SpinLabAppState.self) var appState
    @Environment(\.openWindow) private var openWindow
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
    @State var isWebLibraryPublishDetailsExpanded = false
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
        .onChange(of: selectedPrefix) { _, _ in
            rebuildPreviewDerivedData()
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedBatchId) { _, newValue in
            print("[PERF][library] selectBatch id=\(newValue ?? "nil")")
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
        .sheet(item: $conditionDetailMeasurement) { measurement in
            MeasurementConditionDetailView(
                measurement: measurement,
                onLoadSidecar: { appState.library.loadSidecar(for: measurement) },
                onSaveOverride: { id, value in
                    appState.library.saveConditionOverride(measurement: measurement, conditionId: id, value: value)
                },
                onRemoveOverride: { id in
                    appState.library.removeConditionOverride(measurement: measurement, conditionId: id)
                },
                onDismiss: { conditionDetailMeasurement = nil }
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
    }

    var lib: LibraryFeatureStore {
        appState.library
    }

    func openRecomputeWindow() {
        appState.library.openRecomputePreview()
        openWindow(id: "recompute-preview")
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
            .font(.callout)
            .buttonStyle(.bordered)
            Button("Chart Audit") {
                appState.library.isShowingChartAudit = true
                appState.library.runChartAssetAudit()
            }
            .font(.callout)
            .buttonStyle(.bordered)
            Button("public to html") {
                viewModel.publishWebLibrary()
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
        let state = lib.webLibraryPublishState
        if state.isRunning || state.statusMessage != nil {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Image(systemName: state.isRunning ? "arrow.triangle.2.circlepath" : publishStatusIconName(for: state.statusMessage))
                        .font(.callout.weight(.semibold))
                    Text(state.statusMessage ?? "")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(publishStatusColor(for: state.statusMessage))
                    if state.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }

                if let summaryMessage = state.summaryMessage {
                    Text(summaryMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let completedAt = state.completedAt,
                   state.statusMessage == LibraryFeatureStore.WebLibraryPublishState.publishedSuccessfullyMessage {
                    Text("Updated \(completedAt, format: .dateTime.year().month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if state.statusMessage == LibraryFeatureStore.WebLibraryPublishState.publishFailedMessage,
                   !state.outputLines.isEmpty {
                    DisclosureGroup(isExpanded: $isWebLibraryPublishDetailsExpanded) {
                        ScrollView {
                            Text(formattedPublishDetails(state.outputLines))
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
        let bundle = registry.defaultBundle()
        let appState = SpinLabAppState(
            workflowBundle: bundle,
            persistence: LocalJSONPersistence(),
            libraryArchiveScan: LibraryArchiveScanService(
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
