import Foundation

enum AppRoutePath: Equatable {
    case inbox
    case workbench
    case library
    case libraryDrawer(prefix: String, batchId: String, sampleId: String?)
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
        case let .libraryBatch(prefix, batchId, sampleId):
            return .libraryDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        case .libraryPrefix, .info:
            return nil
        }
    }

    func navigate(to path: AppRoutePath, perform: (AppRoutePath) -> Void) {
        perform(path)
    }

    func navigate(to stack: AppRouteStack, perform: (AppRoutePath) -> Void) {
        for path in stack.paths {
            navigate(to: path, perform: perform)
        }
    }

    func deepLinkToRouteStack(_ deepLink: String) -> AppRouteStack? {
        let normalized = deepLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        let components = normalized.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !components.isEmpty else {
            return nil
        }

        let root = components[0].lowercased()
        switch root {
        case "inbox":
            return AppRouteStack(.inbox)
        case "workbench":
            return AppRouteStack(.workbench)
        case "library":
            if components.count >= 3 {
                let prefix = components[1]
                let batchId = components[2]
                let sampleId = components.count >= 4 ? components[3] : nil
                return AppRouteStack(paths: [.library, .libraryDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)])
            }
            return AppRouteStack(.library)
        default:
            return nil
        }
    }
}
