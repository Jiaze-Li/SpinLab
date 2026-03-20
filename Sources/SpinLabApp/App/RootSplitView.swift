import SwiftUI

struct RootSplitView: View {
    @EnvironmentObject private var appState: SpinLabAppState
    @State private var isLibraryTreeExpanded = true
    @State private var expandedPrefixes: Set<String> = []
    @State private var hoveredSidebarRowKey: String?
    @State private var pendingDeleteDrawerBatchID: String?
    @State private var pendingDeleteDrawerPrefix: String?
    @State private var isPresentingDeleteDrawerConfirm = false
    private let sidebarTopInset: CGFloat = 64
    private let standardDetailTopInset: CGFloat = 86
    private let inboxDetailTopInset: CGFloat = 112
    private let libraryDetailTopInset: CGFloat = 14

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: sidebarTopInset)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AppArea.allCases) { area in
                            sidebarAreaButton(area)
                            if area == .library && appState.selectedArea == .library && isLibraryTreeExpanded {
                                libraryTree
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaPadding(.top, currentDetailTopInset)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .topTrailing) {
                    Text(AppVersion.current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.loadExistingDrawers()
            if let firstPrefix = existingPrefixes.first {
                expandedPrefixes.insert(firstPrefix)
            }
        }
        .onChange(of: appState.selectedArea) { _, newValue in
            if newValue == .library {
                appState.loadExistingDrawers()
                if let firstPrefix = existingPrefixes.first {
                    expandedPrefixes.insert(firstPrefix)
                }
            }
        }
        .confirmationDialog(
            "Delete Drawer?",
            isPresented: $isPresentingDeleteDrawerConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Drawer", role: .destructive) {
                if let batchID = pendingDeleteDrawerBatchID {
                    appState.deleteExistingDrawer(batchId: batchID)
                }
                pendingDeleteDrawerBatchID = nil
                pendingDeleteDrawerPrefix = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteDrawerBatchID = nil
                pendingDeleteDrawerPrefix = nil
            }
        } message: {
            let prefix = pendingDeleteDrawerPrefix ?? "-"
            let batchID = pendingDeleteDrawerBatchID ?? "-"
            Text("Delete drawer \(prefix)/\(batchID) from library files?")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.selectedArea {
        case .inbox:
            InboxView()
        case .workbench:
            WorkbenchView()
        case .library:
            LibraryView()
        }
    }

    private var currentDetailTopInset: CGFloat {
        switch appState.selectedArea {
        case .inbox:
            return inboxDetailTopInset
        case .workbench:
            return standardDetailTopInset
        case .library:
            return libraryDetailTopInset
        }
    }

    private func iconName(for area: AppArea) -> String {
        switch area {
        case .inbox:
            return "tray.full"
        case .workbench:
            return "waveform.path.ecg.rectangle"
        case .library:
            return "books.vertical"
        }
    }

    @ViewBuilder
    private func sidebarAreaButton(_ area: AppArea) -> some View {
        let key = "area:\(area.rawValue)"
        Button {
            if area == .library, appState.selectedArea == .library {
                isLibraryTreeExpanded.toggle()
            } else {
                appState.selectedArea = area
                if area == .library {
                    isLibraryTreeExpanded = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                if area == .library {
                    Image(systemName: isLibraryTreeExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(area.rawValue, systemImage: iconName(for: area))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        appState.selectedArea == area
                            ? Color.accentColor.opacity(0.18)
                            : (hoveredSidebarRowKey == key ? Color.primary.opacity(0.12) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredSidebarRowKey = isHovering ? key : nil
        }
    }

    private var libraryTree: some View {
        VStack(alignment: .leading, spacing: 4) {
            if existingPrefixes.isEmpty {
                Text("No existing drawers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(existingPrefixes, id: \.self) { prefix in
                    let prefixRowKey = "prefix:\(prefix)"
                    Button {
                        if expandedPrefixes.contains(prefix) {
                            expandedPrefixes.remove(prefix)
                        } else {
                            expandedPrefixes.insert(prefix)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: expandedPrefixes.contains(prefix) ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(prefix)
                                .font(.subheadline)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredSidebarRowKey == prefixRowKey ? Color.primary.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredSidebarRowKey = isHovering ? prefixRowKey : nil
                    }
                    .padding(.leading, 10)

                    if expandedPrefixes.contains(prefix) {
                        ForEach(groupsForPrefix(prefix)) { group in
                            let rowKey = "batch:\(prefix):\(group.batchId)"
                            Button {
                                appState.selectExistingDrawer(
                                    prefix: prefix,
                                    batchId: group.batchId,
                                    sampleId: group.samples.first?.id
                                )
                                appState.selectedArea = .library
                            } label: {
                                HStack {
                                    Text(group.batchId)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(group.samples.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            isSelectedBatch(prefix: prefix, batchId: group.batchId)
                                                ? Color.accentColor.opacity(0.18)
                                                : (hoveredSidebarRowKey == rowKey ? Color.primary.opacity(0.12) : Color.clear)
                                        )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                hoveredSidebarRowKey = isHovering ? rowKey : nil
                            }
                            .contextMenu {
                                Button("Delete Drawer…", role: .destructive) {
                                    pendingDeleteDrawerPrefix = prefix
                                    pendingDeleteDrawerBatchID = group.batchId
                                    isPresentingDeleteDrawerConfirm = true
                                }
                            }
                            .padding(.leading, 28)
                        }
                    }
                }
            }
        }
        .font(.subheadline)
    }

    private var existingPrefixes: [String] {
        let configured = appState.librarySettings.allowedBatchPrefixes.map { $0.uppercased() }
        let available = Array(appState.libraryExistingGroups.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    private func groupsForPrefix(_ prefix: String) -> [LibraryPreviewBatchGroup] {
        appState.libraryExistingGroups[prefix] ?? []
    }

    private func isSelectedBatch(prefix: String, batchId: String) -> Bool {
        appState.selectedArea == .library
            && appState.librarySelectedPrefix == prefix
            && appState.librarySelectedBatchId == batchId
    }
}
