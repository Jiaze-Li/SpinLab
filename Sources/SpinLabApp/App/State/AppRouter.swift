import Foundation

enum AppRoutePath: Equatable {
    case inbox
    case workbench
    case library
    case libraryDrawer(prefix: String, batchId: String, sampleId: String?)
}

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
}
