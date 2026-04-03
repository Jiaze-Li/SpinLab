import AppKit
import Observation
import SwiftUI

struct RootSplitView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var expandedSidebarNodeIDs: Set<String> = []
    @State private var pendingDeleteDrawerBatchID: String?
    @State private var pendingDeleteDrawerPrefix: String?
    @State private var isPresentingDeleteDrawerConfirm = false

    private let sidebarTopInset: CGFloat = 64
    private let standardDetailTopInset: CGFloat = 86
    private let inboxDetailTopInset: CGFloat = 14
    private let libraryDetailTopInset: CGFloat = 20
    private let sidebarMenuProvider = SpinLabSidebarMenuProvider()
    private let appRouter = AppRouter()

    var body: some View {
        @Bindable var bindableAppState = appState

        NavigationSplitView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: sidebarTopInset)

                ScrollView(.vertical) {
                    SidebarTreeView(
                        nodes: sidebarMenuProvider.makeMenu(appState: appState, selectedArea: appState.selectedArea),
                        expandedNodeIDs: expandedSidebarNodeIDs,
                        selectedNodeIDs: selectedSidebarNodeIDs,
                        onNodeTap: handleSidebarNodeTap,
                        contextMenuItems: contextMenuItems(for:)
                    )
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
                    HStack(spacing: 10) {
                        if appState.selectedArea != .library {
                            Button("Export Audit") {
                                presentAuditTrailExportPanel()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }

                        if appState.selectedArea != .library {
                            Text(AppVersion.current)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.loadExistingDrawers()
            restoreSidebarInteractionState()
            pruneExpandedSidebarStateForSelectedArea()
            persistSidebarInteractionState()
        }
        .onChange(of: appState.selectedArea) { _, _ in
            pruneExpandedSidebarStateForSelectedArea()
            persistSidebarInteractionState()
        }
        .onChange(of: expandedSidebarNodeIDs) { _, _ in
            persistSidebarInteractionState()
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
        .alert(item: $bindableAppState.activeAlert) { alertState in
            Alert(
                title: Text(alertState.title),
                message: Text(alertState.message),
                dismissButton: .default(Text("OK")) {
                    appState.clearActiveAlert()
                }
            )
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

    private var selectedSidebarNodeIDs: Set<String> {
        var selected: Set<String> = []
        switch appState.selectedArea {
        case .workbench:
            switch appState.workbench.currentRoute {
            case .registry(_):
                selected.insert(SidebarMenuNodeID.area(.workbench))
            case .workflow(let id):
                selected.insert(SidebarMenuNodeID.workbenchWorkflow(id))
            }
        case .library:
            selected.insert(SidebarMenuNodeID.area(.library))
            if let prefix = appState.library.librarySelectedPrefix,
               let batchID = appState.library.librarySelectedBatchId {
                selected.insert(SidebarMenuNodeID.libraryBatch(prefix: prefix, batchID: batchID))
            }
        case .inbox:
            selected.insert(SidebarMenuNodeID.area(.inbox))
        }
        return selected
    }

    private func restoreSidebarInteractionState() {
        let restored = appState.interactionValue(\.sidebar)
        if !restored.expandedNodeIDs.isEmpty {
            expandedSidebarNodeIDs = restored.expandedNodeIDs
            return
        }

        expandedSidebarNodeIDs = legacyExpandedNodeIDs(from: restored)
        if expandedSidebarNodeIDs.isEmpty {
            expandedSidebarNodeIDs = [SidebarMenuNodeID.area(.inbox)]
        }
    }

    private func legacyExpandedNodeIDs(from state: SidebarInteractionState) -> Set<String> {
        var ids: Set<String> = []
        if state.isLibraryTreeExpanded {
            ids.insert(SidebarMenuNodeID.area(.library))
        }
        for prefix in state.expandedPrefixes {
            ids.insert(SidebarMenuNodeID.libraryPrefix(prefix))
        }
        return ids
    }

    /// Enforces WYSIWYG sidebar state:
    /// if a section is visually collapsed because another area is active,
    /// its expansion state is also removed from memory.
    private func pruneExpandedSidebarStateForSelectedArea() {
        let selectedAreaNodeID = SidebarMenuNodeID.area(appState.selectedArea)
        expandedSidebarNodeIDs = expandedSidebarNodeIDs.filter { nodeID in
            if nodeID.hasPrefix("area:") {
                return nodeID == selectedAreaNodeID
            }
            if nodeID.hasPrefix("library-prefix:") {
                return appState.selectedArea == .library
            }
            return true
        }
    }

    private func persistSidebarInteractionState() {
        let isLibraryTreeExpanded = expandedSidebarNodeIDs.contains(SidebarMenuNodeID.area(.library))
        let expandedPrefixes: Set<String> = Set<String>(expandedSidebarNodeIDs.compactMap { nodeID in
            guard nodeID.hasPrefix("library-prefix:") else {
                return nil
            }
            return String(nodeID.dropFirst("library-prefix:".count))
        })

        appState.updateInteractionValue(
            \.sidebar,
            to: SidebarInteractionState(
                isLibraryTreeExpanded: isLibraryTreeExpanded,
                expandedPrefixes: expandedPrefixes,
                expandedNodeIDs: expandedSidebarNodeIDs
            )
        )
    }

    private func handleSidebarNodeTap(_ node: SidebarMenuNode) {
        if case .libraryPrefix = node.kind {
            toggleSidebarNodeExpansion(node.id)
            return
        }

        guard let path = appRouter.routePath(for: node.kind) else {
            return
        }

        if case .area = node.kind {
            appState.navigate(to: path)
            if node.isExpandable {
                toggleSidebarNodeExpansion(node.id)
            }
            return
        }

        appState.navigate(to: path)
    }

    private func toggleSidebarNodeExpansion(_ nodeID: String) {
        if expandedSidebarNodeIDs.contains(nodeID) {
            expandedSidebarNodeIDs.remove(nodeID)
        } else {
            expandedSidebarNodeIDs.insert(nodeID)
        }
    }

    private func contextMenuItems(for node: SidebarMenuNode) -> [SidebarContextMenuItem] {
        guard case let .libraryBatch(prefix, batchID, _) = node.kind else {
            return []
        }

        return [
            SidebarContextMenuItem(
                id: "delete:\(prefix):\(batchID)",
                title: "Delete Drawer…",
                role: .destructive
            ) {
                pendingDeleteDrawerPrefix = prefix
                pendingDeleteDrawerBatchID = batchID
                isPresentingDeleteDrawerConfirm = true
            }
        ]
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
}
