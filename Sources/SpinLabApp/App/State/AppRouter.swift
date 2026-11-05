import Foundation

enum AppRoutePath: Equatable {
    case inbox
    case workbench
    case workbenchWorkflow(id: String)
    /// Library Management (Library root).
    case library
    /// Library Search workspace.
    case librarySearch
    /// Library Sample Workspace for the given Batch / Sample.
    case libraryDrawer(prefix: String, batchId: String, sampleId: String?)
    case libraryWorkflowGallery(id: String)
}

struct AppRouteStack: Equatable {
    var paths: [AppRoutePath]

    init(paths: [AppRoutePath]) {
        self.paths = paths
    }

    init(_ path: AppRoutePath) {
        self.paths = [path]
    }

    var terminalPath: AppRoutePath? {
        paths.last
    }
}

@MainActor
struct AppRouter {
    func routePath(for nodeKind: SidebarMenuNodeKind) -> AppRoutePath? {
        switch nodeKind {
        case let .area(area):
            switch area {
            case .inbox:
                return .inbox
            case .workbench:
                return .workbench
            case .library:
                return .library
            }
        case .inboxReserved:
            return .inbox
        case let .workbenchWorkflow(id):
            return .workbenchWorkflow(id: id)
        case let .libraryWorkflowGallery(id):
            return .libraryWorkflowGallery(id: id)
        case let .libraryBatch(prefix, batchId, sampleId):
            return .libraryDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        case .libraryPrefix, .libraryWorkflowsGroup, .info:
            return nil
        }
    }

    func navigate(to path: AppRoutePath, perform: (AppRoutePath) -> Void) {
        perform(path)
    }

    func navigate(to stack: AppRouteStack, perform: (AppRoutePath) -> Void) {
        // Only the terminal path is committed. Earlier entries are context for
        // humans/links; executing them would commit intermediate pages (and run
        // the dirty-draft guard once per segment) before the real target.
        guard let terminal = stack.terminalPath else {
            return
        }
        navigate(to: terminal, perform: perform)
    }

    // MARK: Deep links

    /// Percent-encodes one path segment. `/` and `%` are always escaped so a
    /// Sample/Batch key containing `/` stays a single, reversible segment.
    static func encodeSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func decodeSegment(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    /// Canonical deep link for a route. Inverse of `deepLinkToRouteStack` for
    /// every route that has a link form.
    func deepLink(for path: AppRoutePath) -> String {
        let enc = Self.encodeSegment
        switch path {
        case .inbox:
            return "inbox"
        case .workbench:
            return "workbench"
        case let .workbenchWorkflow(id):
            return "workbench/\(enc(id))"
        case .library:
            return "library"
        case .librarySearch:
            return "library/search"
        case let .libraryDrawer(prefix, batchId, sampleId):
            var link = "library/\(enc(prefix))/\(enc(batchId))"
            if let sampleId {
                link += "/\(enc(sampleId))"
            }
            return link
        case let .libraryWorkflowGallery(id):
            return "library/workflows/\(enc(id))"
        }
    }

    func deepLinkToRouteStack(_ deepLink: String) -> AppRouteStack? {
        let normalized = deepLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        let components = normalized.split(separator: "/").map { Self.decodeSegment(String($0)) }.filter { !$0.isEmpty }
        guard !components.isEmpty else {
            return nil
        }

        let root = components[0].lowercased()
        switch root {
        case "inbox":
            return AppRouteStack(.inbox)
        case "workbench":
            if components.count >= 2 {
                return AppRouteStack(paths: [.workbench, .workbenchWorkflow(id: components[1])])
            }
            return AppRouteStack(.workbench)
        case "library":
            if components.count == 1 {
                return AppRouteStack(.library)
            }
            if components.count == 2 && components[1].lowercased() == "search" {
                return AppRouteStack(.librarySearch)
            }
            if components.count == 2 && components[1].lowercased() == "management" {
                return AppRouteStack(.library)
            }
            if components.count == 3 && components[1].lowercased() == "workflows" {
                return AppRouteStack(paths: [.library, .libraryWorkflowGallery(id: components[2])])
            }
            if components[1].lowercased() == "workflows" {
                return components.count == 2 ? AppRouteStack(.library) : nil
            }
            // library/<prefix>/<batch>[/<sample>]. More than four raw segments
            // means an unescaped "/" inside a key: ambiguous, so refuse it
            // rather than guess (and possibly open a different sample).
            if components.count >= 3 && components.count <= 4 {
                let sampleId = components.count == 4 ? components[3] : nil
                return AppRouteStack(paths: [.library, .libraryDrawer(prefix: components[1], batchId: components[2], sampleId: sampleId)])
            }
            return nil
        default:
            return nil
        }
    }
}
