import Foundation

struct FilenameRuleParser {
    let ruleSet: FilenameRuleSet

    private enum SampleKeySource: String {
        case file = "file"
        case folder = "folder"
        case channel = "channel"
        case scoreFallback = "score-fallback"
    }

    private struct SampleKeyResolution {
        var key: String?
        var warnings: [String]
    }

    init(ruleSet: FilenameRuleSet) {
        self.ruleSet = ruleSet
    }

    func parse(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        let fileStem = fileURL.deletingPathExtension().lastPathComponent
        let parentName = fileURL.deletingLastPathComponent().lastPathComponent
        let grandparentName = fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent

        let fileTokens = tokenize(fileStem)
        let fileScopeTokens = fileTokensBeforeFirstChannel(fileTokens)
        let parentTokens = tokenize(parentName)
        let grandparentTokens = tokenize(grandparentName)

        // Scoped context: pre-channel file tokens + folder tokens.
        // Used for sample ID, measurement name, substrate tags — avoids pulling
        // channel-specific sample identifiers into global scope.
        let scopedContextTokens = tokensForSources(
            fileTokens: fileScopeTokens,
            parentTokens: parentTokens,
            grandparentTokens: grandparentTokens
        )

        // Full context: all file tokens + folder tokens.
        // Conditions (temperature, field, current, …) are experiment-global values
        // that may appear anywhere in the filename, including after channel markers.
        let fullContextTokens = tokensForSources(
            fileTokens: fileTokens,
            parentTokens: parentTokens,
            grandparentTokens: grandparentTokens
        )

        let joined = joinedSourceText(
            fileStem: fileScopeTokens.joined(separator: " "),
            parentName: parentName,
            grandparentName: grandparentName
        )

        let fileSampleIDs = ruleSet.sampleIDs(from: fileScopeTokens)
        let folderSampleIDs = uniquePreservingOrder(
            ruleSet.sampleIDs(from: parentTokens)
                + ruleSet.sampleIDs(from: grandparentTokens)
        )
        let allSampleIDs = uniquePreservingOrder(fileSampleIDs + folderSampleIDs)

        let measurement = ruleSet.measurementName(from: scopedContextTokens, joined: joined)
        let measurementTags = uniquePreservingOrder(ruleSet.measurementTags(from: scopedContextTokens))
        let substrateTags = uniquePreservingOrder(ruleSet.substrateTags(from: scopedContextTokens))
        let extraConditionEvaluation = ruleSet.extraConditionEvaluation(from: fullContextTokens)
        let extraConditionValues = extraConditionEvaluation.values
        let channelHints = channelHints(from: fileTokens)
        let defaultSampleResolution = resolveDefaultSampleKey(
            fileSampleIDs: fileSampleIDs,
            folderSampleIDs: folderSampleIDs,
            channelHints: channelHints
        )
        let defaultSampleKey = defaultSampleResolution.key
        let warnings = uniquePreservingOrder(
            ruleSet.loadWarnings
                + extraConditionEvaluation.warnings
                + defaultSampleResolution.warnings
                + conflictWarnings(fileSampleIDs: fileSampleIDs, folderSampleIDs: folderSampleIDs)
        )

        return SpinLabDomain.ParsedFilenameHints(
            batchName: ruleSet.batchName(from: fileScopeTokens),
            sampleName: defaultSampleName(defaultSampleKey: defaultSampleKey, substrateTags: substrateTags),
            defaultSampleKey: defaultSampleKey,
            folderDerivedSampleKeys: folderSampleIDs,
            measurementName: measurement ?? fileStem,
            deviceName: ruleSet.deviceName(from: fullContextTokens),
            workflowID: measurement,
            sampleIDs: allSampleIDs,
            channelHints: channelHints,
            measurementTags: measurementTags,
            substrateTags: substrateTags,
            temperature: ruleSet.temperature(from: fullContextTokens),
            growthTemperature: nil,
            current: ruleSet.current(from: fullContextTokens),
            field: ruleSet.field(from: fullContextTokens),
            extraConditionValues: extraConditionValues,
            rotationHint: ruleSet.rotationHint(from: fullContextTokens),
            warnings: warnings
        )
    }

    private func tokenize(_ value: String) -> [String] {
        SampleTokenization.split(value, separators: ruleSet.tokenization.separators)
    }

    private func fileTokensBeforeFirstChannel(_ fileTokens: [String]) -> [String] {
        var collected: [String] = []
        for token in fileTokens {
            if ruleSet.normalizeChannel(token) != nil {
                break
            }
            collected.append(token)
        }
        return collected
    }

    private func tokensForSources(
        fileTokens: [String],
        parentTokens: [String],
        grandparentTokens: [String]
    ) -> [String] {
        var collected: [String] = []
        for source in ruleSet.sources {
            switch source {
            case .file:
                collected.append(contentsOf: fileTokens)
            case .parent:
                collected.append(contentsOf: parentTokens)
            case .grandparent:
                collected.append(contentsOf: grandparentTokens)
            }
        }
        return collected
    }

    private func joinedSourceText(fileStem: String, parentName: String, grandparentName: String) -> String {
        let parts: [String] = ruleSet.sources.map { source in
            switch source {
            case .file:
                return fileStem
            case .parent:
                return parentName
            case .grandparent:
                return grandparentName
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    private func channelHints(from fileTokens: [String]) -> [SpinLabDomain.ParsedChannelHint] {
        var hints: [SpinLabDomain.ParsedChannelHint] = []
        var index = 0

        while index < fileTokens.count {
            guard let normalizedChannel = ruleSet.normalizeChannel(fileTokens[index]) else {
                index += 1
                continue
            }

            var collected: [String] = []
            index += 1

            while index < fileTokens.count, ruleSet.normalizeChannel(fileTokens[index]) == nil {
                collected.append(fileTokens[index])
                index += 1
            }

            let sampleID = ruleSet.sampleIDs(from: collected).first
            let tags = uniquePreservingOrder(ruleSet.substrateTags(from: collected))
            let rawTestInfo = collected.filter { !isSampleSignalToken($0) }
            let testInfoTags = uniquePreservingOrder(ruleSet.measurementTags(from: collected) + rawTestInfo)
            hints.append(
                SpinLabDomain.ParsedChannelHint(
                    channel: normalizedChannel,
                    sampleID: sampleID,
                    tags: tags,
                    testInfoTags: testInfoTags
                )
            )
        }

        return hints
    }

    private func isSampleSignalToken(_ token: String) -> Bool {
        if !ruleSet.sampleIDs(from: [token]).isEmpty {
            return true
        }
        return !ruleSet.substrateTags(from: [token]).isEmpty
    }

    private func resolveDefaultSampleKey(
        fileSampleIDs: [String],
        folderSampleIDs: [String],
        channelHints: [SpinLabDomain.ParsedChannelHint]
    ) -> SampleKeyResolution {
        if fileSampleIDs.count == 1 {
            return SampleKeyResolution(
                key: fileSampleIDs[0],
                warnings: []
            )
        }

        if fileSampleIDs.isEmpty, folderSampleIDs.count == 1 {
            return SampleKeyResolution(
                key: folderSampleIDs[0],
                warnings: []
            )
        }

        if channelHints.count == 1 {
            return SampleKeyResolution(
                key: channelHints[0].sampleID,
                warnings: []
            )
        }

        let nonEmptyChannelSampleIDs = channelHints
            .compactMap { normalized($0.sampleID) }
        let scored = scoredSampleCandidates(
            fileSampleIDs: fileSampleIDs,
            folderSampleIDs: folderSampleIDs,
            channelSampleIDs: nonEmptyChannelSampleIDs
        )
        guard !scored.isEmpty else {
            return SampleKeyResolution(key: nil, warnings: [])
        }

        let topScore = scored.first?.score ?? 0
        let topCandidates = scored.filter { $0.score == topScore }
        if topCandidates.count != 1 {
            return SampleKeyResolution(
                key: nil,
                warnings: [
                    "Sample key arbitration is ambiguous (\(topCandidates.map(\.sampleID).joined(separator: ", "))); default sample key left empty."
                ]
            )
        }

        let winner = topCandidates[0]
        var warnings: [String] = []
        if winner.score < 100 {
            let sourceSummary = winner.sources.map(\.rawValue).sorted().joined(separator: "/")
            warnings.append(
                "Default sample key \(winner.sampleID) was selected via score fallback (\(winner.score)) from \(sourceSummary). Please review."
            )
        }
        return SampleKeyResolution(
            key: winner.sampleID,
            warnings: warnings
        )
    }

    private func scoredSampleCandidates(
        fileSampleIDs: [String],
        folderSampleIDs: [String],
        channelSampleIDs: [String]
    ) -> [(sampleID: String, score: Int, sources: Set<SampleKeySource>)] {
        var scoreBySampleID: [String: Int] = [:]
        var sourcesBySampleID: [String: Set<SampleKeySource>] = [:]

        for sampleID in fileSampleIDs {
            scoreBySampleID[sampleID, default: 0] += 100
            sourcesBySampleID[sampleID, default: []].insert(.file)
        }
        for sampleID in folderSampleIDs {
            scoreBySampleID[sampleID, default: 0] += 60
            sourcesBySampleID[sampleID, default: []].insert(.folder)
        }
        for sampleID in channelSampleIDs {
            scoreBySampleID[sampleID, default: 0] += 45
            sourcesBySampleID[sampleID, default: []].insert(.channel)
        }

        return scoreBySampleID
            .map { (sampleID: $0.key, score: $0.value, sources: sourcesBySampleID[$0.key] ?? [.scoreFallback]) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.sampleID < rhs.sampleID
                }
                return lhs.score > rhs.score
            }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func defaultSampleName(defaultSampleKey: String?, substrateTags: [String]) -> String? {
        guard let defaultSampleKey else {
            return nil
        }
        guard !substrateTags.isEmpty else {
            return defaultSampleKey
        }
        return "\(defaultSampleKey) \(substrateTags.joined(separator: " "))"
    }

    private func conflictWarnings(fileSampleIDs: [String], folderSampleIDs: [String]) -> [String] {
        guard !fileSampleIDs.isEmpty, !folderSampleIDs.isEmpty else {
            return []
        }

        let fileSet = Set(fileSampleIDs.map { $0.uppercased() })
        let folderSet = Set(folderSampleIDs.map { $0.uppercased() })
        guard fileSet.isDisjoint(with: folderSet) else {
            return []
        }

        return [
            "Filename sample IDs (\(fileSampleIDs.joined(separator: ", "))) conflict with parent-folder sample IDs (\(folderSampleIDs.joined(separator: ", ")))."
        ]
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
