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

    func navigate(to path: AppRoutePath, appState: SpinLabAppState) {
        switch path {
        case .inbox:
            appState.selectedArea = .inbox
        case .workbench:
            appState.selectedArea = .workbench
        case .library:
            appState.selectedArea = .library
        case let .libraryDrawer(prefix, batchId, sampleId):
            appState.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
            appState.selectedArea = .library
        }
    }

    func navigate(to stack: AppRouteStack, appState: SpinLabAppState) {
        for path in stack.paths {
            navigate(to: path, appState: appState)
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
