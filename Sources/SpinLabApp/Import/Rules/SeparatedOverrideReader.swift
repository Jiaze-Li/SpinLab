import Foundation

/// Shared reader for the 5 separated override JSON files.
/// Both `RuleLoader` and `ConditionRulesHandbookStore` delegate their read paths here
/// to ensure a single source of truth for parsing semantics.
enum SeparatedOverrideReader {

    // MARK: - sample_id_rules.json

    static func readSampleIDPatterns(from url: URL) -> [String]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let patterns = json["patterns"] as? [String] else {
            return nil
        }
        let normalized = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - workflow_match_rules.json

    static func readWorkflowMatchRules(from url: URL) -> [WorkflowMatchRuleEntry]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [[String: Any]] else {
            return nil
        }
        return rules.compactMap { decodeWorkflowMatchRule($0) }
    }

    // MARK: - conditions_rules.json

    static func readConditions(from url: URL) -> SeparatedConditionsPatch? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var setValues: [String: String] = [:]
        var deletedKeys: Set<String> = []
        if let extraConditions = json["extraConditions"] as? [String: Any] {
            for (rawKey, rawValue) in extraConditions {
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                if rawValue is NSNull {
                    deletedKeys.insert(key)
                    continue
                }
                guard let value = rawValue as? String else { continue }
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                setValues[key] = normalized
            }
        }

        var tokenMaps: [String: [TokenMapping]] = [:]
        if let tokenMapRules = json["tokenMapRules"] as? [String: Any] {
            for (rawKey, rawRules) in tokenMapRules {
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty,
                      let rawList = rawRules as? [[String: Any]] else { continue }
                let mappings: [TokenMapping] = rawList.compactMap { raw -> TokenMapping? in
                    guard let typeRaw = raw["matchType"] as? String,
                          let matchType = TokenMatchType(rawValue: typeRaw),
                          let pattern = (raw["pattern"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !pattern.isEmpty else {
                        return nil
                    }
                    let rawValue = (raw["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = (rawValue?.isEmpty == false) ? rawValue! : "$MATCH"
                    return TokenMapping(matchType: matchType, pattern: pattern, value: value)
                }
                tokenMaps[key] = mappings
            }
        }

        return SeparatedConditionsPatch(
            extraConditions: setValues,
            deletedExtraConditionKeys: deletedKeys,
            tokenMapRules: tokenMaps
        )
    }

    // MARK: - substrate_rules.json

    static func readSubstrateRules(from url: URL) -> SeparatedSubstratePatch? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var parsedTagRules: [MatchRuleEntry]?
        if let rawRules = json["substrateTagRules"] as? [[String: Any]] {
            parsedTagRules = rawRules.compactMap { decodeMapRuleEntry($0) }
        }

        var parsedSharedSubstrate: FilenameRuleSet.SharedSubstrateRules?
        if let rawShared = json["sharedSubstrate"] {
            if let fragmentData = try? JSONSerialization.data(withJSONObject: rawShared),
               let payload = try? JSONDecoder().decode(ConditionRulesHandbookStore.SharedSubstratePayload.self, from: fragmentData) {
                parsedSharedSubstrate = payload.asRuleSetValue
            }
        }

        guard parsedTagRules != nil || parsedSharedSubstrate != nil else {
            return nil
        }
        return SeparatedSubstratePatch(
            substrateTagRules: parsedTagRules,
            sharedSubstrate: parsedSharedSubstrate
        )
    }

    // MARK: - measurement_tag_rules.json

    static func readMeasurementTagRules(from url: URL) -> [MatchRuleEntry]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [[String: Any]] else {
            return nil
        }
        return rules.compactMap { decodeMapRuleEntry($0) }
    }

    // MARK: - Shared decode helpers

    static func decodeMapRuleEntry(_ raw: [String: Any]) -> MatchRuleEntry? {
        guard let rawMatch = raw["match"] as? [String: Any],
              let scopeRaw = rawMatch["scope"] as? String,
              let typeRaw = rawMatch["type"] as? String,
              let scope = FilenameRuleSet.MatchScope(rawValue: scopeRaw),
              let type = FilenameRuleSet.MatchType(rawValue: typeRaw) else {
            return nil
        }

        let values = ((rawMatch["values"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let single = (rawMatch["value"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchValues = values.isEmpty ? (single.map { [$0] } ?? []) : values
        guard !matchValues.isEmpty else { return nil }

        let rawValue = (raw["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (rawValue?.isEmpty == false) ? rawValue! : "$MATCH"
        return MatchRuleEntry(
            scope: scope,
            type: type,
            matchValues: matchValues,
            value: value
        )
    }

    static func decodeWorkflowMatchRule(_ raw: [String: Any]) -> WorkflowMatchRuleEntry? {
        guard let workflowID = (raw["workflowID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !workflowID.isEmpty,
              let scopeRaw = raw["scope"] as? String,
              let typeRaw = raw["type"] as? String,
              let scope = FilenameRuleSet.MatchScope(rawValue: scopeRaw),
              let type = FilenameRuleSet.MatchType(rawValue: typeRaw) else {
            return nil
        }

        let values = ((raw["matchValues"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            return nil
        }

        return WorkflowMatchRuleEntry(
            scope: scope,
            type: type,
            matchValues: values,
            workflowID: workflowID
        )
    }
}

// MARK: - Conversion to FilenameRuleSet types (used by RuleLoader)

extension MatchRuleEntry {
    func asMapRule() -> FilenameRuleSet.MapRule {
        let match: FilenameRuleSet.MatchSpec
        switch type {
        case .equalsAny, .containsAny, .equalsOrContainsAny:
            match = .init(scope: scope, type: type, value: nil, values: matchValues)
        default:
            match = .init(scope: scope, type: type, value: matchValues.first, values: nil)
        }
        return .init(match: match, value: value)
    }
}

extension WorkflowMatchRuleEntry {
    func asMapRule() -> FilenameRuleSet.MapRule {
        let match: FilenameRuleSet.MatchSpec
        switch type {
        case .equalsAny, .containsAny, .equalsOrContainsAny:
            match = .init(scope: scope, type: type, value: nil, values: matchValues)
        default:
            match = .init(scope: scope, type: type, value: matchValues.first, values: nil)
        }
        return .init(match: match, value: workflowID)
    }
}

extension TokenMapping {
    func asMapRule() -> FilenameRuleSet.MapRule {
        let matchSpec: FilenameRuleSet.MatchSpec
        switch matchType {
        case .equals:
            matchSpec = .init(scope: .tokens, type: .equals, value: pattern, values: nil)
        case .regex:
            matchSpec = .init(
                scope: .tokens,
                type: .regex,
                value: RulePatternCodec.regexPattern(from: pattern),
                values: nil
            )
        }
        return .init(match: matchSpec, value: value)
    }
}
