import AppKit
import SwiftUI

/// Dedicated full-featured modal gallery sheet for browsing all saved plots of a specific sample.
///
/// Reuses P1 Workflow Gallery components:
/// - `WorkflowThumbnailCache` for bounded, downsampled image decoding
/// - `WorkflowGalleryThumbnailCard` for card display and missing file placeholders
/// - `WorkflowGalleryDetailView` for provenance, parameters, and input files
/// - `WorkflowGalleryFullScreenView` for full-resolution pan/zoom inspection
struct SamplePlotsGallerySheet: View {
    @Environment(SpinLabAppState.self) private var appState
    let sampleKey: String
    let sampleDisplayName: String
    let items: [WorkflowGalleryItem]
    let initialSelectedItem: WorkflowGalleryItem?
    let libraryRootURL: URL?
    let canDeleteChart: Bool
    let onDeleteChart: ((WorkbenchResultReference) -> Void)?
    let onDismiss: () -> Void

    @State private var galleryState = WorkflowGalleryState()
    @State private var fullScreenItem: WorkflowGalleryItem? = nil
    @State private var pendingDeleteRef: WorkbenchResultReference? = nil
    @State private var isShowingDeleteConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main Content Area
            if galleryState.items.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    // Left: Plots Grid
                    VStack(spacing: 0) {
                        filterToolbar
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

                        Divider()

                        ScrollView(.vertical) {
                            if galleryState.displayItems.isEmpty {
                                ContentUnavailableView(
                                    "No Matching Plots",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try adjusting your search query or filter options.")
                                )
                                .padding(.top, 40)
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                                    spacing: 12
                                ) {
                                    ForEach(galleryState.displayItems) { item in
                                        WorkflowGalleryThumbnailCard(
                                            item: item,
                                            isSelected: galleryState.selectedItem?.id == item.id,
                                            libraryRootURL: libraryRootURL ?? URL(fileURLWithPath: "/"),
                                            onSelect: {
                                                galleryState.selectItem(item)
                                            },
                                            onDoubleClick: {
                                                fullScreenItem = item
                                            }
                                        )
                                        .contextMenu {
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
                                .padding(14)
                            }
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity)

                    // Right: Inspector / Detail Pane
                    WorkflowGalleryDetailView(galleryState: galleryState)
                        .frame(minWidth: 340, idealWidth: 380, maxWidth: 500)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .onAppear {
            galleryState.configureForSample(
                items: items,
                libraryRootURL: libraryRootURL,
                preselectedItem: initialSelectedItem
            )
        }
        .onChange(of: items) { _, newItems in
            galleryState.configureForSample(
                items: newItems,
                libraryRootURL: libraryRootURL,
                preselectedItem: galleryState.selectedItem
            )
        }
        .onChange(of: appState.library.currentSelectionSampleId) { _, newSampleId in
            if newSampleId != sampleKey {
                onDismiss()
            }
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
                    // Remove from active sheet items
                    let updated = galleryState.items.filter { $0.chartIdentityKey != ref.chartIdentityKey }
                    galleryState.configureForSample(
                        items: updated,
                        libraryRootURL: libraryRootURL,
                        preselectedItem: updated.first
                    )
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Plots for \(sampleDisplayName)")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(items.count) \(items.count == 1 ? "plot" : "plots")")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text("Sample Key: \(sampleKey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search plots...", text: $galleryState.searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !galleryState.searchText.isEmpty {
                    Button {
                        galleryState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
            )

            Spacer()

            Picker("Filter", selection: $galleryState.filterOption) {
                ForEach(WorkflowGalleryFilter.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker("Sort", selection: $galleryState.sortOrder) {
                ForEach(WorkflowGallerySortOrder.allCases) { ord in
                    Text(ord.rawValue).tag(ord)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Plots Saved",
            systemImage: "photo.badge.plus",
            description: Text("There are no experimental plots indexed for this sample.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

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
