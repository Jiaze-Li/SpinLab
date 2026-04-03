import SwiftUI

struct SidebarContextMenuItem {
    let id: String
    let title: String
    let role: ButtonRole?
    let action: () -> Void
}

struct SidebarTreeView: View {
    let nodes: [SidebarMenuNode]
    let expandedNodeIDs: Set<String>
    let selectedNodeIDs: Set<String>
    let onNodeTap: (SidebarMenuNode) -> Void
    let contextMenuItems: (SidebarMenuNode) -> [SidebarContextMenuItem]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(nodes) { node in
                SidebarTreeRow(
                    node: node,
                    depth: 0,
                    expandedNodeIDs: expandedNodeIDs,
                    selectedNodeIDs: selectedNodeIDs,
                    onNodeTap: onNodeTap,
                    contextMenuItems: contextMenuItems
                )
            }
        }
    }
}

private struct SidebarTreeRow: View {
    let node: SidebarMenuNode
    let depth: Int
    let expandedNodeIDs: Set<String>
    let selectedNodeIDs: Set<String>
    let onNodeTap: (SidebarMenuNode) -> Void
    let contextMenuItems: (SidebarMenuNode) -> [SidebarContextMenuItem]

    @State private var isHovered = false

    var body: some View {
        let isExpanded = expandedNodeIDs.contains(node.id)
        let isSelected = selectedNodeIDs.contains(node.id)
        let rowContextItems = contextMenuItems(node)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard node.isSelectable else { return }
                onNodeTap(node)
            } label: {
                HStack(spacing: 6) {
                    if node.isExpandable {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 10, alignment: .leading)
                    } else if depth > 0 {
                        Color.clear
                            .frame(width: 10, height: 10)
                    }

                    if let systemImage = node.systemImage {
                        Image(systemName: systemImage)
                            .font(depth == 0 ? .body : .caption)
                            .foregroundStyle(node.isMuted ? .secondary : .primary)
                    }

                    Text(node.title)
                        .font(depth == 0 ? .body : .subheadline)
                        .foregroundStyle(node.isMuted ? .secondary : .primary)

                    Spacer()

                    if let badgeText = node.badgeText {
                        Text(badgeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .padding(.leading, CGFloat(depth) * 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.18)
                                : (isHovered ? Color.primary.opacity(0.12) : Color.clear)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!node.isSelectable)
            .onHover { hovering in
                isHovered = hovering
            }
            .contextMenu {
                ForEach(rowContextItems, id: \.id) { item in
                    Button(item.title, role: item.role) {
                        item.action()
                    }
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    SidebarTreeRow(
                        node: child,
                        depth: depth + 1,
                        expandedNodeIDs: expandedNodeIDs,
                        selectedNodeIDs: selectedNodeIDs,
                        onNodeTap: onNodeTap,
                        contextMenuItems: contextMenuItems
                    )
                }
            }
        }
    }
}
