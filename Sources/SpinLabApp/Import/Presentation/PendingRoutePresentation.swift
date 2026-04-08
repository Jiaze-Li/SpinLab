import Foundation

enum PendingWarningSeverity: String, Hashable {
    case info
    case warning
    case error
}

enum PendingWarningSource: String, Hashable {
    case parser
    case registrySubstrate
    case routing
}

struct PendingDisplayWarning: Hashable, Identifiable {
    var id: String {
        "\(source.rawValue)|\(reasonCode ?? "")|\(message.lowercased())|\(affectedScopes.sorted().joined(separator: ","))"
    }
    var message: String
    var source: PendingWarningSource
    var severity: PendingWarningSeverity
    var reasonCode: String?
    var affectedScopes: Set<String> = []

    var scopeSummary: String? {
        let sorted = affectedScopes.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        return sorted.joined(separator: ", ")
    }
}

struct PendingRoutePresentation: Hashable {
    var pendingID: UUID
    var verdict: SpinLabDomain.RouteStatus
    var routeStatusTitle: String
    var isLibraryMatched: Bool
    var warningItems: [PendingDisplayWarning]
}

struct PendingWarningAggregator {
    func aggregate(
        parsedWarnings: [String],
        substrateWarning: String?,
        routingSnapshot: SpinLabDomain.PendingRoutingSnapshot?
    ) -> [PendingDisplayWarning] {
        var warnings: [PendingDisplayWarning] = []
        warnings.append(contentsOf: parsedWarnings.map {
            PendingDisplayWarning(
                message: $0,
                source: .parser,
                severity: .warning,
                reasonCode: nil,
                affectedScopes: []
            )
        })

        if let substrateWarning {
            warnings.append(
                PendingDisplayWarning(
                    message: substrateWarning,
                    source: .registrySubstrate,
                    severity: .warning,
                    reasonCode: "registry-substrate",
                    affectedScopes: []
                )
            )
        }

        if let routingSnapshot {
            for scope in routingSnapshot.scopes {
                guard let warning = normalized(scope.warning) else {
                    continue
                }
                warnings.append(
                    PendingDisplayWarning(
                        message: warning,
                        source: .routing,
                        severity: .warning,
                        reasonCode: scope.warningReason?.rawValue,
                        affectedScopes: [scope.scope]
                    )
                )
            }

            if let nameConflict = normalized(routingSnapshot.nameConflictWarning) {
                warnings.append(
                    PendingDisplayWarning(
                        message: nameConflict,
                        source: .routing,
                        severity: .warning,
                        reasonCode: SpinLabDomain.RoutingWarningReason.nameConflictInLibrary.rawValue,
                        affectedScopes: []
                    )
                )
            }
        }

        var mergedByKey: [String: PendingDisplayWarning] = [:]
        for warning in warnings {
            let key = dedupKey(for: warning)
            if var existing = mergedByKey[key] {
                existing.affectedScopes.formUnion(warning.affectedScopes)
                mergedByKey[key] = existing
            } else {
                mergedByKey[key] = warning
            }
        }
        return mergedByKey.values.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dedupKey(for warning: PendingDisplayWarning) -> String {
        "\(warning.source.rawValue)|\(warning.reasonCode ?? "")|\(warning.message.lowercased())|\(warning.severity.rawValue)"
    }
}

struct PendingRoutePresentationBuilder {
    private let warningAggregator = PendingWarningAggregator()

    func build(
        pending: SpinLabDomain.PendingImport,
        routingSnapshot: SpinLabDomain.PendingRoutingSnapshot?,
        substrateWarning: String?
    ) -> PendingRoutePresentation {
        let verdict = routingSnapshot?.verdict ?? .reviewRequired
        let warnings = warningAggregator.aggregate(
            parsedWarnings: pending.parsedHints.warnings,
            substrateWarning: substrateWarning,
            routingSnapshot: routingSnapshot
        )
        return PendingRoutePresentation(
            pendingID: pending.id,
            verdict: verdict,
            routeStatusTitle: verdict.displayTitle,
            isLibraryMatched: verdict == .libraryMatched,
            warningItems: warnings
        )
    }
}
