import Foundation

enum SidebarMenuNodeKind: Hashable {
    case area(AppArea)
    case inboxReserved
    case workbenchWorkflow(id: String)
    case libraryPrefix(String)
    case libraryBatch(prefix: String, batchId: String, sampleId: String?)
    case info
}

struct SidebarMenuNode: Identifiable, Hashable {
    let id: String
    let kind: SidebarMenuNodeKind
    let title: String
    let systemImage: String?
    let badgeText: String?
    let children: [SidebarMenuNode]
    let canExpandWhenChildrenEmpty: Bool
    let isSelectable: Bool
    let isMuted: Bool

    var isExpandable: Bool {
        canExpandWhenChildrenEmpty || !children.isEmpty
    }

    init(
        id: String,
        kind: SidebarMenuNodeKind,
        title: String,
        systemImage: String? = nil,
        badgeText: String? = nil,
        children: [SidebarMenuNode] = [],
        canExpandWhenChildrenEmpty: Bool = false,
        isSelectable: Bool = true,
        isMuted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.children = children
        self.canExpandWhenChildrenEmpty = canExpandWhenChildrenEmpty
        self.isSelectable = isSelectable
        self.isMuted = isMuted
    }
}

enum SidebarMenuNodeID {
    static func area(_ area: AppArea) -> String {
        "area:\(area.rawValue.lowercased())"
    }

    static func inboxReserved() -> String {
        "inbox:reserved"
    }

    static func libraryPrefix(_ prefix: String) -> String {
        "library-prefix:\(prefix)"
    }

    static func libraryBatch(prefix: String, batchID: String) -> String {
        "library-batch:\(prefix):\(batchID)"
    }

    static func workbenchWorkflow(_ id: String) -> String {
        "workbench-workflow:\(id)"
    }
}
