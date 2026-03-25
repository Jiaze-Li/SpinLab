import Foundation

struct PendingRoutingRuleBook {
    func verdict(for scopes: [SpinLabDomain.RoutingScopeEvaluation]) -> SpinLabDomain.RouteStatus {
        scopes.allSatisfy(\.isMatched) && !scopes.isEmpty ? .libraryMatched : .reviewRequired
    }
}
