import AppKit
import Combine
import SwiftUI

/// Plots-first grid shown in the Sample Workspace's Primary pane (PR 3). It was
/// previously a horizontal strip in `LibraryDetailView`.
/// Displays every experimental plot associated with the selected sample.
///
/// Features:
/// - Direct read of sample's `results_index.json` via `SamplePlotsOverviewService`
/// - Surfacing 7 historical unlinked charts and any multi-sample comparison charts
/// - Instant first-plot preview without vertical scrolling on standard window heights
/// - Missing PNG detection with explicit placeholder cards and preserved metadata
/// - Clickable thumbnails opening full provenance sheet (`SamplePlotsGallerySheet`)
/// - Double-click opening full-resolution pan/zoom canvas (`WorkflowGalleryFullScreenView`)
/// - "View All" gallery entrance ensuring full-width exploration even in narrow columns
/// - Bounded, lazy thumbnail caching via `WorkflowThumbnailCache`
struct SamplePlotsOverviewSection: View {
    let sampleKey: String
    let sampleDisplayName: String
    let libraryRootURL: URL?
    let workbenchResults: WorkbenchResultsIndex?
    let measurementPlotIndex: MeasurementPlotIndex?
    let workflowDefinitions: [WorkflowDefinition]
    let canDeleteChart: Bool
    let onDeleteChart: ((WorkbenchResultReference) -> Void)?
    var onItemsLoaded: (([WorkflowGalleryItem]) -> Void)? = nil

    @State private var items: [WorkflowGalleryItem] = []
    @State private var isShowingGallerySheet: Bool = false
    @State private var selectedItemForSheet: WorkflowGalleryItem? = nil
    @State private var fullScreenItem: WorkflowGalleryItem? = nil
    @State private var pendingDeleteRef: WorkbenchResultReference? = nil
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var lastKnownDiskModDate: Date? = nil
    @State private var loadIssue: LoadIssue? = nil

    /// Why the grid is empty when it is not simply "no plots saved".
    enum LoadIssue: Equatable {
        case noLibraryRoot
        case libraryRootMissing
        case indexUnreadable
    }

    private let diskPollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let cardWidth: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            sectionHeader

            // Content Area
            if items.isEmpty {
                emptyStateView
            } else {
                plotsGridView
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SamplePlotsOverview.Section")
        .onAppear {
            refreshItems()
            checkDiskUpdates()
        }
        .onReceive(diskPollTimer) { _ in
            checkDiskUpdates()
        }
        .onChange(of: sampleKey) { _, _ in
            lastKnownDiskModDate = nil
            refreshItems()
            checkDiskUpdates()
        }
        .onChange(of: workbenchResults) { _, _ in
            if let root = libraryRootURL {
                SamplePlotsOverviewService.invalidateMultiSampleCache(for: root)
            }
            refreshItems()
        }
        .onChange(of: measurementPlotIndex) { _, _ in
            refreshItems()
        }
        .onChange(of: libraryRootURL) { _, _ in
            refreshItems()
        }
        .sheet(isPresented: $isShowingGallerySheet) {
            SamplePlotsGallerySheet(
                sampleKey: sampleKey,
                sampleDisplayName: sampleDisplayName,
                items: items,
                initialSelectedItem: selectedItemForSheet ?? items.first,
                libraryRootURL: libraryRootURL,
                canDeleteChart: canDeleteChart,
                onDeleteChart: onDeleteChart,
                onDismiss: {
                    isShowingGallerySheet = false
                    selectedItemForSheet = nil
                }
            )
        }
        .sheet(item: $fullScreenItem) { item in
            if let root = libraryRootURL {
                WorkflowGalleryFullScreenView(
                    item: item,
                    libraryRootURL: root,
                    onDismiss: { fullScreenItem = nil }
                )
            }
        }
        .confirmationDialog(
            "Delete Chart?",
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Chart", role: .destructive) {
                if let ref = pendingDeleteRef {
                    onDeleteChart?(ref)
                    if let root = libraryRootURL {
                        SamplePlotsOverviewService.invalidateMultiSampleCache(for: root)
                    }
                    refreshItems()
                }
                pendingDeleteRef = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRef = nil
            }
        } message: {
            Text("This will remove the chart from active views and archive its image and manifest for recovery.")
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Plots")
                .font(AppFontScale.sectionHeader)

            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("SamplePlotsOverview.BadgeCount")
                    .accessibilityValue("\(items.count)")
            }

            Spacer()

            if !items.isEmpty {
                Button {
                    selectedItemForSheet = items.first
                    isShowingGallerySheet = true
                } label: {
                    HStack(spacing: 3) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Browse all \(items.count) plots for this sample in full gallery")
                .accessibilityIdentifier("SamplePlotsOverview.ViewAllButton")
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        let (icon, title, detail): (String, String, String) = {
            switch loadIssue {
            case .noLibraryRoot:
                return ("externaldrive.badge.xmark", "No Library root selected", "Choose a Library root in Library Management to load plots.")
            case .libraryRootMissing:
                return ("externaldrive.badge.exclamationmark", "Library root not found", "The Library folder is missing or unreachable, so plots cannot be loaded.")
            case .indexUnreadable:
                return ("exclamationmark.triangle", "Plot index could not be read", "This sample's results index exists but is unreadable. No plots are shown.")
            case nil:
                return ("photo.badge.plus", "No plots saved for this sample", "Plots saved from the Workbench will appear here.")
            }
        }()
        return VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(loadIssue == nil ? Color.secondary.opacity(0.6) : Color.orange)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("SamplePlotsOverview.EmptyState")
        .accessibilityLabel(title)
    }

    // MARK: - Plots Grid

    private var plotsGridView: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth, maximum: 260), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    WorkflowGalleryThumbnailCard(
                        item: item,
                        isSelected: false,
                        libraryRootURL: libraryRootURL ?? URL(fileURLWithPath: "/"),
                        onSelect: {
                            selectedItemForSheet = item
                            isShowingGallerySheet = true
                        },
                        onDoubleClick: {
                            fullScreenItem = item
                        }
                    )
                    .contextMenu {
                        Button("View Details & Provenance") {
                            selectedItemForSheet = item
                            isShowingGallerySheet = true
                        }
                        Button("Full Screen") {
                            fullScreenItem = item
                        }
                        if canDeleteChart, let ref = makeResultReference(from: item) {
                            Divider()
                            Button("Delete Chart...", role: .destructive) {
                                pendingDeleteRef = ref
                                isShowingDeleteConfirm = true
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityIdentifier("SamplePlotsOverview.Grid")
        }
    }

    // MARK: - Helpers

    private func checkDiskUpdates() {
        guard let rootURL = libraryRootURL else { return }
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        guard let indexURL = try? layout.resultsIndexURL(sampleKey: sampleKey),
              let attrs = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return
        }
        if lastKnownDiskModDate == nil {
            lastKnownDiskModDate = modDate
            if items.isEmpty {
                SamplePlotsOverviewService.invalidateMultiSampleCache(for: rootURL)
                refreshItems()
            }
        } else if modDate > lastKnownDiskModDate! {
            lastKnownDiskModDate = modDate
            SamplePlotsOverviewService.invalidateMultiSampleCache(for: rootURL)
            refreshItems()
        }
    }

    private func refreshItems() {
        guard let rootURL = libraryRootURL else {
            items = []
            loadIssue = .noLibraryRoot
            onItemsLoaded?([])
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            items = []
            loadIssue = .libraryRootMissing
            onItemsLoaded?([])
            return
        }
        let service = SamplePlotsOverviewService(
            libraryRootURL: rootURL,
            workflowDefinitions: workflowDefinitions
        )
        let loaded = service.loadPlots(
            for: sampleKey,
            preloadedResults: workbenchResults,
            preloadedPlotIndex: measurementPlotIndex
        )
        items = loaded
        loadIssue = loaded.isEmpty ? indexIssue(rootURL: rootURL) : nil
        onItemsLoaded?(loaded)
    }

    /// An index file that exists but cannot be decoded (and no in-memory copy
    /// covers it) is reported instead of being shown as "no plots".
    private func indexIssue(rootURL: URL) -> LoadIssue? {
        let layout = LibraryArtifactLayout(pathResolver: LibraryPathResolver(libraryRootURL: rootURL))
        guard let url = try? layout.resultsIndexURL(sampleKey: sampleKey),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let store = LibraryChartIndexStore(layout: layout)
        if store.loadResultsIndexFailSoft(sampleKey: sampleKey) == nil,
           workbenchResults?.sampleKey != sampleKey {
            return .indexUnreadable
        }
        return nil
    }

    private func makeResultReference(from item: WorkflowGalleryItem) -> WorkbenchResultReference? {
        WorkbenchResultReference(
            chartIdentityKey: item.chartIdentityKey,
            chartImagePath: item.chartImagePath,
            manifestPath: item.manifestPath,
            workflowID: item.rawWorkflowID,
            generatedAt: item.generatedAt,
            tabKey: item.tabKey
        )
    }
}
