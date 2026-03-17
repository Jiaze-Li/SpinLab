import Foundation

struct FilenameRuleParser {
    func parse(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        let fileStem = fileURL.deletingPathExtension().lastPathComponent
        let parentName = fileURL.deletingLastPathComponent().lastPathComponent
        let grandparentName = fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent

        let fileTokens = tokenize(fileStem)
        let parentTokens = tokenize(parentName)
        let grandparentTokens = tokenize(grandparentName)
        let contextTokens = fileTokens + parentTokens + grandparentTokens

        let fileSampleIDs = SampleIDParser.extractSampleIDs(fromTokens: fileTokens)
        let folderSampleIDs = uniquePreservingOrder(
            SampleIDParser.extractSampleIDs(fromTokens: parentTokens)
                + SampleIDParser.extractSampleIDs(fromTokens: grandparentTokens)
        )
        let allSampleIDs = uniquePreservingOrder(fileSampleIDs + folderSampleIDs)

        let measurement = measurementName(from: fileStem, parentName: parentName, grandparentName: grandparentName, tokens: contextTokens)
        let measurementTags = measurementTags(from: contextTokens)
        let substrateTags = substrateTags(from: contextTokens)
        let channelHints = channelHints(from: fileTokens)
        let warnings = conflictWarnings(fileSampleIDs: fileSampleIDs, folderSampleIDs: folderSampleIDs)

        return SpinLabDomain.ParsedFilenameHints(
            batchName: batchName(from: fileTokens),
            sampleName: defaultSampleName(
                fileSampleIDs: fileSampleIDs,
                folderSampleIDs: folderSampleIDs,
                channelHints: channelHints,
                substrateTags: substrateTags
            ),
            measurementName: measurement ?? fileStem,
            deviceName: contextTokens.contains(where: { $0.caseInsensitiveCompare("wafer") == .orderedSame }) ? "wafer" : nil,
            workflowName: nil,
            sampleIDs: allSampleIDs,
            channelHints: channelHints,
            measurementTags: measurementTags,
            substrateTags: substrateTags,
            temperature: firstMatch(in: contextTokens, pattern: #"^\d+K$"#),
            growthTemperature: nil,
            current: firstMatch(in: contextTokens, pattern: #"^\d+(?:\.\d+)?mA$"#),
            field: firstMatch(in: contextTokens, pattern: #"^-?\d+T$"#),
            rotationHint: rotationHint(from: contextTokens),
            warnings: warnings
        )
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .split(whereSeparator: { "_- ()".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func measurementName(from fileStem: String, parentName: String, grandparentName: String, tokens: [String]) -> String? {
        let joined = [fileStem, parentName, grandparentName].joined(separator: " ").lowercased()

        if joined.contains("xy") || joined.contains("rotation") {
            return "XY"
        }

        if tokens.contains(where: { $0.caseInsensitiveCompare("MR") == .orderedSame }) {
            return "MR"
        }

        if tokens.contains(where: { $0.caseInsensitiveCompare("RT") == .orderedSame }) {
            return "RT"
        }

        if tokens.contains(where: { $0.caseInsensitiveCompare("AHE") == .orderedSame }) {
            return "AHE"
        }

        return nil
    }

    private func measurementTags(from tokens: [String]) -> [String] {
        let aliases: [String: String] = [
            "AMR": "AMR",
            "PHE": "PHE",
            "RXX": "Rxx",
            "RXY": "Rxy"
        ]

        return uniquePreservingOrder(
            tokens.compactMap { token in
                aliases[token.uppercased()]
            }
        )
    }

    private func substrateTags(from tokens: [String]) -> [String] {
        var collected: [String] = []

        for token in tokens {
            let normalized = token.uppercased()

            if normalized == "HF" || normalized.contains("HF") {
                collected.append("HF")
            }

            if normalized == "BAKE" || normalized == "BAKED" || normalized.contains("BAKE") {
                collected.append("baked")
            }

            if normalized == "O" || normalized.contains("ORIGIN") || normalized.contains("ORIGINAL") {
                collected.append("origin")
            }

            if normalized.contains("STO111") {
                collected.append("STO111")
            } else if normalized.contains("STO001") {
                collected.append("STO001")
            } else if normalized == "STO" || normalized.contains("STO") {
                collected.append("STO")
            }

            if normalized == "NGO" || normalized.contains("NGO") {
                collected.append("NGO")
            }

            if normalized == "111" {
                collected.append("111")
            }

            if normalized == "001" {
                collected.append("001")
            }
        }

        return uniquePreservingOrder(collected)
    }

    private func channelHints(from fileTokens: [String]) -> [SpinLabDomain.ParsedChannelHint] {
        var hints: [SpinLabDomain.ParsedChannelHint] = []
        var index = 0

        while index < fileTokens.count {
            guard let normalizedChannel = normalizeChannel(fileTokens[index]) else {
                index += 1
                continue
            }

            var collected: [String] = []
            index += 1

            while index < fileTokens.count, normalizeChannel(fileTokens[index]) == nil {
                collected.append(fileTokens[index])
                index += 1
            }

            let sampleID = SampleIDParser.extractSampleIDs(fromTokens: collected).first
            let tags = uniquePreservingOrder(substrateTags(from: collected) + measurementTags(from: collected))
            hints.append(
                SpinLabDomain.ParsedChannelHint(
                    channel: normalizedChannel,
                    sampleID: sampleID,
                    tags: tags
                )
            )
        }

        return hints
    }

    private func normalizeChannel(_ token: String) -> String? {
        switch token.lowercased() {
        case "ch1", "c1":
            return "ch1"
        case "ch2", "c2":
            return "ch2"
        case "ch3", "c3":
            return "ch3"
        default:
            return nil
        }
    }

    private func batchName(from tokens: [String]) -> String? {
        SampleIDParser.extractSampleIDs(fromTokens: tokens).first
            ?? tokens.first(where: { $0.range(of: #"^(B|Batch)\d+$"#, options: .regularExpression) != nil })
    }

    private func defaultSampleName(
        fileSampleIDs: [String],
        folderSampleIDs: [String],
        channelHints: [SpinLabDomain.ParsedChannelHint],
        substrateTags: [String]
    ) -> String? {
        func composed(_ sampleID: String) -> String {
            guard !substrateTags.isEmpty else {
                return sampleID
            }
            return "\(sampleID) \(substrateTags.joined(separator: " "))"
        }

        if fileSampleIDs.count == 1 {
            return composed(fileSampleIDs[0])
        }

        if fileSampleIDs.isEmpty, folderSampleIDs.count == 1 {
            return composed(folderSampleIDs[0])
        }

        if channelHints.count == 1 {
            guard let sampleID = channelHints[0].sampleID else {
                return nil
            }
            return composed(sampleID)
        }

        return nil
    }

    private func rotationHint(from tokens: [String]) -> String? {
        tokens.contains(where: { $0.caseInsensitiveCompare("90shift") == .orderedSame }) ? "+90deg for I parallel B" : nil
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

    private func firstMatch(in tokens: [String], pattern: String) -> String? {
        tokens.first(where: { $0.range(of: pattern, options: .regularExpression) != nil })
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
