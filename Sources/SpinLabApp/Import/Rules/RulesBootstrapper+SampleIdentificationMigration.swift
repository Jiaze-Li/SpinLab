import Foundation

extension RulesBootstrapper {

    static func migrateSampleIdentificationIfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        guard let substrate = json["substrate"] as? [String: Any] else {
            throw NSError(domain: "RulesBootstrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "sample_identification missing substrate"])
        }
        let hasShared = substrate["shared"] != nil
        let isV1 = hasShared
        guard isV1 else { return json }

        guard let shared = substrate["shared"] as? [String: Any] else {
            throw NSError(domain: "RulesBootstrapper", code: 2, userInfo: [NSLocalizedDescriptionKey: "sample_identification v1 missing substrate.shared"])
        }

        let sampleId = (json["sampleId"] as? [String: Any]) ?? [:]
        let substrateTagRules = (substrate["substrateTagRules"] as? [[String: Any]]) ?? []
        let tokenSeparators = (shared["tokenSeparators"] as? String) ?? ""
        let materialTokens = stringArray(shared["materialTokens"])
        let materialAliases = stringDictionary(shared["materialAliases"])
        let materialDisplayNames = stringDictionary(shared["materialDisplayNames"])
        let treatmentKeywords = stringArrayDictionary(shared["treatmentKeywords"])
        let originStandaloneTokens = stringArray(shared["originStandaloneTokens"])
        let originContainsTokens = stringArray(shared["originContainsTokens"])
        let orientationTokens = stringArray(shared["orientationTokens"])
        let orientationAliases = stringDictionary(shared["orientationAliases"])
        let orientationPattern = (shared["orientationPattern"] as? String) ?? ""

        var materialRowsByID: [String: (tokens: [String], aliases: [String], displayName: String)] = [:]
        var materialOrder: [String] = []
        for token in materialTokens {
            if materialRowsByID[token] == nil {
                materialOrder.append(token)
            }
            materialRowsByID[token] = (
                tokens: [token],
                aliases: [],
                displayName: materialDisplayNames[token] ?? token
            )
        }
        for (alias, canonicalID) in materialAliases {
            if materialRowsByID[canonicalID] == nil {
                materialRowsByID[canonicalID] = (
                    tokens: [canonicalID],
                    aliases: [],
                    displayName: materialDisplayNames[canonicalID] ?? canonicalID
                )
                materialOrder.append(canonicalID)
            }
            if materialRowsByID[canonicalID]?.aliases.contains(alias) == false {
                materialRowsByID[canonicalID]?.aliases.append(alias)
            }
        }
        let materials: [[String: Any]] = materialOrder.compactMap { id in
            guard let row = materialRowsByID[id] else { return nil }
            return [
                "id": id,
                "tokens": row.tokens,
                "aliases": row.aliases.sorted(),
                "displayName": row.displayName
            ]
        }

        var treatments: [[String: Any]] = []
        for id in treatmentKeywords.keys.sorted() {
            let keywords = treatmentKeywords[id] ?? []
            let standalone = id == "o" ? originStandaloneTokens : []
            let contains = id == "o" ? originContainsTokens : []
            treatments.append([
                "id": id,
                "displayName": id,
                "keywords": keywords,
                "standaloneTokens": standalone,
                "containsTokens": contains
            ])
        }

        var orientationRowsByID: [String: (tokens: [String], aliases: [String])] = [:]
        var orientationOrder: [String] = []
        for token in orientationTokens {
            if orientationRowsByID[token] == nil {
                orientationOrder.append(token)
            }
            orientationRowsByID[token] = (tokens: [token], aliases: [])
        }
        for (alias, canonicalID) in orientationAliases {
            if orientationRowsByID[canonicalID] == nil {
                orientationRowsByID[canonicalID] = (tokens: [canonicalID], aliases: [])
                orientationOrder.append(canonicalID)
            }
            if orientationRowsByID[canonicalID]?.aliases.contains(alias) == false {
                orientationRowsByID[canonicalID]?.aliases.append(alias)
            }
        }
        let orientationRows: [[String: Any]] = orientationOrder.compactMap { id in
            guard let row = orientationRowsByID[id] else { return nil }
            return [
                "id": id,
                "tokens": row.tokens,
                "aliases": row.aliases.sorted()
            ]
        }
        if orientationRows.isEmpty {
            warnings.append("sample_identification: orientation rows empty after migration")
        }

        return [
            "version": 2,
            "sampleId": sampleId,
            "substrate": [
                "tokenSeparators": tokenSeparators,
                "substrateTagRules": substrateTagRules,
                "materials": materials,
                "treatments": treatments,
                "orientations": [
                    "pattern": orientationPattern,
                    "rows": orientationRows
                ]
            ]
        ]
    }

    static func migrateSampleIdentificationV2ToV3IfNeeded(
        json: [String: Any],
        tokenizationJSON: [String: Any]?,
        warnings: inout [String]
    ) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 3 else { return json }

        var migrated = json
        migrated["version"] = 3

        guard var substrate = migrated["substrate"] as? [String: Any] else {
            return migrated
        }

        if let substrateSeparators = substrate["tokenSeparators"] as? String {
            let tokenizationSeparators: String?
            if let tokenizationJSON,
               let tokenization = tokenizationJSON["tokenization"] as? [String: Any] {
                tokenizationSeparators = tokenization["separators"] as? String
            } else {
                tokenizationSeparators = nil
            }

            if let tokenizationSeparators, tokenizationSeparators != substrateSeparators {
                warnings.append(
                    "sample_identification: substrate.tokenSeparators=\"\(substrateSeparators)\" differs from filename_tokenization.separators=\"\(tokenizationSeparators)\"; substrate detection will follow filename_tokenization after migration"
                )
            } else if tokenizationSeparators == nil {
                warnings.append(
                    "sample_identification: substrate.tokenSeparators=\"\(substrateSeparators)\" dropped; filename_tokenization not found, substrate detection will use loaded tokenization at runtime"
                )
            }
        }

        substrate.removeValue(forKey: "tokenSeparators")
        migrated["substrate"] = substrate
        return migrated
    }

    static func migrateSampleIdentificationV3ToV4IfNeeded(
        json: [String: Any],
        warnings: inout [String]
    ) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 4 else { return json }

        let sampleId = (json["sampleId"] as? [String: Any]) ?? [:]
        let patterns = sampleId["patterns"] as? [String] ?? []
        let patternRegex = try NSRegularExpression(pattern: #"^\^(.+)\\d\+\$$"#)
        let prefixRegex = try NSRegularExpression(pattern: #"^[A-Za-z0-9_-]+$"#)
        var batchPrefixes: [String] = []
        var seenBatchPrefixes = Set<String>()

        for pattern in patterns {
            let range = NSRange(pattern.startIndex..<pattern.endIndex, in: pattern)
            guard let match = patternRegex.firstMatch(in: pattern, options: [], range: range),
                  let bodyRange = Range(match.range(at: 1), in: pattern) else {
                warnings.append("sample_identification: sampleId.patterns '\(pattern)' could not be converted to batchPrefixes and was discarded")
                continue
            }

            var body = String(pattern[bodyRange])
            if body.hasPrefix("(?:"), body.hasSuffix(")") {
                body.removeFirst(3)
                body.removeLast()
            }
            let candidates = body.split(separator: "|").map(String.init)

            var hasValidPrefix = false
            for candidate in candidates {
                let candidateRange = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                guard prefixRegex.firstMatch(in: candidate, options: [], range: candidateRange) != nil else {
                    warnings.append("sample_identification: sampleId.patterns '\(pattern)' could not be converted to batchPrefixes and was discarded")
                    continue
                }
                if seenBatchPrefixes.insert(candidate).inserted {
                    batchPrefixes.append(candidate)
                }
                hasValidPrefix = true
            }

            if !hasValidPrefix {
                warnings.append("sample_identification: sampleId.patterns '\(pattern)' could not be converted to batchPrefixes and was discarded")
            }
        }

        let substrate = (json["substrate"] as? [String: Any]) ?? [:]
        let materials = substrate["materials"] as? [[String: Any]] ?? []
        let treatments = substrate["treatments"] as? [[String: Any]] ?? []
        let orientationsDict = substrate["orientations"] as? [String: Any] ?? [:]
        let orientationRows = orientationsDict["rows"] as? [[String: Any]] ?? []
        let substrateTagRules = substrate["substrateTagRules"] as? [[String: Any]] ?? []

        var newMaterials: [[String: Any]] = []
        for entry in materials {
            let id = entry["id"] as? String ?? ""
            let displayName: String
            if let explicit = entry["displayName"] as? String, !explicit.isEmpty {
                displayName = explicit
            } else {
                displayName = id
            }
            guard !displayName.isEmpty else {
                warnings.append("sample_identification: substrate.materials entry missing displayName/id and was skipped")
                continue
            }

            let tokens = entry["tokens"] as? [String] ?? []
            let aliases = entry["aliases"] as? [String] ?? []
            var matches: [[String: String]] = []
            var seen = Set<String>()
            for value in (tokens + aliases) where !value.isEmpty {
                let key = value.lowercased()
                if seen.insert(key).inserted {
                    matches.append(["type": "equals", "value": value])
                }
            }
            newMaterials.append([
                "displayName": displayName,
                "matches": matches
            ])
        }

        var newTreatments: [[String: Any]] = []
        for entry in treatments {
            let id = entry["id"] as? String ?? ""
            let displayName: String
            if let explicit = entry["displayName"] as? String, !explicit.isEmpty {
                displayName = explicit
            } else {
                displayName = id
            }
            guard !displayName.isEmpty else {
                warnings.append("sample_identification: substrate.treatments entry missing displayName/id and was skipped")
                continue
            }

            var matches: [[String: String]] = []
            var seenEquals = Set<String>()
            var seenContains = Set<String>()

            let standaloneTokens = entry["standaloneTokens"] as? [String] ?? []
            for value in standaloneTokens where !value.isEmpty {
                let key = value.lowercased()
                if seenEquals.insert(key).inserted {
                    matches.append(["type": "equals", "value": value])
                }
            }

            let containsTokens = entry["containsTokens"] as? [String] ?? []
            for value in containsTokens where !value.isEmpty {
                let key = value.lowercased()
                if seenContains.insert(key).inserted {
                    matches.append(["type": "contains", "value": value])
                }
            }

            let keywords = entry["keywords"] as? [String] ?? []
            for value in keywords where !value.isEmpty {
                let key = value.lowercased()
                // Single-character legacy keywords migrate to `equals` to preserve token-level
                // semantics; `contains` on a single char would misclassify any token sharing
                // that letter as this treatment.
                if value.count == 1 {
                    if seenEquals.insert(key).inserted {
                        matches.append(["type": "equals", "value": value])
                    }
                } else if seenContains.insert(key).inserted {
                    matches.append(["type": "contains", "value": value])
                }
            }

            newTreatments.append([
                "displayName": displayName,
                "matches": matches
            ])
        }

        if orientationsDict["pattern"] != nil {
            warnings.append("sample_identification: orientations.pattern dropped during v3→v4 migration; individual row tokens/aliases are preserved as equals matches")
        }

        var newOrientations: [[String: Any]] = []
        for row in orientationRows {
            let id = row["id"] as? String ?? ""
            guard !id.isEmpty else {
                warnings.append("sample_identification: substrate.orientations row missing id and was skipped")
                continue
            }
            let displayName = id
            let tokens = row["tokens"] as? [String] ?? []
            let aliases = row["aliases"] as? [String] ?? []
            var matches: [[String: String]] = []
            var seen = Set<String>()
            for value in (tokens + aliases) where !value.isEmpty {
                let key = value.lowercased()
                if key == displayName.lowercased() {
                    continue
                }
                if seen.insert(key).inserted {
                    matches.append(["type": "equals", "value": value])
                }
            }
            newOrientations.append([
                "displayName": displayName,
                "matches": matches
            ])
        }

        for rule in substrateTagRules {
            let ruleDescription = (rule["tag"] as? String) ?? "\(rule)"
            warnings.append("sample_identification: substrateTagRule '\(ruleDescription)' removed; equivalent behavior now comes from treatments/materials/orientations matches")
        }
        if !substrateTagRules.isEmpty {
            warnings.append("sample_identification: \(substrateTagRules.count) substrateTagRule(s) removed in v3→v4 migration")
        }

        var newSampleId: [String: Any] = [:]
        for (key, value) in sampleId where key != "patterns" {
            newSampleId[key] = value
        }
        newSampleId["batchPrefixes"] = batchPrefixes

        let newSubstrate: [String: Any] = [
            "materials": newMaterials,
            "treatments": newTreatments,
            "orientations": newOrientations
        ]

        return [
            "version": 4,
            "sampleId": newSampleId,
            "substrate": newSubstrate
        ]
    }

    static func migrateSampleIdentificationV4ToV5IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 5 else { return json }

        var migrated = json
        migrated["version"] = 5

        let sampleId = (json["sampleId"] as? [String: Any]) ?? [:]
        let batchPrefixes = (sampleId["batchPrefixes"] as? [String]) ?? []
        let validPrefixPattern = try NSRegularExpression(pattern: #"^[A-Za-z0-9_-]+$"#)
        var matches: [[String: String]] = []
        for prefix in batchPrefixes {
            let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard validPrefixPattern.firstMatch(in: trimmed, options: [], range: range) != nil else {
                warnings.append("sample_identification: batch prefix '\(trimmed)' is invalid and was skipped")
                continue
            }
            matches.append(["type": "starts-with", "value": trimmed])
        }

        var newSampleId: [String: Any] = [:]
        for (key, value) in sampleId where key != "batchPrefixes" && key != "patterns" {
            newSampleId[key] = value
        }
        newSampleId["matches"] = matches
        migrated["sampleId"] = newSampleId

        return migrated
    }

    // MARK: - Private helpers (only used within this extension file)

    private static func stringArray(_ any: Any?) -> [String] {
        guard let values = any as? [String] else { return [] }
        return values
    }

    private static func stringDictionary(_ any: Any?) -> [String: String] {
        guard let values = any as? [String: String] else { return [:] }
        return values
    }

    private static func stringArrayDictionary(_ any: Any?) -> [String: [String]] {
        guard let values = any as? [String: [String]] else { return [:] }
        return values
    }
}
