import Foundation

// MARK: - Models

enum RuleEntryKind: String, Equatable {
    case unitSuffix = "unit_suffix"
    case tokenMap = "token_map"
    case customReadOnly = "custom_read_only"
}

enum TokenMatchType: String, CaseIterable, Equatable {
    case equals
    case regex
}

struct TokenMapping: Identifiable, Equatable {
    var id: UUID = UUID()
    var matchType: TokenMatchType = .equals
    var pattern: String
    var value: String
}

struct RuleEntry: Identifiable, Equatable {
    var ruleID: String
    var label: String
    var kind: RuleEntryKind
    var units: [String] = []
    var mappings: [TokenMapping] = []
    var readOnlyMessage: String?

    var id: String { "\(ruleID):\(kind.rawValue)" }
}

struct RuleEntriesDiff: Equatable {
    struct EntryDiff: Equatable {
        let label: String
        let before: String
        let after: String
        var hasChanges: Bool { before != after }
    }

    var entries: [EntryDiff]
    var hasAnyChanges: Bool { entries.contains(where: \.hasChanges) }
}

struct HandbookValidationIssue: Identifiable {
    enum Severity { case warning, error }
    let id = UUID()
    let field: String
    let message: String
    let severity: Severity
}

struct ConditionChangeProposal: Identifiable {
    struct FieldChange {
        let label: String
        let before: String?
        let after: String?
    }
    let id = UUID()
    let pendingID: UUID
    let fileName: String
    let changes: [FieldChange]
}

struct RuleEntryTemplate: Identifiable, Equatable {
    var ruleID: String
    var label: String
    var kind: RuleEntryKind

    var id: String { "\(ruleID):\(kind.rawValue)" }

    func materialize() -> RuleEntry {
        switch kind {
        case .unitSuffix:
            return RuleEntry(ruleID: ruleID, label: label, kind: .unitSuffix, units: [])
        case .tokenMap:
            return RuleEntry(ruleID: ruleID, label: label, kind: .tokenMap, mappings: [])
        case .customReadOnly:
            return RuleEntry(ruleID: ruleID, label: label, kind: .customReadOnly, readOnlyMessage: "Read-only")
        }
    }
}

struct ConditionDefinitionOption: Identifiable, Equatable {
    let id: String
    let label: String

    var description: String { label }
}

struct WorkflowMatchRuleEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var scope: FilenameRuleSet.MatchScope
    var type: FilenameRuleSet.MatchType
    var matchValues: [String]
    var workflowID: String
}

struct SeparatedConditionsPatch: Equatable {
    var extraConditions: [String: String]
    var deletedExtraConditionKeys: Set<String>
    var tokenMapRules: [String: [TokenMapping]]
}

struct MatchRuleEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var scope: FilenameRuleSet.MatchScope
    var type: FilenameRuleSet.MatchType
    var matchValues: [String]
    var value: String
}

struct SeparatedSubstratePatch {
    var substrateTagRules: [MatchRuleEntry]?
    var sharedSubstrate: FilenameRuleSet.SharedSubstrateRules?
}

struct RulePatternCodec {
    static let canonicalPrefix = #"^-?\d+(?:\.\d+)?(?:"#
    static let canonicalSuffix = #")$"#

    static func isCanonical(_ pattern: String) -> Bool {
        pattern.hasPrefix(canonicalPrefix) && pattern.hasSuffix(canonicalSuffix)
    }

    static func units(from pattern: String) -> [String]? {
        guard isCanonical(pattern) else { return nil }
        let inner = String(pattern.dropFirst(canonicalPrefix.count).dropLast(canonicalSuffix.count))
        guard !inner.isEmpty else { return nil }
        return inner
            .components(separatedBy: "|")
            .map(unescapeRegexLiteral)
            .filter { !$0.isEmpty }
    }

    static func pattern(from units: [String]) -> String {
        let escaped = units.map { NSRegularExpression.escapedPattern(for: $0) }
        return canonicalPrefix + escaped.joined(separator: "|") + canonicalSuffix
    }

    static func regexPattern(from shorthandOrRegex: String) -> String {
        let trimmed = shorthandOrRegex.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = numericSuffixShorthandSuffix(from: trimmed) {
            let escaped = NSRegularExpression.escapedPattern(for: suffix)
            return canonicalPrefix + escaped + canonicalSuffix
        }
        return trimmed
    }

    static func displayPattern(from storedPattern: String) -> String {
        if let suffix = numericSuffixRegexSuffix(from: storedPattern) {
            return "xx\(suffix)"
        }
        return storedPattern
    }

    private static func numericSuffixShorthandSuffix(from value: String) -> String? {
        guard value.lowercased().hasPrefix("xx"), value.count > 2 else {
            return nil
        }
        return String(value.dropFirst(2))
    }

    private static func numericSuffixRegexSuffix(from pattern: String) -> String? {
        guard isCanonical(pattern) else { return nil }
        let inner = String(pattern.dropFirst(canonicalPrefix.count).dropLast(canonicalSuffix.count))
        guard !inner.isEmpty, !inner.contains("|") else { return nil }
        return unescapeRegexLiteral(inner)
    }

    private static func unescapeRegexLiteral(_ value: String) -> String {
        var output = ""
        var escaping = false
        for char in value {
            if escaping {
                output.append(char)
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                output.append(char)
            }
        }
        if escaping { output.append("\\") }
        return output
    }
}

// MARK: - Store

final class ConditionRulesHandbookStore {
    private struct SharedSubstratePayload: Codable {
        var tokenSeparators: String
        var originStandaloneTokens: [String]
        var originContainsTokens: [String]
        var treatmentKeywords: [String: [String]]
        var materialTokens: [String]
        var materialAliases: [String: String]?
        var materialDisplayNames: [String: String]?
        var orientationTokens: [String]?
        var orientationAliases: [String: String]?
        var orientationPattern: String

        init(_ rules: FilenameRuleSet.SharedSubstrateRules) {
            tokenSeparators = rules.tokenSeparators
            originStandaloneTokens = rules.originStandaloneTokens
            originContainsTokens = rules.originContainsTokens
            treatmentKeywords = rules.treatmentKeywords
            materialTokens = rules.materialTokens
            materialAliases = rules.materialAliases
            materialDisplayNames = rules.materialDisplayNames
            orientationTokens = rules.orientationTokens
            orientationAliases = rules.orientationAliases
            orientationPattern = rules.orientationPattern
        }

        var asRuleSetValue: FilenameRuleSet.SharedSubstrateRules {
            .init(
                tokenSeparators: tokenSeparators,
                originStandaloneTokens: originStandaloneTokens,
                originContainsTokens: originContainsTokens,
                treatmentKeywords: treatmentKeywords,
                materialTokens: materialTokens,
                materialAliases: materialAliases,
                materialDisplayNames: materialDisplayNames,
                orientationTokens: orientationTokens,
                orientationAliases: orientationAliases,
                orientationPattern: orientationPattern
            )
        }
    }

    private struct Definition {
        let ruleID: String
        let label: String
        let kind: RuleEntryKind
        let binding: String
    }

    private let fileManager: FileManager
    let userFileURL: URL
    private let workflowMatchRulesFileURL: URL
    private let sampleIDRulesFileURL: URL
    private let conditionsRulesFileURL: URL
    private let substrateRulesFileURL: URL
    private let measurementTagRulesFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.userFileURL = Self.applicationSupportRuleURL(fileManager: fileManager)
        self.workflowMatchRulesFileURL = Self.applicationSupportWorkflowMatchRulesURL(fileManager: fileManager)
        self.sampleIDRulesFileURL = Self.applicationSupportSampleIDRulesURL(fileManager: fileManager)
        self.conditionsRulesFileURL = Self.applicationSupportConditionsRulesURL(fileManager: fileManager)
        self.substrateRulesFileURL = Self.applicationSupportSubstrateRulesURL(fileManager: fileManager)
        self.measurementTagRulesFileURL = Self.applicationSupportMeasurementTagRulesURL(fileManager: fileManager)
    }

    // MARK: Read

    func loadCurrentEntries() -> [RuleEntry] {
        _ = migrateUserRuleFileToCanonicalIfNeeded()
        let ruleSet = RuleLoader.shared.loadCached().ruleSet
        return loadEntries(from: ruleSet)
    }

    func loadDefaultEntries() -> [RuleEntry] {
        loadEntries(from: FilenameRuleSet.fallback())
    }

    func addableTemplates(for entries: [RuleEntry]) -> [RuleEntryTemplate] {
        let existingEntryIDs = Set(entries.map(\.id))
        let definitions = definitions(from: RuleLoader.shared.loadCached().ruleSet)
        return definitions.flatMap { definition in
            [RuleEntryTemplate(ruleID: definition.ruleID, label: definition.label, kind: definition.kind)]
        }
        .filter { !existingEntryIDs.contains($0.id) }
    }

    func conditionDefinitionOptions() -> [ConditionDefinitionOption] {
        _ = migrateUserRuleFileToCanonicalIfNeeded()
        let definitions = definitions(from: RuleLoader.shared.loadCached().ruleSet)
        var seenRuleIDs: Set<String> = []
        return definitions.compactMap { definition in
            guard seenRuleIDs.insert(definition.ruleID).inserted else { return nil }
            return ConditionDefinitionOption(id: definition.ruleID, label: definition.label)
        }
    }

    @discardableResult
    func migrateUserRuleFileToCanonicalIfNeeded() -> Bool {
        do {
            try ensureUserFileExists()
        } catch {
            return false
        }

        guard let data = try? Data(contentsOf: userFileURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }

        let hasInbox = json["inbox"] is [String: Any]
        var inbox = (json["inbox"] as? [String: Any]) ?? [:]
        var conditions = (hasInbox ? inbox["conditions"] : json["conditions"]) as? [String: Any] ?? [:]
        var changed = false

        var extraConditions = (conditions["extraConditions"] as? [String: String]) ?? [:]
        var tokenMapRules = (conditions["tokenMapRules"] as? [String: Any]) ?? [:]

        func migrateLegacyPattern(_ legacyKey: String, ruleID: String) {
            let legacy = (conditions[legacyKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if extraConditions[ruleID] == nil, !legacy.isEmpty {
                extraConditions[ruleID] = legacy
                changed = true
            }
            if (conditions[legacyKey] as? String) != "" {
                conditions[legacyKey] = ""
                changed = true
            }
        }

        migrateLegacyPattern("temperaturePattern", ruleID: ConditionFieldCatalog.temperatureID)
        migrateLegacyPattern("currentPattern", ruleID: ConditionFieldCatalog.currentID)
        migrateLegacyPattern("fieldPattern", ruleID: ConditionFieldCatalog.fieldID)

        let legacyDeviceRules = (hasInbox ? inbox["deviceRules"] : json["deviceRules"]) as? [Any] ?? []
        if tokenMapRules[ConditionFieldCatalog.deviceID] == nil, !legacyDeviceRules.isEmpty {
            tokenMapRules[ConditionFieldCatalog.deviceID] = legacyDeviceRules
            changed = true
        }
        if hasInbox {
            if let deviceRules = inbox["deviceRules"] as? [Any], !deviceRules.isEmpty {
                inbox["deviceRules"] = []
                changed = true
            }
        } else if let deviceRules = json["deviceRules"] as? [Any], !deviceRules.isEmpty {
            json["deviceRules"] = []
            changed = true
        }

        let conditionDefinitions = (hasInbox ? inbox["conditionDefinitions"] : json["conditionDefinitions"]) as? [[String: Any]] ?? []
        if conditionDefinitions.isEmpty {
            changed = true
        }

        func canonicalizedDefinition(_ raw: [String: Any]) -> [String: Any]? {
            guard let rawID = raw["id"] as? String else { return nil }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }

            guard let kindRaw = raw["kind"] as? String,
                  kindRaw == RuleEntryKind.unitSuffix.rawValue || kindRaw == RuleEntryKind.tokenMap.rawValue else {
                return nil
            }

            let label = ((raw["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty) ?? ConditionFieldCatalog.defaultLabel(for: id)
            let canonicalBinding: String
            if kindRaw == RuleEntryKind.unitSuffix.rawValue {
                canonicalBinding = "conditions.extraConditions.\(id)"
            } else {
                canonicalBinding = "conditions.tokenMapRules.\(id)"
            }

            if (raw["binding"] as? String) != canonicalBinding
                || (raw["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil {
                changed = true
            }

            return [
                "id": id,
                "label": label,
                "kind": kindRaw,
                "binding": canonicalBinding
            ]
        }

        var canonicalDefinitions = conditionDefinitions.compactMap { canonicalizedDefinition($0) }
        var seenDefinitionKeys: Set<String> = Set(
            canonicalDefinitions.compactMap { definition in
                guard let id = definition["id"] as? String,
                      let kind = definition["kind"] as? String else {
                    return nil
                }
                return "\(id.lowercased()):\(kind)"
            }
        )

        func appendDefinitionIfMissing(id: String, kind: RuleEntryKind) {
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else { return }
            let key = "\(normalizedID.lowercased()):\(kind.rawValue)"
            guard seenDefinitionKeys.insert(key).inserted else { return }
            canonicalDefinitions.append([
                "id": normalizedID,
                "label": ConditionFieldCatalog.defaultLabel(for: normalizedID),
                "kind": kind.rawValue,
                "binding": kind == .unitSuffix
                    ? "conditions.extraConditions.\(normalizedID)"
                    : "conditions.tokenMapRules.\(normalizedID)"
            ])
            changed = true
        }

        appendDefinitionIfMissing(id: ConditionFieldCatalog.temperatureID, kind: .unitSuffix)
        appendDefinitionIfMissing(id: ConditionFieldCatalog.currentID, kind: .unitSuffix)
        appendDefinitionIfMissing(id: ConditionFieldCatalog.fieldID, kind: .unitSuffix)
        appendDefinitionIfMissing(id: ConditionFieldCatalog.deviceID, kind: .tokenMap)
        for key in extraConditions.keys.sorted() {
            appendDefinitionIfMissing(id: key, kind: .unitSuffix)
        }
        for key in tokenMapRules.keys.sorted() {
            appendDefinitionIfMissing(id: key, kind: .tokenMap)
        }

        conditions["extraConditions"] = extraConditions
        conditions["tokenMapRules"] = tokenMapRules

        if hasInbox {
            inbox["conditions"] = conditions
            inbox["conditionDefinitions"] = canonicalDefinitions
            json["inbox"] = inbox
        } else {
            json["conditions"] = conditions
            json["conditionDefinitions"] = canonicalDefinitions
        }

        guard changed else { return false }
        guard let updatedData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return false
        }
        do {
            try updatedData.write(to: userFileURL, options: .atomic)
            _ = RuleLoader.shared.reloadCached()
            return true
        } catch {
            return false
        }
    }

    func loadWorkflowMatchRules() -> [WorkflowMatchRuleEntry] {
        if let separated = loadSeparatedWorkflowMatchRules() {
            return separated
        }
        let ruleSet = RuleLoader.shared.loadCached().ruleSet
        return ruleSet.measurementNameRules.map { rule in
            let values = (rule.match.values ?? []).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let single = rule.match.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchValues = values.isEmpty ? (single.map { [$0] } ?? []) : values
            return WorkflowMatchRuleEntry(
                scope: rule.match.scope,
                type: rule.match.type,
                matchValues: matchValues,
                workflowID: rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func saveWorkflowMatchRules(_ entries: [WorkflowMatchRuleEntry]) throws {
        let normalizedEntries = try entries.map { entry in
            let workflowID = entry.workflowID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !workflowID.isEmpty else {
                throw HandbookError.invalidEntries("Workflow ID cannot be empty in match rules.")
            }
            let values = entry.matchValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !values.isEmpty else {
                throw HandbookError.invalidEntries("Match values cannot be empty in match rules.")
            }
            return WorkflowMatchRuleEntry(
                id: entry.id,
                scope: entry.scope,
                type: entry.type,
                matchValues: values,
                workflowID: workflowID
            )
        }

        try ensureConfigDirectoryExists()
        let document: [String: Any] = [
            "version": 1,
            "rules": serializedWorkflowMatchRules(normalizedEntries)
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: workflowMatchRulesFileURL, options: .atomic)
        _ = RuleLoader.shared.reloadCached()
    }

    func loadSampleIDPatterns() -> [String] {
        if let separated = loadSeparatedSampleIDPatterns() {
            return separated
        }
        return RuleLoader.shared.loadCached().ruleSet.sampleId.patterns
    }

    func saveSampleIDPatterns(_ patterns: [String]) throws {
        // Normalize: trim, filter empty, deduplicate
        var seen: Set<String> = []
        let normalized = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }

        // Validate: each pattern must compile as a valid regex
        for pattern in normalized {
            do {
                _ = try NSRegularExpression(pattern: pattern)
            } catch {
                throw HandbookError.invalidEntries("Invalid regex '\(pattern)': \(error.localizedDescription)")
            }
        }

        try ensureConfigDirectoryExists()
        let document: [String: Any] = [
            "version": 1,
            "patterns": normalized
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: sampleIDRulesFileURL, options: .atomic)
        _ = RuleLoader.shared.reloadCached()
    }

    func loadSeparatedConditions() -> SeparatedConditionsPatch? {
        guard fileManager.fileExists(atPath: conditionsRulesFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: conditionsRulesFileURL),
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
                let mappings: [TokenMapping] = rawList.compactMap { raw in
                    guard let typeRaw = raw["matchType"] as? String,
                          let matchType = TokenMatchType(rawValue: typeRaw),
                          let pattern = (raw["pattern"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !pattern.isEmpty else {
                        return nil
                    }
                    let value = (raw["value"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nilIfEmpty ?? "$MATCH"
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

    func saveConditions(_ patch: SeparatedConditionsPatch) throws {
        for (key, pattern) in patch.extraConditions {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedPattern.isEmpty else {
                throw HandbookError.invalidEntries("Condition key/pattern cannot be empty.")
            }
            do {
                _ = try NSRegularExpression(pattern: normalizedPattern)
            } catch {
                throw HandbookError.invalidEntries("Invalid condition regex '\(normalizedPattern)': \(error.localizedDescription)")
            }
        }

        for (key, mappings) in patch.tokenMapRules {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else {
                throw HandbookError.invalidEntries("Condition token map key cannot be empty.")
            }
            for mapping in mappings {
                let normalizedPattern = mapping.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedPattern.isEmpty else {
                    throw HandbookError.invalidEntries("Token map pattern cannot be empty.")
                }
                if mapping.matchType == .regex {
                    do {
                        _ = try NSRegularExpression(pattern: RulePatternCodec.regexPattern(from: normalizedPattern))
                    } catch {
                        throw HandbookError.invalidEntries("Invalid token map regex '\(normalizedPattern)': \(error.localizedDescription)")
                    }
                }
            }
        }

        var extraConditionsPayload: [String: Any] = [:]
        for (key, value) in patch.extraConditions {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            extraConditionsPayload[normalizedKey] = normalizedValue
        }
        for key in patch.deletedExtraConditionKeys {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { continue }
            extraConditionsPayload[normalizedKey] = NSNull()
        }

        let tokenMapPayload: [String: Any] = patch.tokenMapRules.reduce(into: [:]) { partial, entry in
            let normalizedKey = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { return }
            partial[normalizedKey] = entry.value.map { mapping in
                [
                    "matchType": mapping.matchType.rawValue,
                    "pattern": mapping.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                    "value": mapping.value.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
            }
        }

        try ensureConfigDirectoryExists()
        let document: [String: Any] = [
            "version": 1,
            "extraConditions": extraConditionsPayload,
            "tokenMapRules": tokenMapPayload
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: conditionsRulesFileURL, options: .atomic)
        _ = RuleLoader.shared.reloadCached()
    }

    func loadSeparatedSubstrateRules() -> SeparatedSubstratePatch? {
        guard fileManager.fileExists(atPath: substrateRulesFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: substrateRulesFileURL),
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
               let payload = try? JSONDecoder().decode(SharedSubstratePayload.self, from: fragmentData) {
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

    func saveSubstrateRules(_ patch: SeparatedSubstratePatch) throws {
        let serializedTagRules: [[String: Any]]?
        if let entries = patch.substrateTagRules {
            let normalized = try normalizedMapRuleEntries(
                entries,
                context: "substrateTagRules"
            )
            serializedTagRules = serializedMapRules(normalized)
        } else {
            serializedTagRules = nil
        }

        let serializedSharedSubstrate: Any?
        if let shared = patch.sharedSubstrate {
            let payload = SharedSubstratePayload(shared)
            let data = try JSONEncoder().encode(payload)
            serializedSharedSubstrate = try JSONSerialization.jsonObject(with: data)
        } else {
            serializedSharedSubstrate = nil
        }

        guard serializedTagRules != nil || serializedSharedSubstrate != nil else {
            throw HandbookError.invalidEntries("At least one substrate override key is required.")
        }

        try ensureConfigDirectoryExists()
        var document: [String: Any] = ["version": 1]
        if let serializedTagRules {
            document["substrateTagRules"] = serializedTagRules
        }
        if let serializedSharedSubstrate {
            document["sharedSubstrate"] = serializedSharedSubstrate
        }
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: substrateRulesFileURL, options: .atomic)
        _ = RuleLoader.shared.reloadCached()
    }

    func loadSeparatedMeasurementTagRules() -> [MatchRuleEntry]? {
        guard fileManager.fileExists(atPath: measurementTagRulesFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: measurementTagRulesFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [[String: Any]] else {
            return nil
        }
        return rules.compactMap { decodeMapRuleEntry($0) }
    }

    func saveMeasurementTagRules(_ entries: [MatchRuleEntry]) throws {
        let normalized = try normalizedMapRuleEntries(
            entries,
            context: "measurementTagRules"
        )
        let document: [String: Any] = [
            "version": 1,
            "rules": serializedMapRules(normalized)
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try ensureConfigDirectoryExists()
        try data.write(to: measurementTagRulesFileURL, options: .atomic)
        _ = RuleLoader.shared.reloadCached()
    }

    // MARK: Validate

    func validate(_ entries: [RuleEntry]) -> [HandbookValidationIssue] {
        var issues: [HandbookValidationIssue] = []
        var definitionsByEntryID = Dictionary(
            uniqueKeysWithValues: definitions(from: RuleLoader.shared.loadCached().ruleSet).map {
                (entryKey(ruleID: $0.ruleID, kind: $0.kind), $0)
            }
        )
        for entry in entries where entry.kind != .customReadOnly {
            if definitionsByEntryID[entry.id] == nil {
                definitionsByEntryID[entry.id] = inferredDefinition(for: entry)
            }
        }

        let duplicatedEntryIDs = Dictionary(grouping: entries, by: \.id)
            .filter { $1.count > 1 }
            .keys
        for duplicate in duplicatedEntryIDs.sorted() {
            issues.append(
                HandbookValidationIssue(
                    field: duplicate,
                    message: "Duplicate rule entry detected.",
                    severity: .error
                )
            )
        }

        for entry in entries {
            guard let definition = definitionsByEntryID[entry.id] else {
                if entry.kind == .customReadOnly {
                    issues.append(
                        HandbookValidationIssue(
                            field: entry.label,
                            message: entry.readOnlyMessage ?? "Contains custom format and is read-only in handbook.",
                            severity: .warning
                        )
                    )
                    continue
                }
                issues.append(
                    HandbookValidationIssue(
                        field: entry.label,
                        message: "Unsupported rule id '\(entry.ruleID)'.",
                        severity: .error
                    )
                )
                continue
            }
            guard definition.kind == entry.kind || entry.kind == .customReadOnly else {
                issues.append(
                    HandbookValidationIssue(
                        field: entry.label,
                        message: "Rule kind '\(entry.kind.rawValue)' is not allowed for this label.",
                        severity: .error
                    )
                )
                continue
            }

            switch entry.kind {
            case .unitSuffix:
                issues.append(contentsOf: validateUnitSuffix(entry.units, label: entry.label))
            case .tokenMap:
                issues.append(contentsOf: validateTokenMap(entry.mappings, label: entry.label))
            case .customReadOnly:
                issues.append(
                    HandbookValidationIssue(
                        field: entry.label,
                        message: "Contains custom format and is read-only in handbook.",
                        severity: .warning
                    )
                )
            }
        }

        let unitEntries = entries.filter { $0.kind == .unitSuffix }
        for i in unitEntries.indices {
            for j in unitEntries.indices where j > i {
                let a = unitEntries[i]
                let b = unitEntries[j]
                for unit in Set(a.units).intersection(Set(b.units)).sorted() {
                    issues.append(
                        HandbookValidationIssue(
                            field: "\(a.label) / \(b.label)",
                            message: "Unit '\(unit)' appears in both entries; first match wins.",
                            severity: .warning
                        )
                    )
                }
            }
        }

        return issues
    }

    private func definitions(from ruleSet: FilenameRuleSet) -> [Definition] {
        let labels = ConditionFieldCatalog.labelMap(from: ruleSet)
        return ruleSet.conditionDefinitions.compactMap { definition in
            guard let kind = ruleEntryKind(from: definition.kind) else {
                return nil
            }
            let id = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let label = definition.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Definition(
                ruleID: id,
                label: (label?.isEmpty == false ? label! : (labels[id] ?? ConditionFieldCatalog.defaultLabel(for: id))),
                kind: kind,
                binding: definition.binding
            )
        }
    }

    private func ruleEntryKind(from kind: FilenameRuleSet.ConditionDefinitionKind) -> RuleEntryKind? {
        switch kind {
        case .unitSuffix:
            return .unitSuffix
        case .tokenMap:
            return .tokenMap
        }
    }

    // MARK: Diff

    func diff(from old: [RuleEntry], to new: [RuleEntry]) -> RuleEntriesDiff {
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newMap = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })

        let allIDs = Set(oldMap.keys).union(newMap.keys).sorted()
        let entryDiffs = allIDs.map { entryID -> RuleEntriesDiff.EntryDiff in
            let before = oldMap[entryID]
            let after = newMap[entryID]
            let label = after?.label ?? before?.label ?? entryID
            return RuleEntriesDiff.EntryDiff(
                label: label,
                before: summarize(before),
                after: summarize(after)
            )
        }

        return RuleEntriesDiff(entries: entryDiffs)
    }

    // MARK: Save

    /// Patches only mapped rule paths in the user rules file.
    /// Creates the file from the bundle if it doesn't exist yet.
    func save(_ entries: [RuleEntry]) throws {
        try ensureUserFileExists()

        let issues = validate(entries).filter { $0.severity == .error }
        if !issues.isEmpty {
            throw HandbookError.invalidEntries(issues.map(\.message).joined(separator: " | "))
        }

        let data = try Data(contentsOf: userFileURL)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HandbookError.invalidFormat
        }

        let hasInbox = json["inbox"] is [String: Any]
        var inbox = (json["inbox"] as? [String: Any]) ?? [:]
        // Save must resolve definitions from the latest on-disk rule snapshot;
        // using reload avoids serializing against a stale in-memory cache.
        let existingDefinitions = definitions(from: RuleLoader.shared.reloadCached().ruleSet)
            .map(canonicalizedDefinition)
        var definitionsByEntryID = Dictionary(
            uniqueKeysWithValues: existingDefinitions.map {
                (entryKey(ruleID: $0.ruleID, kind: $0.kind), $0)
            }
        )

        // Conditions patch
        var conditions = (hasInbox ? inbox["conditions"] : json["conditions"]) as? [String: Any] ?? [:]
        var extraConditions = (conditions["extraConditions"] as? [String: String]) ?? [:]
        var tokenMapRules = (conditions["tokenMapRules"] as? [String: Any]) ?? [:]

        for entry in entries {
            guard entry.kind != .customReadOnly else {
                continue
            }
            if definitionsByEntryID[entry.id] == nil {
                definitionsByEntryID[entry.id] = inferredDefinition(for: entry)
            }
            guard let definition = definitionsByEntryID[entry.id] else { continue }

            switch entry.kind {
            case .unitSuffix:
                let pattern = RulePatternCodec.pattern(from: entry.units)
                if definition.binding.hasPrefix("conditions.extraConditions.") {
                    let key = String(definition.binding.dropFirst("conditions.extraConditions.".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty {
                        extraConditions[key] = pattern
                    }
                }
            case .tokenMap:
                let mapRules = entry.mappings.compactMap { mapping -> [String: Any]? in
                    let pattern = mapping.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    if pattern.isEmpty { return nil }

                    let matchType: String
                    let matchValue: String
                    switch mapping.matchType {
                    case .equals:
                        matchType = "equals"
                        matchValue = pattern
                    case .regex:
                        matchType = "regex"
                        matchValue = RulePatternCodec.regexPattern(from: pattern)
                    }

                    let resolvedValue = mapping.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return [
                        "match": [
                            "scope": "tokens",
                            "type": matchType,
                            "value": matchValue
                        ],
                        "value": resolvedValue.isEmpty ? "$MATCH" : resolvedValue
                    ]
                }

                if definition.binding.hasPrefix("conditions.tokenMapRules.") {
                    let key = String(definition.binding.dropFirst("conditions.tokenMapRules.".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty {
                        tokenMapRules[key] = mapRules
                    }
                    continue
                }
            case .customReadOnly:
                continue
            }
        }

        let desiredEntryKeys = uniqueEntryKeys(
            preserving: entries.filter { $0.kind != .customReadOnly }.map(\.id),
            additional: []
        )
        let readOnlyRuleIDs = Set(
            entries
                .filter { $0.kind == .customReadOnly }
                .map { $0.ruleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        var finalDefinitions: [Definition] = desiredEntryKeys.compactMap { definitionsByEntryID[$0] }
        let existingByRuleID = Dictionary(grouping: existingDefinitions) { $0.ruleID.lowercased() }
        for ruleID in readOnlyRuleIDs {
            let preserved = existingByRuleID[ruleID] ?? []
            for definition in preserved {
                let key = entryKey(ruleID: definition.ruleID, kind: definition.kind)
                guard !finalDefinitions.contains(where: { entryKey(ruleID: $0.ruleID, kind: $0.kind) == key }) else {
                    continue
                }
                finalDefinitions.append(definition)
            }
        }

        let activeBindings = Set(finalDefinitions.map(\.binding))

        var filteredExtraConditions: [String: String] = [:]
        for (key, value) in extraConditions {
            let binding = "conditions.extraConditions.\(key)"
            if activeBindings.contains(binding) {
                filteredExtraConditions[key] = value
            }
        }
        if filteredExtraConditions.isEmpty {
            conditions.removeValue(forKey: "extraConditions")
        } else {
            conditions["extraConditions"] = filteredExtraConditions
        }

        var filteredTokenMapRules: [String: Any] = [:]
        for (key, value) in tokenMapRules {
            let binding = "conditions.tokenMapRules.\(key)"
            if activeBindings.contains(binding) {
                filteredTokenMapRules[key] = value
            }
        }
        if filteredTokenMapRules.isEmpty {
            conditions.removeValue(forKey: "tokenMapRules")
        } else {
            conditions["tokenMapRules"] = filteredTokenMapRules
        }

        // Keep legacy fields for decode compatibility, but rules are canonicalized
        // to conditionDefinitions + conditions.extraConditions/tokenMapRules.
        conditions["temperaturePattern"] = ""
        conditions["currentPattern"] = ""
        conditions["fieldPattern"] = ""
        if hasInbox {
            inbox["deviceRules"] = []
        } else {
            json["deviceRules"] = []
        }

        let serializedDefinitions = serializeConditionDefinitions(finalDefinitions)
        if hasInbox {
            inbox["conditionDefinitions"] = serializedDefinitions
        } else {
            json["conditionDefinitions"] = serializedDefinitions
        }

        if hasInbox {
            inbox["conditions"] = conditions
        } else {
            json["conditions"] = conditions
        }

        if hasInbox {
            json["inbox"] = inbox
        }

        let parentURL = userFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        let updatedData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedData.write(to: userFileURL, options: .atomic)
        _ = RuleLoader.shared.reloadCached()
    }

    // MARK: Export

    func export(to destinationURL: URL) throws {
        try ensureUserFileExists()
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: userFileURL, to: destinationURL)
    }

    // MARK: Private

    private func loadEntries(from ruleSet: FilenameRuleSet) -> [RuleEntry] {
        var entries: [RuleEntry] = []
        let definitions = definitions(from: ruleSet)

        for definition in definitions {
            if definition.kind == .tokenMap {
                if definition.binding.hasPrefix("conditions.tokenMapRules.") {
                    let key = String(definition.binding.dropFirst("conditions.tokenMapRules.".count))
                    let parsedMappings = parseDeviceMappings(ruleSet.conditions.tokenMapRules[key] ?? [])
                    if parsedMappings.unsupportedCount > 0 {
                        entries.append(
                            RuleEntry(
                                ruleID: definition.ruleID,
                                label: definition.label,
                                kind: .customReadOnly,
                                readOnlyMessage: "Current token-map rules include unsupported formats (\(parsedMappings.unsupportedCount) item(s)); entry is read-only in handbook."
                            )
                        )
                    } else {
                        entries.append(
                            RuleEntry(
                                ruleID: definition.ruleID,
                                label: definition.label,
                                kind: .tokenMap,
                                mappings: parsedMappings.mappings
                            )
                        )
                    }
                } else {
                    entries.append(
                        RuleEntry(
                            ruleID: definition.ruleID,
                            label: definition.label,
                            kind: .customReadOnly,
                            readOnlyMessage: "Unsupported token-map binding '\(definition.binding)'."
                        )
                    )
                }
                continue
            }

            entries.append(
                loadConditionEntry(
                    ruleSet: ruleSet,
                    ruleID: definition.ruleID,
                    label: definition.label,
                    binding: definition.binding
                )
            )
        }

        return entries
    }

    private func loadConditionEntry(
        ruleSet: FilenameRuleSet,
        ruleID: String,
        label: String,
        binding: String
    ) -> RuleEntry {
        let pattern = patternValue(from: ruleSet, binding: binding) ?? ""
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RuleEntry(ruleID: ruleID, label: label, kind: .unitSuffix, units: [])
        }

        if let units = RulePatternCodec.units(from: pattern) {
            return RuleEntry(ruleID: ruleID, label: label, kind: .unitSuffix, units: units)
        }
        return RuleEntry(
            ruleID: ruleID,
            label: label,
            kind: .customReadOnly,
            readOnlyMessage: "Pattern is non-canonical and cannot be edited as unit suffix list: \(pattern)"
        )
    }

    private func patternValue(from ruleSet: FilenameRuleSet, binding: String) -> String? {
        guard binding.hasPrefix("conditions.extraConditions.") else {
            return nil
        }
        let key = String(binding.dropFirst("conditions.extraConditions.".count))
        return ruleSet.conditions.extraConditions[key]
    }

    private func parseDeviceMappings(_ rules: [FilenameRuleSet.MapRule]) -> (mappings: [TokenMapping], unsupportedCount: Int) {
        var mappings: [TokenMapping] = []
        var unsupportedCount = 0

        for rule in rules {
            guard rule.match.scope == .tokens else {
                unsupportedCount += 1
                continue
            }
            guard let value = rule.match.value, !value.isEmpty else {
                unsupportedCount += 1
                continue
            }

            switch rule.match.type {
            case .equals:
                mappings.append(
                    TokenMapping(
                        matchType: .equals,
                        pattern: value,
                        value: rule.value == "$MATCH" ? value : rule.value
                    )
                )
            case .regex:
                mappings.append(
                    TokenMapping(
                        matchType: .regex,
                        pattern: RulePatternCodec.displayPattern(from: value),
                        value: rule.value == "$MATCH" ? "" : rule.value
                    )
                )
            default:
                unsupportedCount += 1
            }
        }

        return (mappings, unsupportedCount)
    }

    private func inferredDefinition(for entry: RuleEntry) -> Definition {
        let normalizedID = entry.ruleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = normalizedLabel.isEmpty
            ? ConditionFieldCatalog.defaultLabel(for: normalizedID)
            : normalizedLabel
        let binding: String

        switch entry.kind {
        case .unitSuffix:
            binding = "conditions.extraConditions.\(normalizedID)"
        case .tokenMap:
            binding = "conditions.tokenMapRules.\(normalizedID)"
        case .customReadOnly:
            binding = "conditions.extraConditions.\(normalizedID)"
        }

        return Definition(
            ruleID: normalizedID,
            label: label,
            kind: entry.kind,
            binding: binding
        )
    }

    private func canonicalizedDefinition(_ definition: Definition) -> Definition {
        let normalizedRuleID = definition.ruleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRuleID.isEmpty else { return definition }

        let normalizedBinding = definition.binding.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalBinding: String
        switch definition.kind {
        case .unitSuffix:
            if normalizedBinding == "conditions.temperaturePattern"
                || normalizedBinding == "conditions.currentPattern"
                || normalizedBinding == "conditions.fieldPattern"
                || normalizedBinding.hasPrefix("conditions.extraConditions.") {
                canonicalBinding = "conditions.extraConditions.\(normalizedRuleID)"
            } else {
                canonicalBinding = normalizedBinding
            }
        case .tokenMap:
            if normalizedBinding == "deviceRules"
                || normalizedBinding == "inbox.deviceRules"
                || normalizedBinding.hasPrefix("conditions.tokenMapRules.") {
                canonicalBinding = "conditions.tokenMapRules.\(normalizedRuleID)"
            } else {
                canonicalBinding = normalizedBinding
            }
        case .customReadOnly:
            canonicalBinding = normalizedBinding
        }

        return Definition(
            ruleID: definition.ruleID,
            label: definition.label,
            kind: definition.kind,
            binding: canonicalBinding
        )
    }

    private func serializeConditionDefinitions(_ definitions: [Definition]) -> [[String: Any]] {
        definitions.compactMap { definition in
            let kindRaw: String
            switch definition.kind {
            case .unitSuffix:
                kindRaw = "unit_suffix"
            case .tokenMap:
                kindRaw = "token_map"
            case .customReadOnly:
                return nil
            }
            return [
                "id": definition.ruleID,
                "label": definition.label,
                "kind": kindRaw,
                "binding": definition.binding
            ]
        }
    }

    private func uniqueEntryKeys(preserving preferred: [String], additional: [String]) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for key in preferred + additional {
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }

    private func entryKey(ruleID: String, kind: RuleEntryKind) -> String {
        "\(ruleID):\(kind.rawValue)"
    }

    private func validateUnitSuffix(_ units: [String], label: String) -> [HandbookValidationIssue] {
        var issues: [HandbookValidationIssue] = []

        if units.isEmpty {
            issues.append(
                HandbookValidationIssue(field: label, message: "At least one unit suffix is required.", severity: .error)
            )
        }

        let trimmedUnits = units.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for unit in trimmedUnits where unit.isEmpty {
            issues.append(
                HandbookValidationIssue(field: label, message: "Unit suffix cannot be empty.", severity: .error)
            )
        }

        let duplicates = Dictionary(grouping: trimmedUnits, by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
        for duplicate in duplicates.keys.sorted() {
            issues.append(
                HandbookValidationIssue(field: label, message: "Duplicate unit '\(duplicate)'.", severity: .error)
            )
        }

        return issues
    }

    private func validateTokenMap(_ mappings: [TokenMapping], label: String) -> [HandbookValidationIssue] {
        var issues: [HandbookValidationIssue] = []

        if mappings.isEmpty {
            issues.append(
                HandbookValidationIssue(field: label, message: "At least one mapping is required.", severity: .error)
            )
            return issues
        }

        var seen: Set<String> = []
        for mapping in mappings {
            let pattern = mapping.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = mapping.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(mapping.matchType.rawValue):\(pattern.lowercased())"

            if pattern.isEmpty {
                issues.append(
                    HandbookValidationIssue(field: label, message: "Mapping pattern cannot be empty.", severity: .error)
                )
                continue
            }

            if !seen.insert(key).inserted {
                issues.append(
                    HandbookValidationIssue(field: label, message: "Duplicate mapping '\(pattern)'.", severity: .error)
                )
            }

            if mapping.matchType == .equals, value.isEmpty {
                issues.append(
                    HandbookValidationIssue(field: label, message: "Equals mapping '\(pattern)' requires a value.", severity: .error)
                )
            }

            if mapping.matchType == .regex {
                let regexPattern = RulePatternCodec.regexPattern(from: pattern)
                do {
                    _ = try NSRegularExpression(pattern: regexPattern)
                } catch {
                    issues.append(
                        HandbookValidationIssue(field: label, message: "Invalid regex pattern '\(pattern)'.", severity: .error)
                    )
                }
            }
        }

        return issues
    }

    private func summarize(_ entry: RuleEntry?) -> String {
        guard let entry else { return "(removed)" }
        switch entry.kind {
        case .unitSuffix:
            return entry.units.joined(separator: ", ")
        case .tokenMap:
            return entry.mappings
                .map { mapping in
                    let rhs = mapping.value.isEmpty ? "$MATCH" : mapping.value
                    return "[\(mapping.matchType.rawValue)] \(mapping.pattern) -> \(rhs)"
                }
                .joined(separator: " ; ")
        case .customReadOnly:
            return "(read-only custom format)"
        }
    }

    private func ensureUserFileExists() throws {
        guard !fileManager.fileExists(atPath: userFileURL.path) else { return }
        guard let bundleURL = findBundleRuleFileURL() else {
            throw HandbookError.bundleFileNotFound
        }
        try ensureConfigDirectoryExists()
        try fileManager.copyItem(at: bundleURL, to: userFileURL)
    }

    private func ensureConfigDirectoryExists() throws {
        let parentURL = userFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }
    }

    private func loadSeparatedWorkflowMatchRules() -> [WorkflowMatchRuleEntry]? {
        guard fileManager.fileExists(atPath: workflowMatchRulesFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: workflowMatchRulesFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [[String: Any]] else {
            return nil
        }

        return rules.compactMap { decodeWorkflowMatchRule($0) }
    }

    private func loadSeparatedSampleIDPatterns() -> [String]? {
        guard fileManager.fileExists(atPath: sampleIDRulesFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: sampleIDRulesFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let patterns = json["patterns"] as? [String] else {
            return nil
        }
        let normalized = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? nil : normalized
    }

    private func decodeMapRuleEntry(_ raw: [String: Any]) -> MatchRuleEntry? {
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

        let value = (raw["value"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "$MATCH"
        return MatchRuleEntry(
            scope: scope,
            type: type,
            matchValues: matchValues,
            value: value
        )
    }

    private func normalizedMapRuleEntries(
        _ entries: [MatchRuleEntry],
        context: String
    ) throws -> [MatchRuleEntry] {
        try entries.map { entry in
            let values = entry.matchValues
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !values.isEmpty else {
                throw HandbookError.invalidEntries("\(context): match values cannot be empty.")
            }

            let normalizedValue = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedValue.isEmpty else {
                throw HandbookError.invalidEntries("\(context): rule value cannot be empty.")
            }

            if entry.type == .regex {
                let regexPattern = RulePatternCodec.regexPattern(from: values[0])
                do {
                    _ = try NSRegularExpression(pattern: regexPattern)
                } catch {
                    throw HandbookError.invalidEntries(
                        "\(context): invalid regex '\(values[0])': \(error.localizedDescription)"
                    )
                }
            }

            switch entry.type {
            case .equalsAny, .containsAny, .equalsOrContainsAny:
                return MatchRuleEntry(
                    id: entry.id,
                    scope: entry.scope,
                    type: entry.type,
                    matchValues: values,
                    value: normalizedValue
                )
            default:
                return MatchRuleEntry(
                    id: entry.id,
                    scope: entry.scope,
                    type: entry.type,
                    matchValues: [values[0]],
                    value: normalizedValue
                )
            }
        }
    }

    private func serializedMapRules(_ entries: [MatchRuleEntry]) -> [[String: Any]] {
        entries.map { entry in
            let match: [String: Any]
            switch entry.type {
            case .equalsAny, .containsAny, .equalsOrContainsAny:
                match = [
                    "scope": entry.scope.rawValue,
                    "type": entry.type.rawValue,
                    "values": entry.matchValues
                ]
            default:
                match = [
                    "scope": entry.scope.rawValue,
                    "type": entry.type.rawValue,
                    "value": entry.matchValues[0]
                ]
            }
            return [
                "match": match,
                "value": entry.value
            ]
        }
    }

    private func decodeWorkflowMatchRule(_ raw: [String: Any]) -> WorkflowMatchRuleEntry? {
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

    private func serializedWorkflowMatchRules(_ entries: [WorkflowMatchRuleEntry]) -> [[String: Any]] {
        entries.map { entry in
            [
                "scope": entry.scope.rawValue,
                "type": entry.type.rawValue,
                "matchValues": entry.matchValues,
                "workflowID": entry.workflowID
            ]
        }
    }

    private func findBundleRuleFileURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: "filename_rules", withExtension: "json", subdirectory: "config"
        ) { return url }

        if let resources = Bundle.main.resourceURL {
            let c1 = resources.appendingPathComponent("config/filename_rules.json")
            if fileManager.fileExists(atPath: c1.path) { return c1 }
            let c2 = resources.appendingPathComponent("SpinLab_SpinLabApp.bundle/filename_rules.json")
            if fileManager.fileExists(atPath: c2.path) { return c2 }
        }

        let bundleRoot = Bundle.main.bundleURL
        let c3 = bundleRoot.appendingPathComponent("Contents/Resources/config/filename_rules.json")
        if fileManager.fileExists(atPath: c3.path) { return c3 }
        let c4 = bundleRoot.appendingPathComponent("Contents/Resources/SpinLab_SpinLabApp.bundle/filename_rules.json")
        if fileManager.fileExists(atPath: c4.path) { return c4 }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let c5 = cwd.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")
        if fileManager.fileExists(atPath: c5.path) { return c5 }

        return nil
    }

    private static func applicationSupportRuleURL(fileManager: FileManager) -> URL {
        applicationSupportConfigDirectory(fileManager: fileManager)
            .appendingPathComponent("filename_rules.json")
    }

    private static func applicationSupportWorkflowMatchRulesURL(fileManager: FileManager) -> URL {
        applicationSupportConfigDirectory(fileManager: fileManager)
            .appendingPathComponent("workflow_match_rules.json")
    }

    private static func applicationSupportSampleIDRulesURL(fileManager: FileManager) -> URL {
        applicationSupportConfigDirectory(fileManager: fileManager)
            .appendingPathComponent("sample_id_rules.json")
    }

    private static func applicationSupportConditionsRulesURL(fileManager: FileManager) -> URL {
        applicationSupportConfigDirectory(fileManager: fileManager)
            .appendingPathComponent("conditions_rules.json")
    }

    private static func applicationSupportSubstrateRulesURL(fileManager: FileManager) -> URL {
        applicationSupportConfigDirectory(fileManager: fileManager)
            .appendingPathComponent("substrate_rules.json")
    }

    private static func applicationSupportMeasurementTagRulesURL(fileManager: FileManager) -> URL {
        applicationSupportConfigDirectory(fileManager: fileManager)
            .appendingPathComponent("measurement_tag_rules.json")
    }

    private static func applicationSupportConfigDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        // Keep rules colocated with the rest of SpinLab persisted state.
        // In tests, isolate from real user data.
        let isRunningTests =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("xctest") == .orderedSame
            || Bundle.main.bundlePath.localizedCaseInsensitiveContains(".xctest/")
        let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMainAppBundle = bundleID?.caseInsensitiveCompare("com.spinlab.app") == .orderedSame
        let appFolder: String
        if !isRunningTests && isMainAppBundle {
            appFolder = "SpinLab"
        } else {
            if let bundleID, !bundleID.isEmpty {
                appFolder = bundleID
            } else {
                appFolder = "com.spinlab.tests.\(ProcessInfo.processInfo.processIdentifier)"
            }
        }
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
    }

    enum HandbookError: LocalizedError {
        case bundleFileNotFound
        case invalidFormat
        case invalidEntries(String)

        var errorDescription: String? {
            switch self {
            case .bundleFileNotFound:
                return "Could not locate bundled filename_rules.json"
            case .invalidFormat:
                return "Rules JSON format is invalid"
            case let .invalidEntries(message):
                return "Rule entries are invalid: \(message)"
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
