import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var allowedPrefixesDraft: String = ""
    @State private var selectedPrefix: String?
    @State private var selectedBatchId: String?
    @State private var selectedSampleId: String?
    @State private var isLibrarySettingsExpanded = true
    @State private var isRegistryWorkspaceExpanded = true
    @State private var isSearchWorkspaceExpanded = true
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
    @State private var viewModel = LibraryViewModel()
    private let level1HeaderFont: Font = .title2.bold()
    private let level2HeaderFont: Font = .title3.weight(.semibold)
    private let level3HeaderFont: Font = .headline

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
            syncSelection()
            viewModel.persistInteractionState(interactionStateSnapshot)
        }
        .onChange(of: viewModel.viewState.previewGroupsByPrefix) { _, _ in
            syncSelection()
            viewModel.persistInteractionState(interactionStateSnapshot)
        }
        .onChange(of: interactionStateSnapshot) { _, newValue in
            viewModel.persistInteractionState(newValue)
        }
        .onChange(of: searchFingerprint) { _, _ in
            scheduleDebouncedSearchIfNeeded()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
        .confirmationDialog(
            "Unsaved Edits",
            isPresented: pendingSelectionChangeDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Save and Switch") {
                viewModel.saveAndContinuePendingSelectionChange()
            }
            Button("Discard and Switch", role: .destructive) {
                viewModel.discardAndContinuePendingSelectionChange()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingSelectionChange()
            }
        } message: {
            Text(viewModel.viewState.pendingSelectionChangePrompt ?? "You have unsaved sample edits.")
        }
        .sheet(isPresented: $isShowingSampleChangeLog) {
            sampleChangeLogSheet
        }
        .sheet(isPresented: $isShowingGlobalManualLog) {
            globalManualLogSheet
        }
        .sheet(isPresented: $isShowingMetadataSyncLog) {
            metadataSyncLogSheet
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isLibrarySettingsExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLibrarySettingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Library Settings")
                        .font(level2HeaderFont)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isLibrarySettingsExpanded {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Registry Path (Inbox)",
                            value: viewModel.viewState.registrySourcePath ?? "Not loaded",
                            monospaced: true
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Load Registry") {
                                presentSampleRegistryPanel()
                            }
                            Button("Reload Registry") {
                                appState.reloadSampleRegistry()
                            }
                            .disabled(!appState.canReloadSampleRegistry)
                            Spacer()
                        }
                    }
                } label: {
                    Text("Registry")
                        .font(level3HeaderFont)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Library Root",
                            value: viewModel.viewState.libraryRootPath ?? "Not set",
                            monospaced: true
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Choose Library Root") {
                                presentLibraryRootPanel()
                            }
                            Button("Verify Root") {
                                viewModel.verifyLibraryRoot()
                            }
                            Button("Sync Files") {
                                viewModel.syncLibraryFromFiles()
                            }
                            .disabled(viewModel.viewState.libraryRootPath == nil)
                        }

                        if let message = viewModel.viewState.rootVerificationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let path = viewModel.viewState.rootVerificationPath {
                            MetadataValueRow(label: "Verified Path", value: path, monospaced: true)
                        }

                        HStack {
                            TextField("Allowed Prefixes (PN, PT, SL)", text: $allowedPrefixesDraft)
                                .frame(width: 190)
                                .textFieldStyle(.roundedBorder)
                            Button("Save Prefixes") {
                                viewModel.updateAllowedBatchPrefixes(from: allowedPrefixesDraft)
                            }
                        }
                        .onAppear {
                            allowedPrefixesDraft = viewModel.viewState.allowedBatchPrefixesText
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Library Root")
                        .font(level3HeaderFont)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Backup Path",
                            value: viewModel.viewState.backupPath ?? "Not set",
                            monospaced: true
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Choose Backup Path") {
                                presentBackupPathPanel()
                            }
                            Button("Sync Backup") {
                                viewModel.syncLibraryBackup()
                            }
                            .disabled(viewModel.viewState.libraryRootPath == nil || viewModel.viewState.backupPath == nil)
                        }

                        if let error = viewModel.viewState.backupError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let message = viewModel.viewState.backupMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Backup")
                        .font(level3HeaderFont)
                }
            }
        }
    }

    private var registryWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isRegistryWorkspaceExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRegistryWorkspaceExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Registry Operations")
                        .font(level2HeaderFont)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isRegistryWorkspaceExpanded {
                registryPreviewSection
                registryBrowserSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var registryPreviewSection: some View {
        GroupBox {
            registryPreviewSectionContent
        } label: {
            registryPreviewSectionLabel
        }
    }

    private var registryPreviewSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Sync Registry") {
                    viewModel.syncLibraryFromRegistry()
                }
                Button("Apply All") {
                    viewModel.applyPreparedLibrarySyncReview()
                }
                .disabled((viewModel.viewState.refreshReview?.totalChangesCount ?? 0) == 0)
                Button("Apply Selected") {
                    viewModel.applySelectedRegistryDiff(batchId: selectedBatchId)
                }
                .disabled((viewModel.viewState.refreshReview?.totalChangesCount ?? 0) == 0 || selectedBatchId == nil)
            }

            if let message = viewModel.viewState.previewMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let review = viewModel.viewState.refreshReview {
                Text("Pending sync review: \(review.newSamples.count) new, \(review.changedSamples.count) changed, \(review.removedSamples.count) removed, \(review.changedBatches.count) batch-changed, \(review.removedBatches.count) batch-removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.viewState.previewWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.viewState.previewWarnings) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(warning.severity == .error ? Color.red : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(warning.message)
                                .font(.caption)
                        }
                    }
                }
            }

            if let message = viewModel.viewState.drawerMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.viewState.drawerError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var registryPreviewSectionLabel: some View {
        HStack(spacing: 6) {
            Text("Registry Sync")
                .font(level3HeaderFont)
            if let syncStatus = viewModel.viewState.syncStatusMessage {
                Text("(\(syncStatus))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var registryBrowserSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                prefixPicker
                Divider()
                batchList
                Divider()
                sampleList
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Pending Queue")
                .font(level3HeaderFont)
        }
    }

    private var searchWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isSearchWorkspaceExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSearchWorkspaceExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Search")
                        .font(level2HeaderFont)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isSearchWorkspaceExpanded {
                GroupBox {
                    searchOperationBox
                } label: {
                    Text("Search Conditions")
                        .font(level3HeaderFont)
                }

                GroupBox {
                    searchResultBox
                } label: {
                    Text("Search Result")
                        .font(level3HeaderFont)
                }
            }
        }
    }

    private var searchOperationBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Conditions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    searchInputRow(label: "Batch ID", placeholder: "contains", text: $searchBatchIdText)
                    searchInputRow(label: "Substrate Tags", placeholder: "contains", text: $searchSubstrateText)
                    searchInputRow(label: "Global Text", placeholder: "contains", text: $searchKeywordText)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Numeric Conditions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    searchInputRow(label: "厚度", placeholder: "numeric", text: $searchThicknessText)
                    searchInputRow(label: "氧压", placeholder: "numeric", text: $searchOxygenText)
                    searchInputRow(label: "温度", placeholder: "numeric", text: $searchTemperatureText)
                    searchInputRow(label: "能量", placeholder: "numeric", text: $searchEnergyText)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 8) {
                Button("Search") {
                    executeSearch()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    clearSearchFilters()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text("Rule: non-empty fields are AND conditions; empty fields are ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchResultBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !searchHasExecuted {
                Text("Set conditions and click Search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Matched samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(searchMatchedResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if searchMatchedResults.isEmpty {
                    Text("No matched sample")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(searchMatchedResults) { result in
                                Button {
                                    selectSearchResultSample(result)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(result.sample.displayName)
                                            .font(.subheadline)
                                        Spacer()
                                        Text("\(result.prefix)/\(result.sample.batchId)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelectedSearchResult(result) ? Color.accentColor.opacity(0.15) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchInputRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var existingDrawerSampleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing Drawer Samples")
                .font(level2HeaderFont)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let prefix = appState.library.librarySelectedPrefix,
                       let batchId = appState.library.librarySelectedBatchId {
                        HStack {
                            Text("Batch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(prefix)/\(batchId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedExistingBatchSamples.isEmpty {
                            Text("No samples found in selected drawer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(selectedExistingBatchSamples) { sample in
                                        existingDrawerSampleRow(sample: sample, prefix: prefix, batchId: batchId)
                                    }
                                }
                            }
                            .frame(height: 220)
                        }
                    } else {
                        Text("Select a batch in the left Library tree to choose its samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Sample List")
                    .font(level3HeaderFont)
            }
        }
    }

    private var prefixPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prefix")
                .font(.caption)
                .foregroundStyle(.secondary)

            if previewPrefixes.isEmpty {
                Text("Load preview to select prefix")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Prefix", selection: Binding(
                    get: { selectedPrefix ?? previewPrefixes.first ?? "" },
                    set: { newValue in
                        selectedPrefix = newValue
                        selectedBatchId = previewGroupsForSelectedPrefix.first?.batchId
                        selectedSampleId = previewGroupsForSelectedPrefix.first?.samples.first?.id
                        viewModel.selectBrowserSample()
                    })
                ) {
                    ForEach(previewPrefixes, id: \.self) { prefix in
                        Text(prefix).tag(prefix)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180, alignment: .leading)
            }
        }
    }

    private var batchList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Batch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(previewGroupsForSelectedPrefix.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if previewGroupsForSelectedPrefix.isEmpty {
                Text("No batch available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(previewGroupsForSelectedPrefix) { group in
                            Button {
                                selectedBatchId = group.batchId
                                selectedSampleId = group.samples.first?.id
                                viewModel.selectBrowserSample()
                            } label: {
                                HStack {
                                    if let status = appState.library.libraryBatchSyncStatusByID[group.batchId], status != .unchanged {
                                        if status == .added {
                                            Image(systemName: "plus")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(Color.green)
                                        } else if status == .removed {
                                            Image(systemName: "minus")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(Color.red)
                                        } else {
                                            Image(systemName: syncStatusSymbol(for: status))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(syncStatusColor(for: status))
                                        }
                                    }
                                    Text(group.batchId)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(group.samples.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedBatchId == group.batchId ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var sampleList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Physical Sample")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedBatchSamples.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedBatchSamples.isEmpty {
                Text("Select a batch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(selectedBatchSamples) { sample in
                            PreviewSampleRow(
                                sample: sample,
                                isSelected: selectedSampleId == sample.id
                            ) {
                                selectedSampleId = sample.id
                                viewModel.selectBrowserSample()
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
        }
    }

    private func existingDrawerSampleRow(sample: LibrarySample, prefix: String, batchId: String) -> some View {
        Button {
            viewModel.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sample.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(sample.substrateDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(appState.library.librarySelectedSampleId == sample.id ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        if isEditingSelectedSample, let draft = appState.library.librarySampleEditDraft {
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
                                    .font(.headline)
                                detailSection(
                                    fields: sections.numericFields,
                                    availableWidth: sectionWidth,
                                    sharedFirstColumnWidth: globalFirstColumnWidth
                                )
                            }

                            Divider()
                            Text("Metadata")
                                .font(.headline)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sample Detail")
                    .font(.title2.bold())
                Spacer()
                Button("Numeric日志") {
                    viewModel.loadLibraryGlobalManualLogs()
                    isShowingGlobalManualLog = true
                }
                Button("Metadata日志") {
                    viewModel.loadLibraryMetadataSyncLogs()
                    isShowingMetadataSyncLog = true
                }
                if isEditingSelectedSample {
                    Button("Cancel") {
                        viewModel.cancelEditingSelectedLibrarySample()
                    }
                    Button("Save") {
                        viewModel.saveLibrarySampleEdits()
                    }
                    .disabled(!appState.library.librarySampleEditIsDirty || appState.library.librarySampleEditIsSaving)
                } else {
                    Button("Edit") {
                        viewModel.beginEditingSelectedLibrarySample()
                    }
                    .disabled(!appState.library.canEditSelectedLibrarySample)
                }
            }

            if let error = appState.library.librarySampleEditError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let message = appState.library.librarySampleEditMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var globalManualLogSheet: some View {
        NavigationStack {
            List {
                if appState.library.libraryGlobalManualLogs.isEmpty {
                    Text("No global manual log records.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.library.libraryGlobalManualLogs) { entry in
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.sampleId) · \(entry.fieldType): \(entry.fieldKey)")
                                    .font(.callout.weight(.semibold))
                                Text("\(displayValue(entry.oldValue)) -> \(displayValue(entry.newValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Sheet: \(entry.sheetName) · Row: \(entry.rowNumber)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                statusButton(for: entry, targetStatus: .pending, title: "Pending")
                                statusButton(for: entry, targetStatus: .done, title: "Done")
                                statusButton(for: entry, targetStatus: .ignored, title: "Ignored")
                                Spacer()
                            }
                        } header: {
                            Text("\(entry.batchId) · \(formattedLogTimestamp(entry.timestamp)) · \(entry.status.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Numeric日志")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        viewModel.loadLibraryGlobalManualLogs()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isShowingGlobalManualLog = false
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = appState.library.libraryGlobalManualLogError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let message = appState.library.libraryGlobalManualLogMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func statusButton(for entry: LibraryManualUpdateLogEntry, targetStatus: LibraryManualLogStatus, title: String) -> some View {
        if targetStatus == entry.status {
            Button(title) {
                viewModel.markLibraryGlobalManualLogStatus(rowIndex: entry.rowIndex, status: targetStatus)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        } else {
            Button(title) {
                viewModel.markLibraryGlobalManualLogStatus(rowIndex: entry.rowIndex, status: targetStatus)
            }
            .buttonStyle(.bordered)
        }
    }

    private func formattedLogTimestamp(_ timestamp: Date?) -> String {
        guard let timestamp else {
            return "Unknown time"
        }
        return Self.logDateTimeFormatter.string(from: timestamp)
    }

    @ViewBuilder
    private var metadataSyncLogSheet: some View {
        let entries = appState.library.libraryMetadataSyncLogs
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No metadata sync log records.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, content: metadataLogEntrySection)
                }
            }
            .navigationTitle("Metadata同步日志")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        viewModel.loadLibraryMetadataSyncLogs()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isShowingMetadataSyncLog = false
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = appState.library.libraryMetadataSyncLogError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let message = appState.library.libraryMetadataSyncLogMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func metadataLogEntrySection(_ entry: LibraryMetadataSyncLogEntry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.sampleId) · \(entry.columnName)")
                    .font(.callout.weight(.semibold))
                Text("\(displayValue(entry.oldValue)) -> \(displayValue(entry.newValue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sheet: \(entry.sheetName) · Row: \(entry.rowNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(metadataResultText(for: entry))
                    .font(.caption2)
                    .foregroundStyle(entry.writeResult.lowercased() == "success" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
            }
        } header: {
            Text("\(entry.batchId) · \(formattedLogTimestamp(entry.timestamp))")
        }
    }

    private func metadataResultText(for entry: LibraryMetadataSyncLogEntry) -> String {
        if let error = entry.errorMessage, !error.isEmpty {
            return "Result: \(entry.writeResult) · \(error)"
        }
        return "Result: \(entry.writeResult)"
    }

    private var isEditingSelectedSample: Bool {
        guard let sample = selectedSample,
              let draft = appState.library.librarySampleEditDraft else {
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
            DetailField(label: entry.key, value: entry.value, fullWidth: isLongField(entry.value))
        }
        let rows = groupedFields(fields)
        let firstColumnWidth = sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
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
            get: { appState.library.librarySampleEditDraft?.substrateTagsText ?? "" },
            set: { appState.updateLibrarySampleEditSubstrateTags($0) }
        )
    }

    private func numericValueBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                appState.library.librarySampleEditDraft?
                    .numericValues
                    .first(where: { $0.key == key })?
                    .value ?? ""
            },
            set: { appState.updateLibrarySampleEditNumericValue(key: key, value: $0) }
        )
    }

    private func metadataValueBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                appState.library.librarySampleEditDraft?
                    .metadataValues
                    .first(where: { $0.key == key })?
                    .value ?? ""
            },
            set: { appState.updateLibrarySampleEditMetadataValue(key: key, value: $0) }
        )
    }

    private var pendingSelectionChangeDialogBinding: Binding<Bool> {
        Binding(
            get: { appState.hasPendingLibrarySelectionChange() },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelPendingSelectionChange()
                }
            }
        )
    }

    @ViewBuilder
    private var sampleChangeLogSheet: some View {
        NavigationStack {
            if let sample = selectedSample {
                let entries = appState.librarySampleChangeLog(for: sample)
                List {
                    if entries.isEmpty {
                        Text("No change log records for this sample.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            Section {
                                ForEach(entry.changes, id: \.self) { change in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.key)
                                            .font(.caption.weight(.semibold))
                                        Text("\(displayValue(change.oldValue)) -> \(displayValue(change.newValue))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } header: {
                                Text("\(Self.logDateTimeFormatter.string(from: entry.changedAt)) · \(entry.source)")
                            }
                        }
                    }
                }
                .navigationTitle("\(sample.batchId) · \(sample.substrateDisplay)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isShowingSampleChangeLog = false
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Sample Selected",
                    systemImage: "tray",
                    description: Text("Select a sample to view change log.")
                )
            }
        }
        .frame(minWidth: 540, minHeight: 420)
    }

    @ViewBuilder
    private func detailSection(
        fields: [DetailField],
        availableWidth: CGFloat,
        sharedFirstColumnWidth: CGFloat?
    ) -> some View {
        let rows = groupedFields(fields)
        let sectionFirstColumnWidth = sharedFirstColumnWidth ?? sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
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
        let rows = groupedFields(fields)
        return sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
    }

    private func groupedFields(_ fields: [DetailField]) -> [[DetailField]] {
        var rows: [[DetailField]] = []
        var pending: DetailField?
        for field in fields {
            if field.fullWidth {
                if let pendingField = pending {
                    rows.append([pendingField])
                    pending = nil
                }
                rows.append([field])
                continue
            }
            if let pendingField = pending {
                rows.append([pendingField, field])
                pending = nil
            } else {
                pending = field
            }
        }
        if let pendingField = pending {
            rows.append([pendingField])
        }
        return rows
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

    private func sectionFirstColumnWidth(rows: [[DetailField]], availableWidth: CGFloat) -> CGFloat? {
        twoColumnWidths(rows: rows, availableWidth: availableWidth)?.first
    }

    private func twoColumnWidths(rows: [[DetailField]], availableWidth: CGFloat) -> (first: CGFloat, second: CGFloat)? {
        let spacing: CGFloat = 12
        let minColumnWidth: CGFloat = 170
        let firstColumnMaxWidth: CGFloat = 420

        let pairRows = rows.filter { $0.count == 2 }
        guard !pairRows.isEmpty else {
            return nil
        }

        // Character-based redundancy: reserve extra breathing room equivalent to 5 chars.
        let redundancyInChars: CGFloat = 5
        let averageCharWidth = estimatedTextWidth("MMMMM", font: .systemFont(ofSize: NSFont.systemFontSize)) / 5
        let redundancyWidth = max(averageCharWidth * redundancyInChars, 24)

        let firstContentNeeded = pairRows
            .map { estimatedFieldWidth($0[0]) }
            .max() ?? minColumnWidth
        let secondContentNeeded = pairRows
            .map { estimatedFieldWidth($0[1]) }
            .max() ?? minColumnWidth

        let firstBase = max(firstContentNeeded + redundancyWidth, minColumnWidth)
        let secondBase = max(secondContentNeeded + redundancyWidth, minColumnWidth)
        let totalBase = firstBase + secondBase + spacing

        // If the total width is insufficient, fallback to single-column rendering.
        guard availableWidth >= totalBase else {
            return nil
        }

        let extra = availableWidth - totalBase
        var first = firstBase + extra / 2
        var second = secondBase + extra / 2

        // Cap the first column in wide layouts to avoid visual imbalance.
        if first > firstColumnMaxWidth {
            let overflow = first - firstColumnMaxWidth
            first = firstColumnMaxWidth
            second += overflow
        }

        // Keep the second column at least minimally readable.
        if second < minColumnWidth {
            let needed = minColumnWidth - second
            first -= needed
            second = minColumnWidth
        }

        let maxFirstGivenAvailable = availableWidth - minColumnWidth - spacing
        first = min(first, maxFirstGivenAvailable)
        second = availableWidth - first - spacing
        guard first >= minColumnWidth, second >= minColumnWidth else {
            return nil
        }
        return (first: first, second: second)
    }

    private func estimatedFieldWidth(_ field: DetailField) -> CGFloat {
        let labelWidth = estimatedTextWidth(field.label, font: .systemFont(ofSize: NSFont.smallSystemFontSize))
        let valueFont: NSFont = field.monospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        let valueWidth = estimatedTextWidth(field.value, font: valueFont)
        let clampedValueWidth = min(max(valueWidth, 80), 360)
        return max(labelWidth, clampedValueWidth)
    }

    private func estimatedTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let sample = text.isEmpty ? " " : text
        let singleLine = sample
            .split(separator: "\n")
            .map(String.init)
            .max(by: { $0.count < $1.count }) ?? sample
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((singleLine as NSString).size(withAttributes: attributes).width)
    }

    private func isLongField(_ value: String) -> Bool {
        if value.count > 68 {
            return true
        }
        let markers = ["/", "\\", "\n", "\t"]
        return markers.contains { value.contains($0) } && value.count > 34
    }

    private func orderedNumericTagKeys(for sample: LibrarySample) -> [String] {
        let preferred = ["厚度", "氧压", "温度", "能量", "电压", "磁场", "电阻"]
        var keys: [String] = []
        for key in preferred where sample.numericDisplay[key] != nil {
            keys.append(key)
        }
        for key in sample.numericDisplay.keys where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private func adaptiveDetailSectionSpacing(for height: CGFloat) -> CGFloat {
        let base: CGFloat = 12
        let extraHeight = max(height - 720, 0)
        // Spread sections out on tall windows while keeping dense layout on normal heights.
        return min(base + extraHeight / 28, 26)
    }

    private static let logDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

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
        let sampleChanges = appState.library.librarySampleSyncChangesByID[sample.id] ?? []
        let batchChanges = appState.library.libraryBatchSyncChangesByID[sample.batchId] ?? []
        let sampleHighlights = sampleChanges.map {
            ChangeHighlight(key: $0.key, description: "\(displayValue($0.oldValue)) -> \(displayValue($0.newValue))")
        }
        let batchHighlights = batchChanges.map {
            ChangeHighlight(key: "Batch.\($0.key)", description: "\(displayValue($0.oldValue)) -> \(displayValue($0.newValue))")
        }
        return sampleHighlights + batchHighlights
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : "∅"
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
        let configured = viewModel.viewState.allowedBatchPrefixes
        let available = Array(combinedPreviewGroupsByPrefix.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    private var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] {
        let prefix = selectedPrefix ?? previewPrefixes.first
        return combinedPreviewGroupsByPrefix[prefix ?? ""] ?? []
    }

    private var combinedPreviewGroupsByPrefix: [String: [LibraryPreviewBatchGroup]] {
        var groups = viewModel.viewState.previewGroupsByPrefix
        for (batchID, status) in viewModel.viewState.batchSyncStatusByID where status != .unchanged {
            let prefix = LibrarySort.batchSortKey(batchID).prefix
            let alreadyExists = groups[prefix]?.contains(where: { $0.batchId == batchID }) == true
            if alreadyExists {
                continue
            }
            let existingSamples = viewModel.viewState.existingGroupsByPrefix[prefix]?
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

    private var selectedBatchSamples: [LibrarySample] {
        guard let batchId = selectedBatchId else {
            return []
        }
        return previewGroupsForSelectedPrefix.first(where: { $0.batchId == batchId })?.samples ?? []
    }

    private var selectedSample: LibrarySample? {
        resolveSelectedSample(from: selectionEntry)
    }

    private var selectedExistingSample: LibrarySample? {
        guard let prefix = appState.library.librarySelectedPrefix,
              let batchId = appState.library.librarySelectedBatchId,
              let sampleId = appState.library.librarySelectedSampleId else {
            return nil
        }
        let groups = appState.library.libraryExistingGroups[prefix] ?? []
        let samples = groups.first(where: { $0.batchId == batchId })?.samples ?? []
        return samples.first(where: { $0.id == sampleId })
    }

    private var selectedExistingBatchSamples: [LibrarySample] {
        guard let prefix = appState.library.librarySelectedPrefix,
              let batchId = appState.library.librarySelectedBatchId else {
            return []
        }
        let groups = appState.library.libraryExistingGroups[prefix] ?? []
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
            appState.loadSampleRegistry(from: url)
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
        let restored = viewModel.viewState.restoredInteractionState
        selectedPrefix = restored.selectedPrefix
        selectedBatchId = restored.selectedBatchId
        selectedSampleId = restored.selectedSampleId
        isLibrarySettingsExpanded = restored.isLibrarySettingsExpanded
        isRegistryWorkspaceExpanded = restored.isRegistryWorkspaceExpanded
        isSearchWorkspaceExpanded = restored.isSearchWorkspaceExpanded
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
        if selectedPrefix == nil || !previewPrefixes.contains(selectedPrefix ?? "") {
            selectedPrefix = previewPrefixes.first
        }
        if let firstBatch = previewGroupsForSelectedPrefix.first?.batchId {
            if selectedBatchId == nil || previewGroupsForSelectedPrefix.first(where: { $0.batchId == selectedBatchId }) == nil {
                selectedBatchId = firstBatch
            }
        } else {
            selectedBatchId = nil
            selectedSampleId = nil
            return
        }
        if selectedSampleId == nil || !selectedBatchSamples.contains(where: { $0.id == selectedSampleId }) {
            selectedSampleId = selectedBatchSamples.first?.id
        }
    }

    private var allExistingDrawerSamples: [SearchResultItem] {
        let groups = viewModel.viewState.existingGroupsByPrefix
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
            matchesSearch(result.sample)
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

    private func matchesSearch(_ sample: LibrarySample) -> Bool {
        let batchText = searchBatchIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        let substrateText = searchSubstrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordText = searchKeywordText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !batchText.isEmpty,
           !sample.batchId.localizedCaseInsensitiveContains(batchText) {
            return false
        }

        if !substrateText.isEmpty {
            let queryTags = normalizedSubstrateQueryTags(from: substrateText)
            let sampleTags = Set(
                ([sample.substrateDisplay] + sample.substrateTags)
                    .map(normalizedSubstrateTag)
                    .filter { !$0.isEmpty }
            )
            let matched = queryTags.contains { sampleTags.contains($0) }
            if !matched {
                return false
            }
        }

        if !keywordText.isEmpty {
            let keywordHaystack = [
                sample.batchId,
                sample.displayName,
                sample.id,
                sample.substrateDisplay,
                sample.substrateRaw,
                sample.substrateTags.joined(separator: " "),
                sample.metadata.values.joined(separator: " ")
            ].joined(separator: " ")
            if !keywordHaystack.localizedCaseInsensitiveContains(keywordText) {
                return false
            }
        }

        if let thickness = searchThicknessValue,
           !numericEquals(sample.numericTags["厚度"], thickness) {
            return false
        }

        if let oxygen = searchOxygenValue,
           !numericEquals(sample.numericTags["氧压"], oxygen) {
            return false
        }

        if let temperature = searchTemperatureValue,
           !numericEquals(sample.numericTags["温度"], temperature) {
            return false
        }

        if let energy = searchEnergyValue,
           !numericEquals(sample.numericTags["能量"], energy) {
            return false
        }

        return true
    }

    private func numericEquals(_ source: Double?, _ expected: Double) -> Bool {
        guard let source else {
            return false
        }
        return abs(source - expected) < 1e-9
    }

    private func normalizedSubstrateQueryTags(from input: String) -> [String] {
        let normalizedInput = input
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
        let parts = normalizedInput
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { normalizedSubstrateTag(String($0)) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            let single = normalizedSubstrateTag(normalizedInput)
            return single.isEmpty ? [] : [single]
        }
        return parts
    }

    private func normalizedSubstrateTag(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        value = value
            .replacingOccurrences(of: " (", with: "(")
            .replacingOccurrences(of: ") ", with: ")")
        value = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return value
    }

    private func selectSearchResultSample(_ result: SearchResultItem) {
        viewModel.selectExistingDrawer(prefix: result.prefix, batchId: result.sample.batchId, sampleId: result.sample.id)
    }

    private func isSelectedSearchResult(_ result: SearchResultItem) -> Bool {
        appState.library.libraryActiveSelectionSource == .drawer
            && appState.library.librarySelectedPrefix == result.prefix
            && appState.library.librarySelectedBatchId == result.sample.batchId
            && appState.library.librarySelectedSampleId == result.sample.id
    }

    private var selectionEntry: SelectionEntry {
        SelectionEntry(
            source: appState.library.libraryActiveSelectionSource,
            browserSampleId: selectedSampleId,
            drawerPrefix: appState.library.librarySelectedPrefix,
            drawerBatchId: appState.library.librarySelectedBatchId,
            drawerSampleId: appState.library.librarySelectedSampleId
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
        let sampleFields: [DetailField] = [
            DetailField(label: "Sample", value: sample.displayName, fullWidth: isLongField(sample.displayName)),
            DetailField(label: "Batch", value: sample.batchId),
            DetailField(label: "Sample Key", value: sample.id, monospaced: true, fullWidth: true),
            DetailField(label: "Substrate", value: sample.substrateDisplay)
        ]
        let substrateFields: [DetailField] = sample.substrateTags.isEmpty
            ? []
            : [DetailField(label: "Substrate Tags", value: sample.substrateTags.joined(separator: ", "), fullWidth: true)]
        let numericFields: [DetailField] = orderedNumericTagKeys(for: sample).map { key in
            DetailField(label: key, value: sample.numericDisplay[key] ?? "")
        }
        let metadataFields: [DetailField] = sample.orderedMetadata.map { item in
            DetailField(label: item.key, value: item.value, fullWidth: isLongField(item.value))
        }
        return SampleDetailSections(
            sampleFields: sampleFields,
            substrateFields: substrateFields,
            numericFields: numericFields,
            metadataFields: metadataFields
        )
    }
}

private struct SelectionEntry {
    let source: LibrarySelectionSource
    let browserSampleId: String?
    let drawerPrefix: String?
    let drawerBatchId: String?
    let drawerSampleId: String?
}

private struct SearchResultItem: Identifiable, Hashable {
    var id: String { "\(prefix)|\(sample.id)" }
    let prefix: String
    let sample: LibrarySample
}

private struct SampleDetailSections {
    let sampleFields: [DetailField]
    let substrateFields: [DetailField]
    let numericFields: [DetailField]
    let metadataFields: [DetailField]

    var allFields: [DetailField] {
        sampleFields + substrateFields + numericFields + metadataFields
    }
}

private struct ChangeHighlight: Identifiable, Hashable {
    var id: String { "\(key)|\(description)" }
    let key: String
    let description: String
}

private struct DetailField: Hashable {
    let label: String
    let value: String
    var monospaced: Bool = false
    var fullWidth: Bool = false
}

private struct PreviewSampleRow: View {
    let sample: LibrarySample
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sample.substrateDisplay)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
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
