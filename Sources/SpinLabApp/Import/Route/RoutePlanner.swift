import Foundation

struct SpinLabRoutePlanner {
    private let rules = FileRoutingRuleBook()

    func makeRoutePlan(from parsed: SpinLabDomain.ParsedFilenameHints) -> SpinLabDomain.RoutePlan {
        let folderCandidates = uniquePreservingOrder(parsed.folderDerivedSampleKeys)
        let fallbackFileSampleInput = rules.normalizedSampleInput(parsed.defaultSampleKey)
            ?? (folderCandidates.count == 1 ? folderCandidates[0] : nil)
        let fileDescriptor = rules.resolvedDescriptor(
            sampleInput: fallbackFileSampleInput,
            sampleTags: parsed.substrateTags,
            fallback: nil
        )
        let fileToken = fileDescriptor.flatMap(rules.renderFileToken(from:))

        var resolutions: [SpinLabDomain.RouteChannelResolution] = []
        var unresolvedChannels: [String] = []

        let hasChannelSampleSignal = parsed.channelHints.contains { channelHint in
            rules.hasSampleSignal(sampleInput: channelHint.sampleID, sampleTags: channelHint.tags)
        }

        if !hasChannelSampleSignal {
            if let fileToken {
                resolutions.append(
                    SpinLabDomain.RouteChannelResolution(
                        channel: "file",
                        sampleId: fileToken,
                        source: "fileToken",
                        tags: parsed.substrateTags
                    )
                )
            } else {
                unresolvedChannels.append("file")
            }

            for channelHint in parsed.channelHints {
                resolutions.append(
                    SpinLabDomain.RouteChannelResolution(
                        channel: channelHint.channel,
                        sampleId: nil,
                        source: "testInfoOnly",
                        tags: channelHint.testInfoTags
                    )
                )
            }
        } else {
            for channelHint in parsed.channelHints {
                let channelHasSampleSignal = rules.hasSampleSignal(
                    sampleInput: channelHint.sampleID,
                    sampleTags: channelHint.tags
                )

                if channelHasSampleSignal {
                    let channelToken = rules.resolvedFileToken(
                        sampleInput: channelHint.sampleID,
                        sampleTags: channelHint.tags,
                        fallback: fileDescriptor
                    )
                    let unresolvedExplanation = channelToken == nil
                        ? RoutingExplanationBook.unresolvedChannelSampleSignal()
                        : nil

                    resolutions.append(
                        SpinLabDomain.RouteChannelResolution(
                            channel: channelHint.channel,
                            sampleId: channelToken,
                            source: "channelToken",
                            tags: channelHint.tags,
                            warning: unresolvedExplanation?.message,
                            warningReason: unresolvedExplanation?.reason
                        )
                    )

                    if channelToken == nil {
                        unresolvedChannels.append(channelHint.channel)
                    }
                } else {
                    resolutions.append(
                        SpinLabDomain.RouteChannelResolution(
                            channel: channelHint.channel,
                            sampleId: nil,
                            source: "testInfoOnly",
                            tags: channelHint.testInfoTags
                        )
                    )
                }
            }
        }

        let groupedTargets = Dictionary(grouping: resolutions.compactMap { resolution -> (String, String)? in
            guard let sampleKey = resolution.sampleId else {
                return nil
            }
            return (sampleKey, resolution.channel)
        }, by: \.0)

        let targets = groupedTargets
            .map { sampleKey, entries in
                SpinLabDomain.RouteTarget(
                    sampleId: sampleKey,
                    channels: uniquePreservingOrder(entries.map { $0.1 }).sorted()
                )
            }
            .sorted { $0.sampleId < $1.sampleId }

        return SpinLabDomain.RoutePlan(
            // Route planner only emits routing candidates. Final verdict ownership is in
            // PendingRoutingSnapshotEvaluator after drawer matching.
            planningStatus: .reviewRequired,
            targets: targets,
            channelResolutions: resolutions,
            unresolvedChannels: uniquePreservingOrder(unresolvedChannels),
            conflicts: []
        )
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
