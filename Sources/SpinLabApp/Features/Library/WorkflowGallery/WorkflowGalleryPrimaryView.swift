import SwiftUI

struct WorkflowGalleryPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState
    let workflowID: String
    @Bindable var galleryState: WorkflowGalleryState

    private var libraryRootURL: URL {
        if let rootPath = appState.library.librarySettings.rootPath, !rootPath.isEmpty {
            return URL(fileURLWithPath: rootPath)
        }
        return URL(fileURLWithPath: "/Users/jack/Downloads/data")
    }

    private var workflowDisplayName: String {
        let defs = appState.workflowDefinitions.isEmpty ? appState.workbench.workflowDefinitions : appState.workflowDefinitions
        if let def = defs.first(where: { $0.id.caseInsensitiveCompare(workflowID) == .orderedSame }) {
            return def.displayName.isEmpty ? def.id : def.displayName
        }
        if workflowID.lowercased() == "3w" { return "3ω" }
        return workflowID
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header control bar
            galleryHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Divider()

            // Main Content Area
            ZStack {
                if galleryState.isLoading {
                    ProgressView("Scanning library for \(workflowDisplayName) charts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if galleryState.items.isEmpty {
                    ContentUnavailableView(
                        "No Charts Found",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("No saved charts for \(workflowDisplayName) were found across any samples in the library.")
                    )
                } else if galleryState.displayItems.isEmpty {
                    ContentUnavailableView.search(text: galleryState.searchText)
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(galleryState.displayItems) { item in
                                WorkflowGalleryThumbnailCard(
                                    item: item,
                                    isSelected: galleryState.selectedItem?.id == item.id,
                                    libraryRootURL: libraryRootURL,
                                    onSelect: {
                                        galleryState.selectItem(item)
                                    },
                                    onDoubleClick: {
                                        galleryState.selectItem(item)
                                        galleryState.openFullScreen()
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $galleryState.isFullScreenPresented) {
            if let selected = galleryState.selectedItem {
                WorkflowGalleryFullScreenView(
                    item: selected,
                    libraryRootURL: libraryRootURL,
                    onDismiss: {
                        galleryState.isFullScreenPresented = false
                    }
                )
            }
        }
        .onAppear {
            loadGalleryData()
        }
        .onChange(of: workflowID) { _, _ in
            loadGalleryData()
        }
    }

    private var galleryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                // Title and Count
                HStack(spacing: 8) {
                    Text(workflowDisplayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("\(galleryState.items.count)")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .secondaryLabelColor).opacity(0.15))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }

                Spacer()

                // Filter Picker
                Picker("Filter", selection: $galleryState.filterOption) {
                    ForEach(WorkflowGalleryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                // Sort Order Picker
                Picker("Sort", selection: $galleryState.sortOrder) {
                    ForEach(WorkflowGallerySortOrder.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by sample key or plot title...", text: $galleryState.searchText)
                    .textFieldStyle(.plain)

                if !galleryState.searchText.isEmpty {
                    Button {
                        galleryState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func loadGalleryData() {
        let defs = appState.workflowDefinitions.isEmpty ? appState.workbench.workflowDefinitions : appState.workflowDefinitions
        galleryState.loadGallery(
            workflowID: workflowID,
            libraryRootURL: libraryRootURL,
            workflowDefinitions: defs
        )
    }
}
