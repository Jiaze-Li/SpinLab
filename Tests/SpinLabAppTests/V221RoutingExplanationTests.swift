import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.1 Routing Explanation")
struct V221RoutingExplanationTests {
    @Test("route status has stable display title")
    func routeStatusDisplayTitle() {
        #expect(SpinLabDomain.RouteStatus.libraryMatched.displayTitle == "Library Matched")
        #expect(SpinLabDomain.RouteStatus.reviewRequired.displayTitle == "Review Required")
    }

    @Test("planner resolves channel-only substrate signal without unresolved warnings")
    func plannerResolvesChannelOnlySubstrateSignal() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: nil, tags: ["HF"], testInfoTags: [])
            ]
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)
        let ch1 = plan.channelResolutions.first(where: { $0.channel == "ch1" })

        #expect(ch1?.sampleKey == "HF")
        #expect(ch1?.warning == nil)
        #expect(ch1?.warningReason == nil)
        #expect(plan.unresolvedChannels.isEmpty)
    }

    @Test("snapshot evaluator emits no-matching-drawer reason when matching fails")
    func evaluatorEmitsReasonForNoMatchingDrawer() {
        let evaluator = PendingRoutingSnapshotEvaluator()
        let routePlan = SpinLabDomain.RoutePlan(
            channelResolutions: [
                SpinLabDomain.RouteChannelResolution(
                    channel: "file",
                    sampleKey: "PN32 - STO(111)",
                    source: "fileToken"
                )
            ]
        )

        let snapshot = evaluator.makeSnapshot(
            routePlan: routePlan,
            matchDrawer: { _ in nil }
        )

        #expect(snapshot.scopes.count == 1)
        #expect(snapshot.scopes[0].warning == "No matching drawer found in Library.")
        #expect(snapshot.scopes[0].warningReason == .noMatchingLibraryDrawer)
    }

    @Test("snapshot evaluator keeps upstream warning and reason")
    func evaluatorKeepsUpstreamWarningAndReason() {
        let evaluator = PendingRoutingSnapshotEvaluator()
        let routePlan = SpinLabDomain.RoutePlan(
            channelResolutions: [
                SpinLabDomain.RouteChannelResolution(
                    channel: "ch2",
                    sampleKey: "PN41",
                    source: "channelToken",
                    warning: "Upstream warning"
                )
            ]
        )

        let snapshot = evaluator.makeSnapshot(
            routePlan: routePlan,
            matchDrawer: { _ in nil }
        )

        #expect(snapshot.scopes.count == 1)
        #expect(snapshot.scopes[0].warning == "Upstream warning")
        #expect(snapshot.scopes[0].warningReason == .upstreamResolutionWarning)
    }
}
