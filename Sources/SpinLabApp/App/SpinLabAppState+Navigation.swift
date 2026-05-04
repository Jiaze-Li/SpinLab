import Foundation

extension SpinLabAppState {

    func navigate(to routeStack: AppRouteStack) {
        let router = AppRouter()
        router.navigate(to: routeStack) { [weak self] route in
            self?.navigate(to: route)
        }
    }

    func openDeepLink(_ path: String) -> Bool {
        let router = AppRouter()
        guard let stack = router.deepLinkToRouteStack(path) else {
            return false
        }
        navigate(to: stack)
        return true
    }

    func navigate(to route: AppRoutePath) {
        switch route {
        case .inbox:
            selectedArea = .inbox
        case .workbench:
            selectedArea = .workbench
            workbenchFeatureStore.selectedSection = .workflows
            workbenchFeatureStore.currentRoute = .registry(selectedID: nil)
        case let .workbenchWorkflow(id):
            selectedArea = .workbench
            workbenchFeatureStore.selectedSection = .workflows
            workbenchFeatureStore.selectWorkflow(id)
        case .library:
            selectedArea = .library
        case let .libraryDrawer(prefix, batchId, sampleId):
            selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
            selectedArea = .library
        }
    }
}
