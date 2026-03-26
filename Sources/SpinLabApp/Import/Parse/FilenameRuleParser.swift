import Foundation

struct FilenameRuleParser {
    let ruleSet: FilenameRuleSet

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
        let contextTokens = tokensForSources(
            fileTokens: fileScopeTokens,
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

        let measurement = ruleSet.measurementName(from: contextTokens, joined: joined)
        let measurementTags = uniquePreservingOrder(ruleSet.measurementTags(from: contextTokens))
        let substrateTags = uniquePreservingOrder(ruleSet.substrateTags(from: contextTokens))
        let channelHints = channelHints(from: fileTokens)
        let defaultSampleKey = defaultSampleKey(
            fileSampleIDs: fileSampleIDs,
            folderSampleIDs: folderSampleIDs,
            channelHints: channelHints
        )
        let warnings = uniquePreservingOrder(
            ruleSet.loadWarnings
                + conflictWarnings(fileSampleIDs: fileSampleIDs, folderSampleIDs: folderSampleIDs)
        )

        return SpinLabDomain.ParsedFilenameHints(
            batchName: ruleSet.batchName(from: fileScopeTokens),
            sampleName: defaultSampleName(defaultSampleKey: defaultSampleKey, substrateTags: substrateTags),
            defaultSampleKey: defaultSampleKey,
            folderDerivedSampleKeys: folderSampleIDs,
            measurementName: measurement ?? fileStem,
            deviceName: ruleSet.deviceName(from: contextTokens),
            workflowName: measurement,
            sampleIDs: allSampleIDs,
            channelHints: channelHints,
            measurementTags: measurementTags,
            substrateTags: substrateTags,
            temperature: ruleSet.temperature(from: contextTokens),
            growthTemperature: nil,
            current: ruleSet.current(from: contextTokens),
            field: ruleSet.field(from: contextTokens),
            rotationHint: ruleSet.rotationHint(from: contextTokens),
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

    private func defaultSampleKey(
        fileSampleIDs: [String],
        folderSampleIDs: [String],
        channelHints: [SpinLabDomain.ParsedChannelHint]
    ) -> String? {
        if fileSampleIDs.count == 1 {
            return fileSampleIDs[0]
        }

        if fileSampleIDs.isEmpty, folderSampleIDs.count == 1 {
            return folderSampleIDs[0]
        }

        if channelHints.count == 1 {
            return channelHints[0].sampleID
        }

        return nil
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
