import Foundation

@MainActor
final class SpinLabSidebarMenuProvider {
    private var cachedLibraryChildrenKey: String?
    private var cachedLibraryChildrenValue: [SidebarMenuNode] = []

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
            if selectedArea == .library {
                return cachedLibraryChildren(appState: appState)
            }
            // Not active: return last cached children so the tree stays expanded.
            return cachedLibraryChildrenValue
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
        var nodes: [SidebarMenuNode] = []

        // 1. Workflow Gallery section
        var defs = appState.workflowDefinitions.isEmpty ? appState.workbench.workflowDefinitions : appState.workflowDefinitions
        if defs.isEmpty {
            defs = WorkflowDefinitionStore().load()
        }
        let workflowChildren = defs.map { def in
            SidebarMenuNode(
                id: SidebarMenuNodeID.libraryWorkflowGallery(def.id),
                kind: .libraryWorkflowGallery(id: def.id),
                title: def.displayName.isEmpty ? def.id : def.displayName,
                systemImage: "square.grid.2x2"
            )
        }

        let workflowsGroup = SidebarMenuNode(
            id: SidebarMenuNodeID.libraryWorkflowsGroup(),
            kind: .libraryWorkflowsGroup,
            title: "Workflows",
            systemImage: "photo.stack",
            children: workflowChildren,
            canExpandWhenChildrenEmpty: false,
            isSelectable: false
        )
        nodes.append(workflowsGroup)

        // 2. Existing Drawers / Prefixes section
        let prefixes = orderedLibraryPrefixes(appState: appState)
        if prefixes.isEmpty {
            nodes.append(
                SidebarMenuNode(
                    id: "library:info-empty",
                    kind: .info,
                    title: "No existing drawers",
                    isSelectable: false,
                    isMuted: true
                )
            )
        } else {
            let prefixNodes = prefixes.map { prefix in
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
            nodes.append(contentsOf: prefixNodes)
        }

        return nodes
    }

    private func cachedLibraryChildren(appState: SpinLabAppState) -> [SidebarMenuNode] {
        let cacheKey = libraryChildrenCacheKey(appState: appState)
        if cachedLibraryChildrenKey == cacheKey {
            return cachedLibraryChildrenValue
        }
        let rebuilt = libraryChildren(appState: appState)
        cachedLibraryChildrenKey = cacheKey
        cachedLibraryChildrenValue = rebuilt
        return rebuilt
    }

    private func libraryChildrenCacheKey(appState: SpinLabAppState) -> String {
        let defs = appState.workflowDefinitions.isEmpty ? appState.workbench.workflowDefinitions : appState.workflowDefinitions
        let orderedPrefixes = orderedLibraryPrefixes(appState: appState)
        var parts: [String] = []
        parts.reserveCapacity(2 + defs.count + orderedPrefixes.count * 8)
        parts.append("wfs:\(defs.map(\.id).joined(separator: ","))")
        parts.append("prefixes:\(orderedPrefixes.joined(separator: ","))")
        for prefix in orderedPrefixes {
            let groups = appState.library.libraryExistingGroups[prefix] ?? []
            parts.append("p:\(prefix)#\(groups.count)")
            for group in groups {
                parts.append("b:\(group.batchId)")
                parts.append("n:\(group.samples.count)")
                parts.append("f:\(group.samples.first?.id ?? "")")
            }
        }
        return parts.joined(separator: "|")
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
