import Foundation

protocol RoutePlanningCapability {
    func makeRoutePlan(from parsed: SpinLabDomain.ParsedFilenameHints) -> SpinLabDomain.RoutePlan
}

protocol RouteSnapshotEvaluationCapability {
    func makeSnapshot(
        routePlan: SpinLabDomain.RoutePlan,
        matchDrawer: (String) -> String?
    ) -> SpinLabDomain.PendingRoutingSnapshot
}

protocol DrawerMatchingCapability {
    func makeIndex(from samples: [LibrarySample]) -> DrawerMatchIndex
    func match(sampleInput: String, index: DrawerMatchIndex) -> String?
}

protocol RuleRuntimeCapability {
    func loadRulesCached() -> RuleLoader.LoadResult
    func reloadRulesCached() -> RuleLoader.LoadResult
}

struct DefaultRuleRuntimeCapability: RuleRuntimeCapability {
    private let ruleProvider: any SpinLabRuleProviding

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        self.ruleProvider = ruleProvider
    }

    func loadRulesCached() -> RuleLoader.LoadResult {
        ruleProvider.loadResult()
    }

    func reloadRulesCached() -> RuleLoader.LoadResult {
        ruleProvider.reloadResult()
    }
}

struct RoutingCapabilities {
    var planner: any RoutePlanningCapability
    var evaluator: any RouteSnapshotEvaluationCapability
    var matcher: any DrawerMatchingCapability

    nonisolated(unsafe) static let live = RoutingCapabilities(
        planner: SpinLabRoutePlanner(),
        evaluator: PendingRoutingSnapshotEvaluator(),
        matcher: DrawerMatchEngine()
    )
}

extension SpinLabRoutePlanner: RoutePlanningCapability {}
extension PendingRoutingSnapshotEvaluator: RouteSnapshotEvaluationCapability {}
extension DrawerMatchEngine: DrawerMatchingCapability {}
