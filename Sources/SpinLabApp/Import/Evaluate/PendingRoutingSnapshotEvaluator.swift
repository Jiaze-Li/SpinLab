import Foundation

struct PendingRoutingSnapshotEvaluator {
    private let rules = PendingRoutingRuleBook()

    func makeSnapshot(
        routePlan: SpinLabDomain.RoutePlan,
        matchDrawer: (String) -> String?
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        let sampleResolutions = routePlan.channelResolutions.filter { normalized($0.sampleKey) != nil }
        let scopes = sampleResolutions.map { resolution in
            let sampleKey = normalized(resolution.sampleKey)
            let matchedDrawer = sampleKey.flatMap(matchDrawer)
            let warning = RoutingExplanationBook.resolveScopeWarning(
                resolutionWarning: resolution.warning,
                matchedDrawer: matchedDrawer
            )

            return SpinLabDomain.RoutingScopeEvaluation(
                scope: resolution.channel,
                sampleKey: sampleKey,
                matchedDrawer: matchedDrawer,
                tags: resolution.tags,
                warning: warning?.message,
                warningReason: warning?.reason
            )
        }

        let mode: SpinLabDomain.RoutingScopeMode = sampleResolutions.contains(where: { $0.channel != "file" })
            ? .channelLevel
            : .fileLevel
        let unresolved = unresolvedScopes(from: scopes, routePlan: routePlan)
        let verdict = rules.verdict(for: scopes)

        return SpinLabDomain.PendingRoutingSnapshot(
            mode: mode,
            verdict: verdict,
            scopes: scopes,
            unresolvedScopes: unresolved,
            conflicts: routePlan.conflicts,
            routePlan: routePlan
        )
    }

    private func unresolvedScopes(
        from scopes: [SpinLabDomain.RoutingScopeEvaluation],
        routePlan: SpinLabDomain.RoutePlan
    ) -> [String] {
        let unmatchedScopes = scopes.filter { !$0.isMatched }.map(\.scope)
        return uniquePreservingOrder(routePlan.unresolvedChannels + unmatchedScopes)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
