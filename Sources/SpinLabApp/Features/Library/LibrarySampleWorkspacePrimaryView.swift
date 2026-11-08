import SwiftUI

/// Primary pane of the Sample Workspace: Batch header, adaptive Sample
/// selector and the selected Sample's plots grid. Contains no
/// Library Management / Registry / Search / Publish controls.
///
/// Sample switching only ever goes through `LibraryViewModel.selectExistingDrawer`
/// (the guarded navigation transaction); this view never writes selection.
@MainActor
struct LibrarySampleWorkspacePrimaryView: View {
    @Environment(SpinLabAppState.self) var appState
    @Bindable var state: LibraryWorkspaceState

    @State private var menuQuery = ""
    @State private var isMenuPresented = false
    @State private var isShowingCreateSampleSheet = false

    private var lib: LibraryFeatureStore { appState.library }

    /// Samples of the route's Batch only; a transient mismatch between the route
    /// and the Drawer selection shows nothing rather than another batch's samples.
    private var routeMatchesDrawer: Bool {
        guard let id = batchIdentity else { return false }
        return lib.librarySelectedPrefix == id.prefix && lib.librarySelectedBatchId == id.batchId
    }
    private var batchSamples: [LibrarySample] {
        routeMatchesDrawer ? state.selectedExistingBatchSamples(appState) : []
    }
    private var selector: LibrarySampleSelectorModel { LibrarySampleSelectorModel(samples: batchSamples) }

    private var batchIdentity: (prefix: String, batchId: String)? {
        guard case let .sampleWorkspace(prefix, batchId) = lib.currentRoute else { return nil }
        return (prefix, batchId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            header
            if routeMatchesDrawer,
               let sample = state.selectedExistingSample(appState),
               selector.isValidSelection(sample.id) {
                selectedSampleBody(sample)
            } else {
                emptyState
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SampleWorkspace.Primary")
        .animation(nil, value: lib.librarySelectedSampleId)
        .onChange(of: state.selectedExistingSample(appState)?.id) { _, newId in
            if newId == nil { lib.plotsOverviewItems = [] }
        }
        .onDisappear { lib.plotsOverviewItems = [] }
        .sheet(isPresented: $isShowingCreateSampleSheet) {
            CreateNativeSampleSheetView(
                isPresented: $isShowingCreateSampleSheet,
                initialBatchId: batchIdentity?.batchId
            )
        }
    }

    // MARK: Header + selector

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(batchIdentity.map { "\($0.prefix) · \($0.batchId)" } ?? "Sample Workspace")
                    .font(AppFontScale.sectionTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("SampleWorkspace.BatchTitle")
                Text("\(batchSamples.count) sample\(batchSamples.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isShowingCreateSampleSheet = true
                } label: {
                    Label("New Sample", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("SampleWorkspace.NewSampleButton")
            }
            selectorView
        }
    }

    @ViewBuilder
    private var selectorView: some View {
        let model = selector
        switch model.style {
        case .empty:
            EmptyView()
        case .single:
            if let option = model.options.first {
                HStack(spacing: 6) {
                    Text(option.title).font(.headline).lineLimit(1).truncationMode(.middle)
                    if let sub = option.subtitle {
                        Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("SampleWorkspace.SingleSampleTitle")
            }
        case .chips:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.options) { option in
                        chip(option)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("SampleWorkspace.SampleChips")
        case .menu:
            menuSelector(model)
        }
    }

    private func isSelected(_ option: LibrarySampleSelectorModel.Option) -> Bool {
        lib.librarySelectedSampleId == option.id
    }

    private func chip(_ option: LibrarySampleSelectorModel.Option) -> some View {
        Button {
            select(option.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(option.title).font(.callout).lineLimit(1).truncationMode(.middle)
                if let sub = option.subtitle {
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected(option) ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected(option) ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.subtitle.map { "\(option.title) — \($0)" } ?? option.title)
        .accessibilityLabel(option.title)
        .accessibilityIdentifier("SampleWorkspace.SampleChip.\(option.id)")
        .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
    }

    private func menuSelector(_ model: LibrarySampleSelectorModel) -> some View {
        let current = model.options.first(where: isSelected)
        return Button {
            menuQuery = ""
            isMenuPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(current?.title ?? "Choose a sample")
                    .lineLimit(1).truncationMode(.middle)
                if let sub = current?.subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .frame(maxWidth: 420, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SampleWorkspace.SampleMenuButton")
        .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Search \(model.options.count) samples", text: $menuQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("SampleWorkspace.SampleMenuSearch")
                let rows = model.filtered(by: menuQuery)
                if rows.isEmpty {
                    Text("No matching sample").font(.caption).foregroundStyle(.secondary).padding(6)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(rows) { option in
                                Button {
                                    isMenuPresented = false
                                    select(option.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(option.title).lineLimit(1).truncationMode(.middle)
                                            if let sub = option.subtitle {
                                                Text(sub).font(.caption2).foregroundStyle(.secondary)
                                                    .lineLimit(1).truncationMode(.middle)
                                            }
                                        }
                                        Spacer()
                                        if isSelected(option) { Image(systemName: "checkmark") }
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("SampleWorkspace.SampleMenuRow.\(option.id)")
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            .padding(10)
            .frame(width: 320)
        }
    }

    /// Guarded navigation transaction (PR 1): dirty drafts prompt, Cancel/Save
    /// failure leave the selection untouched.
    private func select(_ sampleId: String) {
        guard let identity = batchIdentity, sampleId != lib.librarySelectedSampleId else { return }
        state.viewModel.selectExistingDrawer(prefix: identity.prefix, batchId: identity.batchId, sampleId: sampleId)
    }

    // MARK: Body

    @ViewBuilder
    private func selectedSampleBody(_ sample: LibrarySample) -> some View {
        Divider()
        let canDelete = lib.canMutateLibraryDetailSelection && lib.librarySampleEditDraft == nil
        SamplePlotsOverviewSection(
            sampleKey: sample.id,
            sampleDisplayName: sample.displayName,
            libraryRootURL: lib.librarySettings.rootPath.map { URL(fileURLWithPath: $0) },
            workbenchResults: lib.workbenchResults,
            measurementPlotIndex: lib.measurementPlotIndex,
            workflowDefinitions: appState.workflowDefinitions,
            canDeleteChart: canDelete,
            onDeleteChart: canDelete ? { ref in lib.deleteWorkbenchResult(ref) } : nil,
            onItemsLoaded: { items in lib.plotsOverviewItems = items }
        )
        // A new identity per Sample resets sheets, pending deletes and cached
        // grid state so nothing from the previous Sample can linger.
        .id(sample.id)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "tray").font(.title2).foregroundStyle(.tertiary)
            Text(batchSamples.isEmpty ? "No samples in this batch" : "No sample selected")
                .font(.headline)
            Text(batchSamples.isEmpty
                 ? "This batch has no archived samples."
                 : "Choose a sample above to see its plots.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                isShowingCreateSampleSheet = true
            } label: {
                Label("New Sample", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
            .accessibilityIdentifier("SampleWorkspace.EmptyStateCreateButton")
        }
        .padding(.top, 24)
        .accessibilityIdentifier("SampleWorkspace.EmptyState")
    }
}
