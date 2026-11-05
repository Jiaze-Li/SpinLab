import AppKit
import Combine
import SwiftUI

/// Section in `LibraryDetailView` rendered immediately below the Sample Info header.
/// Displays an overview of experimental plots associated with the selected sample.
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

    private let diskPollTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private let cardWidth: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            sectionHeader

            // Content Area
            if items.isEmpty {
                emptyStateView
            } else if items.count == 1, let singleItem = items.first {
                singlePlotView(item: singleItem)
            } else {
                multiPlotsView
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
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("No plots saved for this sample")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("SamplePlotsOverview.EmptyState")
        .accessibilityLabel("No plots saved for this sample")
    }

    // MARK: - Single Plot View

    private func singlePlotView(item: WorkflowGalleryItem) -> some View {
        HStack(spacing: 0) {
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
            .frame(width: cardWidth)
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

            Spacer()
        }
    }

    // MARK: - Multi Plots View

    private var multiPlotsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
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
                    .frame(width: cardWidth)
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
        } else if modDate > lastKnownDiskModDate! {
            lastKnownDiskModDate = modDate
            refreshItems()
        }
    }

    private func refreshItems() {
        guard let rootURL = libraryRootURL else {
            items = []
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
        onItemsLoaded?(loaded)
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
