import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.1.1 Route Planner")
struct V211RoutePlannerTests {
    @Test("multi-sample channels are grouped into multiple targets")
    func multiSampleChannelFanOut() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            fileSampleKey: nil,
            folderDerivedSampleKeys: [],
            sampleIDs: ["PN36", "PN37"],
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: "PN36", tags: ["STO111"]),
                SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: "PN36", tags: ["STO111"]),
                SpinLabDomain.ParsedChannelHint(channel: "ch3", sampleID: "PN37", tags: ["NGO110"])
            ]
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)

        #expect(plan.planningStatus == .reviewRequired)
        #expect(plan.targets.count == 2)
        #expect(plan.targets.first(where: { $0.sampleId == "PN36" })?.channels == ["ch1", "ch2"])
        #expect(plan.targets.first(where: { $0.sampleId == "PN37" })?.channels == ["ch3"])
        #expect(plan.unresolvedChannels.isEmpty)
        #expect(plan.conflicts.isEmpty)
    }

    @Test("channel substrate token can resolve without explicit batch token")
    func channelSubstrateTokenResolvesWithoutBatch() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            fileSampleKey: nil,
            folderDerivedSampleKeys: ["PN40", "PN41"],
            sampleIDs: ["PN40", "PN41"],
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: nil, tags: ["STO001"])
            ]
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)

        #expect(plan.targets.isEmpty)
        #expect(plan.unresolvedChannels == ["file"])
    }

    @Test("file-level routing allows partial substrate-only token")
    func fileLevelAllowsSubstrateOnlyToken() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            batchName: "B2404",
            fileSampleKey: nil,
            folderDerivedSampleKeys: [],
            sampleIDs: [],
            channelHints: [],
            substrateTags: ["STO001"]
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)

        #expect(plan.targets.isEmpty)
        #expect(plan.unresolvedChannels == ["file"])
    }

    @Test("batch token alone is valid filetoken")
    func batchOnlyTokenIsValid() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            fileSampleKey: "PN14",
            folderDerivedSampleKeys: [],
            sampleIDs: ["PN14"],
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: "PN14", tags: [])
            ]
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)

        #expect(plan.targets.first?.sampleId == "PN14")
        #expect(plan.unresolvedChannels.isEmpty)
    }

    @Test("explicit sample identity input is accepted directly")
    func explicitSampleIdentityInputIsAccepted() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            fileSampleKey: nil,
            folderDerivedSampleKeys: [],
            sampleIDs: [],
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: "PN14 - STO(111)", tags: [])
            ],
            substrateTags: []
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)

        #expect(plan.targets.count == 1)
        #expect(plan.targets.first?.sampleId == "PN14 - STO(111)")
    }

    @Test("explicit sample identity preserves treatment in sample key and tags")
    func explicitSampleIdentityPreservesTreatment() {
        let parsed = SpinLabDomain.ParsedFilenameHints(
            fileSampleKey: nil,
            folderDerivedSampleKeys: [],
            sampleIDs: [],
            channelHints: [
                SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: "PN41 - o STO(111)", tags: ["o", "STO111"])
            ],
            substrateTags: []
        )

        let plan = SpinLabRoutePlanner().makeRoutePlan(from: parsed)

        #expect(plan.targets.first?.sampleId == "PN41 - o STO(111)")
        #expect(plan.channelResolutions.first?.tags.contains("o") == true)
        #expect(plan.channelResolutions.first?.tags.contains("STO111") == true)
    }
}
