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
    @State var searchMatchedResults: [SearchResultItem] = []
    @State var searchDebounceTask: Task<Void, Never>?
    @State var isWebLibraryPublishDetailsExpanded = false
    let computationService = LibraryViewComputationService()

    // Persisted interaction fields live in LibraryWorkspaceState (stable owner);
    // forwarded here so the page code reads/writes them unchanged.
    var isLibrarySettingsExpanded: Bool {
        get { state.isLibrarySettingsExpanded }
        nonmutating set { state.isLibrarySettingsExpanded = newValue }
    }
    var isRegistryWorkspaceExpanded: Bool {
        get { state.isRegistryWorkspaceExpanded }
        nonmutating set { state.isRegistryWorkspaceExpanded = newValue }
    }
    var isSearchWorkspaceExpanded: Bool {
        get { state.isSearchWorkspaceExpanded }
        nonmutating set { state.isSearchWorkspaceExpanded = newValue }
    }
    var searchBatchIdText: String {
        get { state.searchBatchIdText }
        nonmutating set { state.searchBatchIdText = newValue }
    }
    var searchSubstrateText: String {
        get { state.searchSubstrateText }
        nonmutating set { state.searchSubstrateText = newValue }
    }
    var searchKeywordText: String {
        get { state.searchKeywordText }
        nonmutating set { state.searchKeywordText = newValue }
    }
    var searchThicknessText: String {
        get { state.searchThicknessText }
        nonmutating set { state.searchThicknessText = newValue }
    }
    var searchOxygenText: String {
        get { state.searchOxygenText }
        nonmutating set { state.searchOxygenText = newValue }
    }
    var searchTemperatureText: String {
        get { state.searchTemperatureText }
        nonmutating set { state.searchTemperatureText = newValue }
    }
    var searchEnergyText: String {
        get { state.searchEnergyText }
        nonmutating set { state.searchEnergyText = newValue }
    }
    var searchThicknessToleranceText: String {
        get { state.searchThicknessToleranceText }
        nonmutating set { state.searchThicknessToleranceText = newValue }
    }
    var searchOxygenToleranceText: String {
        get { state.searchOxygenToleranceText }
        nonmutating set { state.searchOxygenToleranceText = newValue }
    }
    var searchTemperatureToleranceText: String {
        get { state.searchTemperatureToleranceText }
        nonmutating set { state.searchTemperatureToleranceText = newValue }
    }
    var searchEnergyToleranceText: String {
        get { state.searchEnergyToleranceText }
        nonmutating set { state.searchEnergyToleranceText = newValue }
    }
    var searchHasExecuted: Bool {
        get { state.searchHasExecuted }
        nonmutating set { state.searchHasExecuted = newValue }
    }

    var body: some View {
        librarySettingsColumn
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Search results are page-local: rebuild them when the page mounts
            // with a restored "search executed" flag. Lifecycle, selection sync,
            // projection loading, persistence and global dialogs live in
            // LibraryWorkspaceHost, not here.
            if state.searchHasExecuted && searchMatchedResults.isEmpty {
                executeSearch()
            }
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
            isExpanded: $state.isLibrarySettingsExpanded,
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
            isExpanded: $state.isRegistryWorkspaceExpanded,
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
                let groupsForNew = state.computeCombinedPreviewGroupsByPrefix(appState: appState)[newValue] ?? []
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
}

// MARK: - Search

extension LibraryPrimaryView {
    var searchWorkspaceSection: some View {
        SearchWorkspaceSectionView(
            isExpanded: $state.isSearchWorkspaceExpanded,
            batchIdText: $state.searchBatchIdText,
            substrateText: $state.searchSubstrateText,
            keywordText: $state.searchKeywordText,
            thicknessText: $state.searchThicknessText,
            oxygenText: $state.searchOxygenText,
            temperatureText: $state.searchTemperatureText,
            energyText: $state.searchEnergyText,
            thicknessToleranceText: $state.searchThicknessToleranceText,
            oxygenToleranceText: $state.searchOxygenToleranceText,
            temperatureToleranceText: $state.searchTemperatureToleranceText,
            energyToleranceText: $state.searchEnergyToleranceText,
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
