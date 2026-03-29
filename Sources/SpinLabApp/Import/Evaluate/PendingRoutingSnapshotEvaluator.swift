import Foundation

struct PendingRoutingSnapshotEvaluator {
    private let rules = PendingRoutingRuleBook()

    func makeSnapshot(
        routePlan: SpinLabDomain.RoutePlan,
        matchDrawer: (String) -> String?
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        // Evaluate only scopes with an explicit sample signal; empty sample scopes are non-actionable.
        let sampleResolutions = routePlan.channelResolutions.filter { normalized($0.sampleId) != nil }
        let scopes = sampleResolutions.map { resolution in
            let sampleKey = normalized(resolution.sampleId)
            let matchedDrawer = sampleKey.flatMap(matchDrawer)
            let warning = RoutingExplanationBook.resolveScopeWarning(
                resolutionWarning: resolution.warning,
                matchedDrawer: matchedDrawer
            )

            return SpinLabDomain.RoutingScopeEvaluation(
                scope: resolution.channel,
                sampleId: sampleKey,
                matchedDrawer: matchedDrawer,
                tags: resolution.tags,
                warning: warning?.message,
                warningReason: warning?.reason
            )
        }

        // Channel-level mode is enabled when any non-file scope participates in final evaluation.
        let mode: SpinLabDomain.RoutingScopeMode = sampleResolutions.contains(where: { $0.channel != "file" })
            ? .channelLevel
            : .fileLevel
        let unresolved = unresolvedScopes(from: scopes, routePlan: routePlan)
        let verdict = rules.verdict(for: scopes)
        let resolvedRoutePlan = resolvedRoutePlan(routePlan, with: scopes)

        return SpinLabDomain.PendingRoutingSnapshot(
            mode: mode,
            verdict: verdict,
            scopes: scopes,
            unresolvedScopes: unresolved,
            conflicts: routePlan.conflicts,
            routePlan: resolvedRoutePlan
        )
    }

    private func resolvedRoutePlan(
        _ routePlan: SpinLabDomain.RoutePlan,
        with scopes: [SpinLabDomain.RoutingScopeEvaluation]
    ) -> SpinLabDomain.RoutePlan {
        let matchedEntries: [(String, String)] = scopes.compactMap { scope in
            guard let matched = scope.matchedDrawer else {
                return nil
            }
            return (scope.scope, matched)
        }
        let matchedByChannel = Dictionary(uniqueKeysWithValues: matchedEntries)

        let channelResolutions = routePlan.channelResolutions.map { resolution in
            var next = resolution
            if let matchedID = matchedByChannel[resolution.channel] {
                next.sampleId = matchedID
            }
            return next
        }

        let groupedEntries: [(String, String)] = channelResolutions.compactMap { resolution in
            guard let sampleKey = normalized(resolution.sampleId) else {
                return nil
            }
            return (sampleKey, resolution.channel)
        }
        let groupedTargets = Dictionary(grouping: groupedEntries, by: { $0.0 })
        let targets = groupedTargets
            .map { sampleKey, entries in
                SpinLabDomain.RouteTarget(
                    sampleId: sampleKey,
                    channels: uniquePreservingOrder(entries.map { $0.1 }).sorted()
                )
            }
            .sorted { $0.sampleId < $1.sampleId }

        return SpinLabDomain.RoutePlan(
            planningStatus: routePlan.planningStatus,
            targets: targets,
            channelResolutions: channelResolutions,
            unresolvedChannels: routePlan.unresolvedChannels,
            conflicts: routePlan.conflicts
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
