import Testing
@testable import SpinLabApp

@Suite("V2.2.1 Route Presentation")
struct V221RoutePresentationTests {
    @Test("warning aggregator merges parser substrate and routing warnings")
    func warningAggregatorMergesAllSources() {
        let aggregator = PendingWarningAggregator()
        let snapshot = SpinLabDomain.PendingRoutingSnapshot(
            mode: .fileLevel,
            verdict: .reviewRequired,
            scopes: [
                SpinLabDomain.RoutingScopeEvaluation(
                    scope: "file",
                    sampleKey: "PN41 - STO(001)",
                    matchedDrawer: nil,
                    tags: [],
                    warning: "No matching drawer found in Library.",
                    warningReason: .noMatchingLibraryDrawer
                )
            ],
            unresolvedScopes: ["file"],
            conflicts: [],
            routePlan: SpinLabDomain.RoutePlan()
        )

        let warnings = aggregator.aggregate(
            parsedWarnings: ["Parser warning", "Parser warning"],
            substrateWarning: "Registry substrate is missing for PN41.",
            routingSnapshot: snapshot
        )

        #expect(warnings.count == 3)
        #expect(warnings.contains(where: { $0.message == "Parser warning" && $0.source == .parser }))
        #expect(warnings.contains(where: { $0.source == .registrySubstrate }))
        #expect(warnings.contains(where: { $0.reasonCode == SpinLabDomain.RoutingWarningReason.noMatchingLibraryDrawer.rawValue }))
        #expect(warnings.contains(where: { $0.reasonCode == SpinLabDomain.RoutingWarningReason.noMatchingLibraryDrawer.rawValue && $0.affectedScopes == ["file"] }))
    }

    @Test("routing warnings preserve merged scope context when deduplicated")
    func warningAggregatorPreservesScopeContextOnDedup() {
        let aggregator = PendingWarningAggregator()
        let snapshot = SpinLabDomain.PendingRoutingSnapshot(
            mode: .channelLevel,
            verdict: .reviewRequired,
            scopes: [
                SpinLabDomain.RoutingScopeEvaluation(
                    scope: "ch1",
                    sampleKey: "PN41",
                    matchedDrawer: nil,
                    tags: [],
                    warning: "No matching drawer found in Library.",
                    warningReason: .noMatchingLibraryDrawer
                ),
                SpinLabDomain.RoutingScopeEvaluation(
                    scope: "ch2",
                    sampleKey: "PN42",
                    matchedDrawer: nil,
                    tags: [],
                    warning: "No matching drawer found in Library.",
                    warningReason: .noMatchingLibraryDrawer
                )
            ],
            unresolvedScopes: ["ch1", "ch2"],
            conflicts: [],
            routePlan: SpinLabDomain.RoutePlan()
        )

        let warnings = aggregator.aggregate(
            parsedWarnings: [],
            substrateWarning: nil,
            routingSnapshot: snapshot
        )

        #expect(warnings.count == 1)
        #expect(warnings.first?.affectedScopes == ["ch1", "ch2"])
    }

    @Test("rule loader emits metadata with stable fingerprint format")
    func ruleLoaderProvidesMetadata() {
        let loadResult = RuleLoader.shared.loadCached()
        #expect(loadResult.metadata.version == loadResult.ruleSet.version)
        #expect(!loadResult.metadata.contentHash.isEmpty)
        #expect(loadResult.metadata.fingerprint.hasPrefix("v\(loadResult.ruleSet.version):"))
    }
}
