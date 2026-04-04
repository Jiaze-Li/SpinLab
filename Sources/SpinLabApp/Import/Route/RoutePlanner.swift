import Foundation

struct SpinLabRoutePlanner {
    private let rules = FileRoutingRuleBook()

    func makeRoutePlan(from parsed: SpinLabDomain.ParsedFilenameHints) -> SpinLabDomain.RoutePlan {
        let folderCandidates = uniquePreservingOrder(parsed.folderDerivedSampleKeys)
        let fallbackFileSampleInput = rules.normalizedSampleInput(parsed.defaultSampleKey)
            ?? (folderCandidates.count == 1 ? rules.normalizedSampleInput(folderCandidates[0]) : nil)
        let fileDescriptor = rules.resolvedDescriptor(
            sampleInput: fallbackFileSampleInput,
            sampleTags: fallbackFileSampleInput == nil ? [] : parsed.substrateTags,
            fallback: nil
        )
        let fileToken = fileDescriptor.flatMap(rules.renderFileToken(from:))

        var resolutions: [SpinLabDomain.RouteChannelResolution] = []
        var unresolvedChannels: [String] = []

        let hasChannelSampleSignal = parsed.channelHints.contains { channelHint in
            channelSignal(
                for: channelHint,
                fileDescriptor: fileDescriptor
            ).hasSignal
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
                let signal = channelSignal(
                    for: channelHint,
                    fileDescriptor: fileDescriptor
                )

                if signal.hasSignal {
                    if let explicitSampleInput = signal.explicitSampleInput {
                        resolutions.append(
                            SpinLabDomain.RouteChannelResolution(
                                channel: channelHint.channel,
                                sampleId: explicitSampleInput,
                                source: "channelToken",
                                tags: channelHint.tags
                            )
                        )
                    } else if let channelProcessingToken = signal.processingOnlyToken {
                        resolutions.append(
                            SpinLabDomain.RouteChannelResolution(
                                channel: channelHint.channel,
                                sampleId: channelProcessingToken,
                                source: "channelToken",
                                tags: channelHint.tags
                            )
                        )
                    } else if let channelToken = signal.channelTokenWithFallback {
                        resolutions.append(
                            SpinLabDomain.RouteChannelResolution(
                                channel: channelHint.channel,
                                sampleId: channelToken,
                                source: "channelToken",
                                tags: channelHint.tags
                            )
                        )
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

    private func processingOnlyToken(from sampleTags: [String]) -> String? {
        guard let descriptor = rules.resolvedDescriptor(sampleInput: nil, sampleTags: sampleTags, fallback: nil) else {
            return nil
        }
        guard descriptor.batch == nil,
              descriptor.material == nil,
              descriptor.orientation == nil,
              !descriptor.processingTokens.isEmpty else {
            return nil
        }
        return rules.renderFileToken(from: descriptor)
    }

    private func channelSignal(
        for channelHint: SpinLabDomain.ParsedChannelHint,
        fileDescriptor: SampleSemanticDescriptor?
    ) -> ChannelSignal {
        let explicit = rules.normalizedSampleInput(channelHint.sampleID)
        let processingOnly = processingOnlyToken(from: channelHint.tags)
        let channelTagSignal = rules.hasSampleSignal(sampleInput: nil, sampleTags: channelHint.tags)
        let tokenWithFallback = rules.resolvedFileToken(
            sampleInput: channelHint.sampleID,
            sampleTags: channelHint.tags,
            fallback: fileDescriptor
        )
        let hasSignal = explicit != nil
            || processingOnly != nil
            || (channelTagSignal && fileDescriptor != nil && tokenWithFallback != nil)
        return ChannelSignal(
            explicitSampleInput: explicit,
            processingOnlyToken: processingOnly,
            channelTokenWithFallback: tokenWithFallback,
            hasSignal: hasSignal
        )
    }
}

private struct ChannelSignal {
    let explicitSampleInput: String?
    let processingOnlyToken: String?
    let channelTokenWithFallback: String?
    let hasSignal: Bool
}
