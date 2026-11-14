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
    var mode: Mode = .management

    /// Library Management only. The Sample Workspace has its own page
    /// (`LibrarySampleWorkspacePrimaryView`).
    enum Mode {
        case management
    }

    @State var allowedPrefixesDraft: String = ""
    @State var isWebLibraryPublishDetailsExpanded = false
    @State var isShowingCreateSampleSheet = false

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

    var body: some View {
        librarySettingsColumn
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Lifecycle, selection sync, projection loading, persistence and global
        // dialogs live in LibraryWorkspaceHost, not here.
        .onChange(of: lib.webLibraryPublishState.presentationRevision) { _, _ in
            isWebLibraryPublishDetailsExpanded = false
        }
        .sheet(isPresented: $isShowingCreateSampleSheet) {
            CreateNativeSampleSheetView(
                isPresented: $isShowingCreateSampleSheet,
                initialBatchId: selectedBatchId
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
            Button {
                isShowingCreateSampleSheet = true
            } label: {
                Label("New Sample", systemImage: "plus")
            }
            .font(.callout)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Library.NewSampleButton")
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
                appState.library.syncLibraryFromFiles(offerRecovery: true)
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
                markManagementPreview()
                state.viewModel.selectBrowserSample()
            },
            onSelectBatch: { group in
                browserSelectedBatchId = group.batchId
                browserSelectedSampleId = group.samples.first?.id
                markManagementPreview()
                state.viewModel.selectBrowserSample()
            },
            onSelectSample: { sample in
                browserSelectedSampleId = sample.id
                markManagementPreview()
                state.viewModel.selectBrowserSample()
            },
            onSyncRegistry: {
                state.viewModel.syncLibraryFromRegistry()
                appState.pickUpPhoneSamples(manual: true)
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

    /// An explicit Registry Preview pick in Management turns the right column
    /// into the read-only sample preview.
    func markManagementPreview() {
        if mode == .management {
            appState.library.isManagementPreviewActive = true
        }
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
            LibrarySampleWorkspacePrimaryView(state: state)
            LibraryDetailView(state: state)
        }
            .environment(appState)
            .frame(width: 1200, height: 760)
    }
}
#endif
