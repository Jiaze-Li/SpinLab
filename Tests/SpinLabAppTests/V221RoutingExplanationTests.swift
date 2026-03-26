import Testing
@testable import SpinLabApp

@Suite("V2.2.1 Routing Explanation")
struct V221RoutingExplanationTests {
    @Test("route status has stable display title")
    func routeStatusDisplayTitle() {
        #expect(SpinLabDomain.RouteStatus.libraryMatched.displayTitle == "Library Matched")
        #expect(SpinLabDomain.RouteStatus.reviewRequired.displayTitle == "Review Required")
    }

    @Test("planner emits channel warning reason when signal cannot resolve into token")
    func plannerEmitsReasonForUnresolvedChannelSignal() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: nil, tags: ["HF"], testInfoTags: [])
            ]
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)
        let ch1 = plan.channelResolutions.first(where: { $0.channel == "ch1" })

        #expect(ch1?.warning == "Channel sample signal exists but no filetoken was resolved.")
        #expect(ch1?.warningReason == .channelSampleSignalWithoutToken)
        #expect(plan.unresolvedChannels == ["ch1"])
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
