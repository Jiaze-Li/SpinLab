import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var allowedPrefixesDraft: String = ""
    @State private var isLibrarySettingsExpanded = true
    @State private var isRegistryWorkspaceExpanded = true
    @State private var isSearchWorkspaceExpanded = true
    @State private var isMetadataSectionExpanded = true
    @State private var isShowingSampleChangeLog = false
    @State private var isShowingGlobalManualLog = false
    @State private var isShowingMetadataSyncLog = false
    @State private var searchBatchIdText: String = ""
    @State private var searchSubstrateText: String = ""
    @State private var searchKeywordText: String = ""
    @State private var searchThicknessText: String = ""
    @State private var searchOxygenText: String = ""
    @State private var searchTemperatureText: String = ""
    @State private var searchEnergyText: String = ""
    @State private var searchMatchedResults: [SearchResultItem] = []
    @State private var searchHasExecuted = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var interactionPersistTask: Task<Void, Never>?
    @State private var previewDerivedData = PreviewDerivedData()
    @State private var viewModel = LibraryViewModel()
    private let computationService = LibraryViewComputationService()
    private let level1HeaderFont: Font = .title2.bold()
    private let level2HeaderFont: Font = .title3.weight(.semibold)
    private let level3HeaderFont: Font = .headline
    private var workflowDisplayNameByID: [String: String] {
        Dictionary(uniqueKeysWithValues: appState.workflowDefinitions.map { ($0.id, $0.displayName) })
    }
    private var workflowConditionOrderByID: [String: [String]] {
        Dictionary(uniqueKeysWithValues: appState.workflowDefinitions.map { definition in
            (definition.id, definition.conditionFields.map(\.definitionID))
        })
    }

    var body: some View {
        HSplitView {
            librarySettingsColumn
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 680)
                .layoutPriority(1)

            libraryDetailColumn
                .frame(minWidth: 320, idealWidth: 500, maxWidth: .infinity)
                .layoutPriority(0)
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
        }
        .onChange(of: viewModel.viewState.previewGroupsByPrefix) { _, _ in
            rebuildPreviewDerivedData()
            syncSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: viewModel.viewState.batchSyncStatusByID) { _, _ in
            rebuildPreviewDerivedData()
            syncSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: viewModel.viewState.existingGroupsByPrefix) { _, _ in
            rebuildPreviewDerivedData()
            syncSelection()
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedPrefix) { _, _ in
            rebuildPreviewDerivedData()
            scheduleInteractionStatePersist()
        }
        .onChange(of: selectedBatchId) { _, _ in
            rebuildPreviewDerivedData()
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
            pendingPrompt: viewModel.viewState.pendingSelectionChangePrompt,
            onSaveAndSwitch: { viewModel.saveAndContinuePendingSelectionChange() },
            onDiscardAndSwitch: { viewModel.discardAndContinuePendingSelectionChange() },
            onCancelSwitch: { viewModel.cancelPendingSelectionChange() },
            isShowingSampleChangeLog: $isShowingSampleChangeLog,
            selectedSample: selectedSample,
            changeLogEntries: selectedSample.map { appState.library.sampleChangeLog(for: $0) } ?? [],
            isShowingGlobalManualLog: $isShowingGlobalManualLog,
            globalManualLogs: viewModel.viewState.globalManualLogs,
            globalManualLogError: viewModel.viewState.globalManualLogError,
            globalManualLogMessage: viewModel.viewState.globalManualLogMessage,
            onRefreshGlobalManualLog: { viewModel.loadLibraryGlobalManualLogs() },
            onMarkStatus: { viewModel.markLibraryGlobalManualLogStatus(rowIndex: $0, status: $1) },
            isShowingMetadataSyncLog: $isShowingMetadataSyncLog,
            metadataSyncEntries: viewModel.viewState.metadataSyncLogs,
            metadataSyncLogError: viewModel.viewState.metadataSyncLogError,
            metadataSyncLogMessage: viewModel.viewState.metadataSyncLogMessage,
            onRefreshMetadataSyncLog: { viewModel.loadLibraryMetadataSyncLogs() }
        ))
    }

    private var librarySettingsColumn: some View {
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

    private var viewState: LibraryViewState {
        viewModel.viewState
    }

    private var selectedPrefix: String? {
        get { appState.librarySelectedPrefix }
        nonmutating set { appState.librarySelectedPrefix = newValue }
    }

    private var selectedBatchId: String? {
        get { appState.librarySelectedBatchId }
        nonmutating set { appState.librarySelectedBatchId = newValue }
    }

    private var selectedSampleId: String? {
        get { appState.librarySelectedSampleId }
        nonmutating set { appState.librarySelectedSampleId = newValue }
    }

    private var libraryColumnHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library")
                .font(level1HeaderFont)
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

    private var librarySettingsSection: some View {
        LibrarySettingsSectionView(
            isExpanded: $isLibrarySettingsExpanded,
            allowedPrefixesDraft: $allowedPrefixesDraft,
            level2HeaderFont: level2HeaderFont,
            level3HeaderFont: level3HeaderFont,
            viewState: viewState,
            canReloadSampleRegistry: appState.canReloadSampleRegistry,
            onLoadRegistry: {
                presentSampleRegistryPanel()
            },
            onReloadRegistry: {
                viewModel.reloadSampleRegistry()
            },
            onChooseLibraryRoot: {
                presentLibraryRootPanel()
            },
            onVerifyRoot: {
                viewModel.verifyLibraryRoot()
            },
            onSyncFiles: {
                viewModel.syncLibraryFromFiles()
            },
            onBackfillSidecars: {
                viewModel.backfillLibraryMeasurementSidecars()
            },
            onSavePrefixes: { value in
                viewModel.updateAllowedBatchPrefixes(from: value)
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
            level2HeaderFont: level2HeaderFont,
            level3HeaderFont: level3HeaderFont,
            viewState: viewState,
            selectedPrefix: selectedPrefix,
            selectedBatchId: selectedBatchId,
            selectedSampleId: selectedSampleId,
            previewPrefixes: previewPrefixes,
            previewGroupsForSelectedPrefix: previewGroupsForSelectedPrefix,
            selectedBatchSamples: selectedBatchSamples,
            onSelectPrefix: { newValue in
                selectedPrefix = newValue
                selectedBatchId = previewGroupsForSelectedPrefix.first?.batchId
                selectedSampleId = previewGroupsForSelectedPrefix.first?.samples.first?.id
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

    private var searchWorkspaceSection: some View {
        SearchWorkspaceSectionView(
            isExpanded: $isSearchWorkspaceExpanded,
            batchIdText: $searchBatchIdText,
            substrateText: $searchSubstrateText,
            keywordText: $searchKeywordText,
            thicknessText: $searchThicknessText,
            oxygenText: $searchOxygenText,
            temperatureText: $searchTemperatureText,
            energyText: $searchEnergyText,
            level2HeaderFont: level2HeaderFont,
            level3HeaderFont: level3HeaderFont,
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

    private var existingDrawerSampleSection: some View {
        LibraryExistingDrawerSampleSectionView(
            level2HeaderFont: level2HeaderFont,
            level3HeaderFont: level3HeaderFont,
            selectedPrefix: viewState.selectedPrefix,
            selectedBatchId: viewState.selectedBatchId,
            selectedSampleId: viewState.selectedSampleId,
            selectedExistingBatchSamples: selectedExistingBatchSamples
        ) { sample in
            guard let prefix = viewState.selectedPrefix,
                  let batchId = viewState.selectedBatchId else {
                return
            }
            viewModel.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sample.id)
        }
    }

    private var libraryDetailColumn: some View {
        GeometryReader { proxy in
            let detailWidth = proxy.size.width
            let detailHeight = proxy.size.height
            let sectionWidth = max(detailWidth - 24, 0)
            let sectionSpacing = adaptiveDetailSectionSpacing(for: detailHeight)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    sampleDetailHeader

                    if let sample = selectedSample {
                        if isEditingSelectedSample, let draft = viewState.sampleEditDraft {
                            let sections = makeDetailSections(for: sample)
                            let globalFirstColumnWidth = alignedFirstColumnWidth(
                                fields: sections.allFields,
                                availableWidth: sectionWidth
                            )
                            samplePrimarySection(
                                for: sample,
                                draft: draft,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )
                            Divider()
                            editNumericSection(draft: draft)
                            Divider()
                            editMetadataSection(draft: draft, availableWidth: sectionWidth)
                        } else {
                            let sections = makeDetailSections(for: sample)
                            let globalFirstColumnWidth = alignedFirstColumnWidth(
                                fields: sections.allFields,
                                availableWidth: sectionWidth
                            )

                            samplePrimarySection(
                                for: sample,
                                draft: nil,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )

                            if !selectedChangeHighlights(for: sample).isEmpty {
                                Divider()
                                Text("Pending Changes")
                                    .font(.headline)
                                pendingChangesSection(for: sample)
                            }

                            if !sections.numericFields.isEmpty {
                                Divider()
                                Text("Numeric Tags")
                                    .font(sampleDetailSectionTitleFont)
                                detailSection(
                                    fields: sections.numericFields,
                                    availableWidth: sectionWidth,
                                    sharedFirstColumnWidth: globalFirstColumnWidth
                                )
                            }

                            Divider()
                            MeasurementDataSectionView(
                                measurementData: appState.library.measurementData,
                                conditionAliasBook: appState.library.conditionAliasBook,
                                availableWidth: sectionWidth
                            )

                            Divider()
                            DisclosureGroup(isExpanded: $isMetadataSectionExpanded) {
                                if sample.orderedMetadata.isEmpty {
                                    Text("No metadata")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    detailSection(
                                        fields: sections.metadataFields,
                                        availableWidth: sectionWidth,
                                        sharedFirstColumnWidth: globalFirstColumnWidth
                                    )
                                }
                            } label: {
                                Text("Metadata")
                                    .font(sampleDetailSectionTitleFont)
                            }

                            Divider()
                            LibraryMeasurementsDoneSection(
                                measurements: sample.appliedMeasurements,
                                workflowDisplayNameByID: workflowDisplayNameByID,
                                workflowConditionOrderByID: workflowConditionOrderByID,
                                onDelete: { m in appState.library.deleteAppliedMeasurement(m) }
                            )

                            Divider()
                            WorkbenchResultsSectionView(
                                workbenchResults: appState.library.workbenchResults,
                                libraryRootURL: appState.library.librarySettings.rootPath.map { URL(fileURLWithPath: $0) },
                                onDelete: { ref in appState.library.deleteWorkbenchResult(ref) }
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "No Sample Selected",
                            systemImage: "tray",
                            description: Text("Select a prefix, batch, and sample to view metadata.")
                        )
                    }
                }
                .frame(minHeight: max(detailHeight - 8, 0), alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
            }
        }
        .onChange(of: appState.workbench.aheWorkspace.persistCount) { _, _ in
            appState.library.loadWorkbenchResultsForCurrentSelection()
            appState.library.loadMeasurementDataForCurrentSelection()
        }
    }

    @ViewBuilder
    private func samplePrimarySection(
        for sample: LibrarySample,
        draft: LibrarySampleEditDraft?,
        availableWidth: CGFloat,
        sharedFirstColumnWidth: CGFloat?
    ) -> some View {
        if let firstWidth = sharedFirstColumnWidth {
            HStack(alignment: .top, spacing: 12) {
                samplePrimaryLeftColumn(for: sample)
                    .frame(width: firstWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                samplePrimaryRightColumn(for: sample, draft: draft)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                samplePrimaryLeftColumn(for: sample)
                samplePrimaryRightColumn(for: sample, draft: draft)
            }
        }
    }

    @ViewBuilder
    private func samplePrimaryLeftColumn(for sample: LibrarySample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataValueRow(label: "Sample", value: sample.displayName)
            MetadataValueRow(label: "Sample Key", value: sample.id, monospaced: true)
            MetadataValueRow(label: "Substrate", value: sample.substrateDisplay)
        }
    }

    @ViewBuilder
    private func samplePrimaryRightColumn(for sample: LibrarySample, draft: LibrarySampleEditDraft?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataValueRow(label: "Batch", value: sample.batchId)
            HStack {
                Button("修改日志") {
                    isShowingSampleChangeLog = true
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if draft != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Substrate Tags")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("comma-separated substrate tags", text: substrateTagsBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            } else if !sample.substrateTags.isEmpty {
                MetadataValueRow(label: "Substrate Tags", value: sample.substrateTags.joined(separator: ", "))
            } else {
                MetadataValueRow(label: "Substrate Tags", value: "None")
            }
        }
    }

    private var sampleDetailHeader: some View {
        LibrarySampleDetailHeaderView(
            isEditingSelectedSample: isEditingSelectedSample,
            sampleEditIsDirty: viewState.sampleEditIsDirty,
            sampleEditIsSaving: viewState.sampleEditIsSaving,
            canEditSelectedLibrarySample: viewState.canEditSelectedLibrarySample,
            sampleEditError: viewState.sampleEditError,
            sampleEditMessage: viewState.sampleEditMessage,
            onLoadGlobalManualLogs: {
                viewModel.loadLibraryGlobalManualLogs()
                isShowingGlobalManualLog = true
            },
            onLoadMetadataSyncLogs: {
                viewModel.loadLibraryMetadataSyncLogs()
                isShowingMetadataSyncLog = true
            },
            onCancelEdit: {
                viewModel.cancelEditingSelectedLibrarySample()
            },
            onSaveEdit: {
                viewModel.saveLibrarySampleEdits()
            },
            onBeginEdit: {
                viewModel.beginEditingSelectedLibrarySample()
            }
        )
    }

    private var isEditingSelectedSample: Bool {
        guard let sample = selectedSample,
              let draft = viewState.sampleEditDraft else {
            return false
        }
        return draft.sampleId == sample.id
    }

    @ViewBuilder
    private func editNumericSection(draft: LibrarySampleEditDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Numeric Tags")
                .font(.headline)
            if draft.numericValues.isEmpty {
                Text("No numeric tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.numericValues) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.key)
                            .font(.callout.weight(.semibold))
                            .frame(width: 120, alignment: .leading)
                        TextField(entry.key, text: numericValueBinding(for: entry.key))
                            .textFieldStyle(.roundedBorder)
                        if !entry.unit.isEmpty {
                            Text(entry.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editMetadataSection(draft: LibrarySampleEditDraft, availableWidth: CGFloat) -> some View {
        let fields: [DetailField] = draft.metadataValues.map { entry in
            DetailField(label: entry.key, value: entry.value, fullWidth: computationService.isLongField(entry.value))
        }
        let rows = computationService.groupedFields(fields)
        let firstColumnWidth = computationService.sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)
            if draft.metadataValues.isEmpty {
                Text("No metadata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.indices), id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    if row.count == 1 {
                        editMetadataFieldRow(row[0], fillWidth: true)
                    } else if let firstColumnWidth {
                        HStack(alignment: .top, spacing: 12) {
                            editMetadataFieldRow(row[0], fixedWidth: firstColumnWidth, fillWidth: false)
                            editMetadataFieldRow(row[1], fillWidth: true)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            editMetadataFieldRow(row[0], fillWidth: true)
                            editMetadataFieldRow(row[1], fillWidth: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editMetadataFieldRow(_ field: DetailField, fixedWidth: CGFloat? = nil, fillWidth: Bool) -> some View {
        let row = VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(field.label, text: metadataValueBinding(for: field.label), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
        if let fixedWidth {
            row
                .frame(width: fixedWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else if fillWidth {
            row
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            row
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var substrateTagsBinding: Binding<String> {
        Binding(
            get: { viewState.sampleEditDraft?.substrateTagsText ?? "" },
            set: { appState.library.updateLibrarySampleEditSubstrateTags($0) }
        )
    }

    private func numericValueBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                viewState.sampleEditDraft?
                    .numericValues
                    .first(where: { $0.key == key })?
                    .value ?? ""
            },
            set: { appState.library.updateLibrarySampleEditNumericValue(key: key, value: $0) }
        )
    }

    private func metadataValueBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                viewState.sampleEditDraft?
                    .metadataValues
                    .first(where: { $0.key == key })?
                    .value ?? ""
            },
            set: { appState.library.updateLibrarySampleEditMetadataValue(key: key, value: $0) }
        )
    }

    private var pendingSelectionChangeDialogBinding: Binding<Bool> {
        Binding(
            get: { appState.library.hasPendingSelectionChange() },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelPendingSelectionChange()
                }
            }
        )
    }

    @ViewBuilder
    private func detailSection(
        fields: [DetailField],
        availableWidth: CGFloat,
        sharedFirstColumnWidth: CGFloat?
    ) -> some View {
        let rows = computationService.groupedFields(fields)
        let sectionFirstColumnWidth = sharedFirstColumnWidth ?? computationService.sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                if row.count == 1 {
                    detailFieldRow(row[0], fillWidth: true)
                } else if let firstWidth = sectionFirstColumnWidth {
                    HStack(alignment: .top, spacing: 12) {
                        detailFieldRow(row[0], fixedWidth: firstWidth, fillWidth: false)
                        detailFieldRow(row[1], fillWidth: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        detailFieldRow(row[0], fillWidth: true)
                        detailFieldRow(row[1], fillWidth: true)
                    }
                }
            }
        }
    }

    private func alignedFirstColumnWidth(fields: [DetailField], availableWidth: CGFloat) -> CGFloat? {
        computationService.alignedFirstColumnWidth(fields: fields, availableWidth: availableWidth)
    }

    @ViewBuilder
    private func detailFieldRow(_ field: DetailField, fixedWidth: CGFloat? = nil, fillWidth: Bool) -> some View {
        let row = MetadataValueRow(label: field.label, value: field.value, monospaced: field.monospaced)
        if let fixedWidth {
            row
                .frame(width: fixedWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else if fillWidth {
            row
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            row
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func adaptiveDetailSectionSpacing(for height: CGFloat) -> CGFloat {
        computationService.adaptiveDetailSectionSpacing(for: height)
    }

    private var sampleDetailSectionTitleFont: Font {
        .title3.weight(.semibold)
    }

    @ViewBuilder
    private func pendingChangesSection(for sample: LibrarySample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(selectedChangeHighlights(for: sample)) { change in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.key)
                            .font(.caption.weight(.semibold))
                        Text(change.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow.opacity(0.45), lineWidth: 0.8)
                )
            }
        }
    }

    private func selectedChangeHighlights(for sample: LibrarySample) -> [ChangeHighlight] {
        computationService.selectedChangeHighlights(
            for: sample,
            sampleSyncChangesByID: viewState.sampleSyncChangesByID,
            batchSyncChangesByID: viewState.batchSyncChangesByID
        )
    }

    private func syncStatusSymbol(for status: LibrarySyncBatchStatus) -> String {
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

    private func syncStatusColor(for status: LibrarySyncBatchStatus) -> Color {
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

    private var previewPrefixes: [String] {
        previewDerivedData.previewPrefixes
    }

    private var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] {
        previewDerivedData.previewGroupsForSelectedPrefix
    }

    private var selectedBatchSamples: [LibrarySample] {
        previewDerivedData.selectedBatchSamples
    }

    private var selectedSample: LibrarySample? {
        resolveSelectedSample(from: selectionEntry)
    }

    private var selectedExistingSample: LibrarySample? {
        guard let prefix = viewState.selectedPrefix,
              let batchId = viewState.selectedBatchId,
              let sampleId = viewState.selectedSampleId else {
            return nil
        }
        let groups = viewState.existingGroupsByPrefix[prefix] ?? []
        let samples = groups.first(where: { $0.batchId == batchId })?.samples ?? []
        return samples.first(where: { $0.id == sampleId })
    }

    private var selectedExistingBatchSamples: [LibrarySample] {
        guard let prefix = viewState.selectedPrefix,
              let batchId = viewState.selectedBatchId else {
            return []
        }
        let groups = viewState.existingGroupsByPrefix[prefix] ?? []
        return groups.first(where: { $0.batchId == batchId })?.samples ?? []
    }

    private func presentLibraryRootPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Library Root"
        panel.message = "Select a folder for the SpinLab library store."
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.updateLibraryRoot(to: url)
        }
    }

    private func presentBackupPathPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Backup Path"
        panel.message = "Select a folder for Library backup sync."
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.updateLibraryBackupPath(to: url)
        }
    }

    private func presentSampleRegistryPanel() {
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
            viewModel.loadSampleRegistry(from: url)
        }
    }

    private func presentAuditTrailExportPanel() {
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

    private var interactionStateSnapshot: LibraryInteractionState {
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
            searchHasExecuted: searchHasExecuted
        )
    }

    private func applyRestoredInteractionState() {
        let restored = viewState.restoredInteractionState
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

        if restored.searchHasExecuted {
            executeSearch()
        } else {
            searchMatchedResults = []
            searchHasExecuted = false
        }
    }

    private func syncSelection() {
        // When the active source is .drawer, validate against existing groups
        // (not preview-derived data) so that unchanged batches stay selected.
        if viewState.activeSelectionSource == .drawer {
            syncDrawerSelection()
            return
        }
        syncBrowserSelection()
    }

    private func syncBrowserSelection() {
        let output = LibrarySelectionSync.syncBrowserSelection(
            input: .init(
                selectedPrefix: selectedPrefix,
                selectedBatchId: selectedBatchId,
                selectedSampleId: selectedSampleId
            ),
            previewGroupsByPrefix: viewState.previewGroupsByPrefix
        )
        selectedPrefix = output.selectedPrefix
        selectedBatchId = output.selectedBatchId
        selectedSampleId = output.selectedSampleId
    }

    private func syncDrawerSelection() {
        let output = LibrarySelectionSync.syncDrawerSelection(
            input: .init(
                selectedPrefix: selectedPrefix,
                selectedBatchId: selectedBatchId,
                selectedSampleId: selectedSampleId
            ),
            existingGroupsByPrefix: viewState.existingGroupsByPrefix
        )
        selectedPrefix = output.selectedPrefix
        selectedBatchId = output.selectedBatchId
        selectedSampleId = output.selectedSampleId
    }

    private var allExistingDrawerSamples: [SearchResultItem] {
        let groups = viewState.existingGroupsByPrefix
        return groups
            .flatMap { prefix, batchGroups in
                batchGroups.flatMap { group in
                    group.samples.map { sample in
                        SearchResultItem(prefix: prefix, sample: sample)
                    }
                }
            }
            .sorted {
                if $0.prefix != $1.prefix {
                    return $0.prefix < $1.prefix
                }
                if LibrarySort.compareBatch($0.sample.batchId, $1.sample.batchId) {
                    return true
                }
                if LibrarySort.compareBatch($1.sample.batchId, $0.sample.batchId) {
                    return false
                }
                return $0.sample.substrateDisplay < $1.sample.substrateDisplay
            }
    }

    private var searchThicknessValue: Double? {
        Double(searchThicknessText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var searchOxygenValue: Double? {
        Double(searchOxygenText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var searchTemperatureValue: Double? {
        Double(searchTemperatureText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var searchEnergyValue: Double? {
        Double(searchEnergyText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func clearSearchFilters() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        searchBatchIdText = ""
        searchSubstrateText = ""
        searchKeywordText = ""
        searchThicknessText = ""
        searchOxygenText = ""
        searchTemperatureText = ""
        searchEnergyText = ""
        searchMatchedResults = []
        searchHasExecuted = false
    }

    private func executeSearch() {
        searchMatchedResults = allExistingDrawerSamples.filter { result in
            computationService.matchesSearch(sample: result.sample, filters: searchFilters)
        }
        searchHasExecuted = true
    }

    private var searchFingerprint: String {
        [
            searchBatchIdText,
            searchSubstrateText,
            searchKeywordText,
            searchThicknessText,
            searchOxygenText,
            searchTemperatureText,
            searchEnergyText
        ].joined(separator: "|")
    }

    private func scheduleDebouncedSearchIfNeeded() {
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

    private func scheduleInteractionStatePersist(immediate: Bool = false) {
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

    private var searchFilters: LibrarySearchFilters {
        LibrarySearchFilters(
            batchText: searchBatchIdText,
            substrateText: searchSubstrateText,
            keywordText: searchKeywordText,
            thickness: searchThicknessValue,
            oxygen: searchOxygenValue,
            temperature: searchTemperatureValue,
            energy: searchEnergyValue
        )
    }

    private func selectSearchResultSample(_ result: SearchResultItem) {
        viewModel.selectExistingDrawer(prefix: result.prefix, batchId: result.sample.batchId, sampleId: result.sample.id)
    }

    private func isSelectedSearchResult(_ result: SearchResultItem) -> Bool {
        viewState.activeSelectionSource == .drawer
            && viewState.selectedPrefix == result.prefix
            && viewState.selectedBatchId == result.sample.batchId
            && viewState.selectedSampleId == result.sample.id
    }

    private var selectionEntry: SelectionEntry {
        SelectionEntry(
            source: viewState.activeSelectionSource,
            browserSampleId: selectedSampleId,
            drawerPrefix: viewState.selectedPrefix,
            drawerBatchId: viewState.selectedBatchId,
            drawerSampleId: viewState.selectedSampleId
        )
    }

    private func resolveSelectedSample(from entry: SelectionEntry) -> LibrarySample? {
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

    private func makeDetailSections(for sample: LibrarySample) -> SampleDetailSections {
        computationService.makeDetailSections(for: sample)
    }

    private func rebuildPreviewDerivedData() {
        let combined = computeCombinedPreviewGroupsByPrefix()
        let prefixes = computePreviewPrefixes(from: combined)
        let effectivePrefix = selectedPrefix ?? prefixes.first
        let groupsForPrefix = combined[effectivePrefix ?? ""] ?? []
        let samples = resolveSelectedBatchSamples(groups: groupsForPrefix, selectedBatchId: selectedBatchId)
        previewDerivedData = PreviewDerivedData(
            previewPrefixes: prefixes,
            previewGroupsForSelectedPrefix: groupsForPrefix,
            selectedBatchSamples: samples
        )
    }

    private func computeCombinedPreviewGroupsByPrefix() -> [String: [LibraryPreviewBatchGroup]] {
        var groups = viewState.previewGroupsByPrefix
        for (batchID, status) in viewState.batchSyncStatusByID where status != .unchanged {
            let prefix = LibrarySort.batchSortKey(batchID).prefix
            let alreadyExists = groups[prefix]?.contains(where: { $0.batchId == batchID }) == true
            if alreadyExists {
                continue
            }
            let existingSamples = viewState.existingGroupsByPrefix[prefix]?
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

    private func computePreviewPrefixes(from groups: [String: [LibraryPreviewBatchGroup]]) -> [String] {
        let configured = viewState.allowedBatchPrefixes
        let available = Array(groups.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    private func resolveSelectedBatchSamples(
        groups: [LibraryPreviewBatchGroup],
        selectedBatchId: String?
    ) -> [LibrarySample] {
        guard let selectedBatchId else {
            return []
        }
        return groups.first(where: { $0.batchId == selectedBatchId })?.samples ?? []
    }
}

private struct PreviewDerivedData {
    var previewPrefixes: [String] = []
    var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] = []
    var selectedBatchSamples: [LibrarySample] = []
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
