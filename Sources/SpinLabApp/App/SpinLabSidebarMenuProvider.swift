import Foundation

@MainActor
struct SpinLabSidebarMenuProvider {
    func makeMenu(appState: SpinLabAppState, selectedArea: AppArea) -> [SidebarMenuNode] {
        AppArea.allCases.map { area in
            SidebarMenuNode(
                id: SidebarMenuNodeID.area(area),
                kind: .area(area),
                title: area.rawValue,
                systemImage: iconName(for: area),
                children: children(for: area, appState: appState, selectedArea: selectedArea),
                canExpandWhenChildrenEmpty: area == .library
            )
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

    private func children(for area: AppArea, appState: SpinLabAppState, selectedArea: AppArea) -> [SidebarMenuNode] {
        switch area {
        case .inbox:
            return [
                SidebarMenuNode(
                    id: SidebarMenuNodeID.inboxReserved(),
                    kind: .inboxReserved,
                    title: "Reserved",
                    systemImage: "circle.dashed",
                    isMuted: true
                )
            ]
        case .workbench:
            return workbenchChildren(appState: appState)
        case .library:
            guard selectedArea == .library else {
                // Lazy build: avoid constructing full Library submenu unless Library is active.
                return []
            }
            return libraryChildren(appState: appState)
        }
    }

    private func workbenchChildren(appState: SpinLabAppState) -> [SidebarMenuNode] {
        let definitions = appState.workbench.workflowDefinitions
        guard !definitions.isEmpty else {
            return [
                SidebarMenuNode(
                    id: "workbench:info-empty",
                    kind: .info,
                    title: "No workflows",
                    isSelectable: false,
                    isMuted: true
                )
            ]
        }

        return definitions.map { definition in
            SidebarMenuNode(
                id: SidebarMenuNodeID.workbenchWorkflow(definition.id),
                kind: .workbenchWorkflow(id: definition.id),
                title: definition.displayName.isEmpty ? definition.id : definition.displayName,
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        }
    }

    private func libraryChildren(appState: SpinLabAppState) -> [SidebarMenuNode] {
        let prefixes = orderedLibraryPrefixes(appState: appState)
        guard !prefixes.isEmpty else {
            return [
                SidebarMenuNode(
                    id: "library:info-empty",
                    kind: .info,
                    title: "No existing drawers",
                    isSelectable: false,
                    isMuted: true
                )
            ]
        }

        return prefixes.map { prefix in
            let groups = appState.library.libraryExistingGroups[prefix] ?? []
            let batchChildren = groups.map { group in
                SidebarMenuNode(
                    id: SidebarMenuNodeID.libraryBatch(prefix: prefix, batchID: group.batchId),
                    kind: .libraryBatch(
                        prefix: prefix,
                        batchId: group.batchId,
                        sampleId: group.samples.first?.id
                    ),
                    title: group.batchId,
                    badgeText: "\(group.samples.count)"
                )
            }
            return SidebarMenuNode(
                id: SidebarMenuNodeID.libraryPrefix(prefix),
                kind: .libraryPrefix(prefix),
                title: prefix,
                children: batchChildren
            )
        }
    }

    private func orderedLibraryPrefixes(appState: SpinLabAppState) -> [String] {
        let configured = appState.library.librarySettings.allowedBatchPrefixes.map { $0.uppercased() }
        let available = Array(appState.library.libraryExistingGroups.keys).sorted()
        guard !configured.isEmpty else {
            return available
        }

        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }
}
