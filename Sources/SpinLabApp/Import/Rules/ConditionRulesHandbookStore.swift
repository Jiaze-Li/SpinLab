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
    private struct Definition {
        let ruleID: String
        let label: String
        let kind: RuleEntryKind
        let binding: String
    }

    private let fileManager: FileManager
    let userFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.userFileURL = Self.applicationSupportRuleURL(fileManager: fileManager)
    }

    // MARK: Read

    func loadCurrentEntries() -> [RuleEntry] {
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
        let definitions = definitions(from: RuleLoader.shared.loadCached().ruleSet)
        var seenRuleIDs: Set<String> = []
        return definitions.compactMap { definition in
            guard seenRuleIDs.insert(definition.ruleID).inserted else { return nil }
            return ConditionDefinitionOption(id: definition.ruleID, label: definition.label)
        }
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
        let parentURL = userFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }
        try fileManager.copyItem(at: bundleURL, to: userFileURL)
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

        return nil
    }

    private static func applicationSupportRuleURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let appFolder = Bundle.main.bundleIdentifier ?? "com.spinlab.app"
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("filename_rules.json")
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
