import Foundation

struct FilenameRuleParser {
    let ruleSet: FilenameRuleSet

    private static let rotationHintMap: [String: String] = [
        "90shift": "+90deg for I parallel B"
    ]

    private static func hardcodedRotationHint(from tokens: [String]) -> String? {
        tokens.compactMap { rotationHintMap[$0.lowercased()] }.first
    }

    private enum SampleKeySource: String {
        case file = "file"
        case folder = "folder"
        case channel = "channel"
        case scoreFallback = "score-fallback"
    }

    private enum SampleKeyScore {
        static let channel = 100
        static let file = 60
        static let folder = 45
    }

    private struct SampleKeyResolution {
        var key: String?
        var warnings: [String]
    }

    init(ruleSet: FilenameRuleSet) {
        self.ruleSet = ruleSet
    }

    func parse(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        let originalFileStem = fileURL.deletingPathExtension().lastPathComponent
        let originalParentName = fileURL.deletingLastPathComponent().lastPathComponent
        let originalGrandparentName = fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let fileStem = originalFileStem
        let parentName = originalParentName
        let grandparentName = originalGrandparentName

        let fileTokens = tokenize(fileStem)
        let fileScopeTokens = fileTokensBeforeFirstChannel(fileTokens)
        let parentTokens = tokenize(parentName)
        let grandparentTokens = tokenize(grandparentName)
        let conditionFileTokens = conditionTokens(from: fileTokens)
        let measurementMatch = ruleSet.measurementNameMatch(from: fileScopeTokens)

        // Scoped context: pre-channel file tokens + folder tokens.
        // Used for sample ID, measurement name, substrate tags — avoids pulling
        // channel-specific sample identifiers into global scope.
        let scopedContextTokens = tokensForSources(
            fileTokens: fileScopeTokens,
            parentTokens: parentTokens,
            grandparentTokens: grandparentTokens
        )
        let folderContextTokens = tokensForSources(
            fileTokens: [],
            parentTokens: parentTokens,
            grandparentTokens: grandparentTokens
        )
        let conditionFolderTokens = conditionTokens(from: folderContextTokens)

        // Full context: all file tokens + folder tokens.
        // Conditions (temperature, field, current, …) are experiment-global values
        // that may appear anywhere in the filename, including after channel markers.
        let fullContextTokens = tokensForSources(
            fileTokens: fileTokens,
            parentTokens: parentTokens,
            grandparentTokens: grandparentTokens
        )

        let fileSampleIDs = ruleSet.sampleIDs(from: fileScopeTokens)
        let folderSampleIDs = uniquePreservingOrder(
            ruleSet.sampleIDs(from: parentTokens)
                + ruleSet.sampleIDs(from: grandparentTokens)
        )
        let allSampleIDs = uniquePreservingOrder(fileSampleIDs + folderSampleIDs)

        let measurement = preferredValue(
            fileValue: measurementMatch?.value,
            folderValue: ruleSet.measurementName(from: folderContextTokens),
            fallbackValue: ruleSet.measurementName(from: scopedContextTokens)
        )
        let measurementTags = preferredTags(
            fileTags: uniquePreservingOrder(ruleSet.measurementTags(from: fileScopeTokens)),
            folderTags: uniquePreservingOrder(ruleSet.measurementTags(from: folderContextTokens))
        )
        let substrateTags = preferredTags(
            fileTags: uniquePreservingOrder(ruleSet.substrateTags(from: substrateTokens(from: fileScopeTokens))),
            folderTags: uniquePreservingOrder(ruleSet.substrateTags(from: substrateTokens(from: folderContextTokens)))
        )
        let fileConditionEvaluation = ruleSet.conditionEvaluation(from: conditionFileTokens)
        let folderConditionEvaluation = ruleSet.conditionEvaluation(from: conditionFolderTokens)
        let conditionEvaluation = mergedConditionEvaluation(
            fileEvaluation: fileConditionEvaluation,
            folderEvaluation: folderConditionEvaluation
        )
        let channelHints = channelHints(from: fileTokens)
        let fileSampleResolution = resolveFileSampleKey(
            fileSampleIDs: fileSampleIDs,
            folderSampleIDs: folderSampleIDs,
            channelHints: channelHints
        )
        var routingWarnings: [String] = []
        if let measurementMatch {
            routingWarnings = measurementMatch.ignoredLowerMatches.map { "Ignored lower match: \($0)" }
        }
        let fileSampleKey = fileSampleResolution.key
        let warnings = uniquePreservingOrder(
            ruleSet.loadWarnings
            + conditionEvaluation.warnings
            + fileSampleResolution.warnings
            + routingWarnings
            + conflictWarnings(fileSampleIDs: fileSampleIDs, folderSampleIDs: folderSampleIDs)
        )
        var conditionValues = conditionEvaluation.values
        if let harmonic = harmonicMetadata(from: fileTokens, workflowID: measurement) {
            conditionValues["harmonic"] = harmonic.value
        }
        var hintSources: [String: String] = [:]

        let fileSampleIDsWithSources = ruleSet.sampleIDsWithSources(from: fileScopeTokens)
        for (idx, item) in fileSampleIDsWithSources.enumerated() {
            if idx == 0 {
                hintSources["sampleID"] = item.ruleRef
            }
            hintSources["sampleID#\(idx)"] = item.ruleRef
        }

        let fileConditionWithSources = ruleSet.conditionEvaluationWithSources(from: conditionFileTokens)
        for (id, sourced) in fileConditionWithSources.sourcedValues {
            hintSources["condition.\(id)"] = sourced.ruleRef
        }
        // Folder-derived conditions: fill keys absent from file scope
        let folderConditionWithSources = ruleSet.conditionEvaluationWithSources(from: conditionFolderTokens)
        for (id, sourced) in folderConditionWithSources.sourcedValues where hintSources["condition.\(id)"] == nil {
            hintSources["condition.\(id)"] = sourced.ruleRef
        }

        let fileSubstrateWithSources = ruleSet.substrateTagsWithSources(from: substrateTokens(from: fileScopeTokens))
        if !fileSubstrateWithSources.isEmpty {
            for (idx, item) in fileSubstrateWithSources.enumerated() {
                hintSources["substrateTags[\(idx)]"] = item.ruleRef
            }
        } else {
            // preferredTags returns folder tags when file has none
            let folderSubstrateWithSources = ruleSet.substrateTagsWithSources(from: substrateTokens(from: folderContextTokens))
            for (idx, item) in folderSubstrateWithSources.enumerated() {
                hintSources["substrateTags[\(idx)]"] = item.ruleRef
            }
        }

        // Folder-derived sampleIDs: add sources for indices beyond file scope
        if hintSources["sampleID"] == nil {
            var seen: Set<String> = []
            let folderSIDsWithSrc = (ruleSet.sampleIDsWithSources(from: parentTokens)
                + ruleSet.sampleIDsWithSources(from: grandparentTokens))
                .filter { seen.insert($0.value).inserted }
            for (idx, item) in folderSIDsWithSrc.enumerated() {
                if idx == 0 { hintSources["sampleID"] = item.ruleRef }
                hintSources["sampleID#\(idx)"] = item.ruleRef
            }
        } else {
            let fileSampleIDSet = Set(fileSampleIDs)
            var seen: Set<String> = []
            let folderAdditions = (ruleSet.sampleIDsWithSources(from: parentTokens)
                + ruleSet.sampleIDsWithSources(from: grandparentTokens))
                .filter { seen.insert($0.value).inserted && !fileSampleIDSet.contains($0.value) }
            let offset = fileSampleIDsWithSources.count
            for (i, item) in folderAdditions.enumerated() {
                hintSources["sampleID#\(offset + i)"] = item.ruleRef
            }
        }

        // Single-channel promotion: fileSampleKey came from channel scope, not file/folder scope.
        // Neither of the passes above will have set hintSources["sampleID"], so backfill it here
        // so that buildRuleSnapshot can emit SidecarRuleSnapshot.fields.sampleID.
        if fileSampleKey != nil, hintSources["sampleID"] == nil,
           fileSampleIDs.isEmpty, folderSampleIDs.isEmpty, channelHints.count == 1 {
            var collectedChannelTokens: [String] = []
            var inChannel = false
            for token in fileTokens {
                if ruleSet.normalizeChannel(token) != nil {
                    inChannel = true
                    continue
                }
                if inChannel { collectedChannelTokens.append(token) }
            }
            hintSources["sampleID"] = ruleSet.sampleIDsWithSources(from: collectedChannelTokens).first?.ruleRef
                ?? "singleChannelPromotion"
        }

        if let measurementWithSource = ruleSet.measurementNameWithSource(from: fileScopeTokens) {
            hintSources["workflowID"] = measurementWithSource.ruleRef
            hintSources["measurementName"] = measurementWithSource.ruleRef
        }

        if let harmonic = harmonicMetadata(from: fileTokens, workflowID: measurement) {
            hintSources["condition.harmonic"] = harmonic.ruleRef
        }

        return SpinLabDomain.ParsedFilenameHints(
            batchName: fileSampleIDs.first,
            sampleName: sampleName(fileSampleKey: fileSampleKey, substrateTags: substrateTags),
            fileSampleKey: fileSampleKey,
            folderDerivedSampleKeys: folderSampleIDs,
            measurementName: measurement ?? fileStem,
            workflowID: measurement,
            sampleIDs: allSampleIDs,
            channelHints: channelHints,
            measurementTags: measurementTags,
            substrateTags: substrateTags,
            conditionValues: conditionValues,
            rotationHint: Self.hardcodedRotationHint(from: fullContextTokens),
            warnings: warnings,
            hintSources: hintSources
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

    private func conditionTokens(from tokens: [String]) -> [String] {
        var result = tokens
        guard tokens.count > 1 else {
            return result
        }

        for index in tokens.indices.dropLast() {
            let value = tokens[index]
            let unit = tokens[tokens.index(after: index)]
            guard isNumericToken(value), isUnitToken(unit) else {
                continue
            }
            result.append(value + unit)
        }
        return result
    }

    private func substrateTokens(from tokens: [String]) -> [String] {
        tokens.filter { token in
            !isDecimalNumericToken(token)
        }
    }

    private func isNumericToken(_ token: String) -> Bool {
        token.range(of: #"^-?\d+(?:\.\d+)?$"#, options: .regularExpression) != nil
    }

    private func isDecimalNumericToken(_ token: String) -> Bool {
        token.range(of: #"^-?\d+\.\d+$"#, options: .regularExpression) != nil
    }

    private func isUnitToken(_ token: String) -> Bool {
        token.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil
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

            let tags = uniquePreservingOrder(ruleSet.substrateTags(from: substrateTokens(from: collected)))
            let sampleID = sampleName(
                fileSampleKey: ruleSet.sampleIDs(from: collected).first,
                substrateTags: tags
            )
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

    private func resolveFileSampleKey(
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

        // Narrow promotion: only when no file/folder sample was found and exactly one channel has a sample.
        if fileSampleIDs.isEmpty, folderSampleIDs.isEmpty,
           channelHints.count == 1,
           let singleChannelSample = normalized(channelHints[0].sampleID) {
            return SampleKeyResolution(
                key: singleChannelSample,
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
        if winner.score < SampleKeyScore.file {
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
            scoreBySampleID[sampleID, default: 0] += SampleKeyScore.file
            sourcesBySampleID[sampleID, default: []].insert(.file)
        }
        for sampleID in folderSampleIDs {
            scoreBySampleID[sampleID, default: 0] += SampleKeyScore.folder
            sourcesBySampleID[sampleID, default: []].insert(.folder)
        }
        for sampleID in channelSampleIDs {
            scoreBySampleID[sampleID, default: 0] += SampleKeyScore.channel
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

    private func harmonicMetadata(from tokens: [String], workflowID: String?) -> (value: String, ruleRef: String)? {
        guard workflowID?.caseInsensitiveCompare("IV") == .orderedSame else {
            return nil
        }
        guard let harmonic = tokens.first(where: {
            $0.caseInsensitiveCompare("1w") == .orderedSame || $0.caseInsensitiveCompare("3w") == .orderedSame
        }) else {
            return nil
        }
        let normalized = harmonic.lowercased()
        return (normalized, "filename:harmonicToken@\(normalized)")
    }

    private func sampleName(fileSampleKey: String?, substrateTags: [String]) -> String? {
        guard let fileSampleKey else {
            return nil
        }
        guard !substrateTags.isEmpty else {
            return fileSampleKey
        }
        return "\(fileSampleKey) \(substrateTags.joined(separator: " "))"
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

    private func preferredValue(
        fileValue: String?,
        folderValue: String?,
        fallbackValue: String?
    ) -> String? {
        normalized(fileValue) ?? normalized(folderValue) ?? normalized(fallbackValue)
    }

    private func preferredTags(fileTags: [String], folderTags: [String]) -> [String] {
        if !fileTags.isEmpty {
            return fileTags
        }
        return folderTags
    }

    private func mergedConditionEvaluation(
        fileEvaluation: FilenameRuleSet.ExtraConditionEvaluation,
        folderEvaluation: FilenameRuleSet.ExtraConditionEvaluation
    ) -> FilenameRuleSet.ExtraConditionEvaluation {
        let allKeys = Set(fileEvaluation.values.keys).union(folderEvaluation.values.keys)
        var mergedValues: [String: String] = [:]
        for key in allKeys {
            if let fileValue = fileEvaluation.values[key] {
                mergedValues[key] = fileValue
            } else if let folderValue = folderEvaluation.values[key] {
                mergedValues[key] = folderValue
            }
        }

        return FilenameRuleSet.ExtraConditionEvaluation(
            values: mergedValues,
            warnings: uniquePreservingOrder(fileEvaluation.warnings + folderEvaluation.warnings)
        )
    }
}
