import Foundation

// MARK: - Models


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
    enum WriteScope: String {
        case handbookEntries
        case workflowMatchRules
        case sampleIDPatterns
        case conditions
        case substrateRules
        case measurementTagRules
    }

    struct RuleWriteToken {
        fileprivate let id: UUID
        fileprivate let scope: WriteScope
    }

    private struct PendingApproval {
        let scope: WriteScope
        let baseHash: String
        let createdAt: Date
        let expiresAt: Date
        let actor: String
    }

    struct SharedSubstratePayload: Codable {
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
    private let logger = AppLogger.shared
    private let auditLogger = AuditLogger.shared
    private let approvalLock = NSLock()
    private let approvalTTL: TimeInterval = 120
    private var pendingApprovals: [UUID: PendingApproval] = [:]
    let userFileURL: URL
    private let workflowMatchRulesFileURL: URL
    private let sampleIDRulesFileURL: URL
    private let conditionsRulesFileURL: URL
    private let substrateRulesFileURL: URL
    private let measurementTagRulesFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let paths = RulesConfigPaths(fileManager: fileManager)
        self.userFileURL = paths.ruleURL
        self.workflowMatchRulesFileURL = paths.workflowMatchRulesURL
        self.sampleIDRulesFileURL = paths.sampleIDRulesURL
        self.conditionsRulesFileURL = paths.conditionsRulesURL
        self.substrateRulesFileURL = paths.substrateRulesURL
        self.measurementTagRulesFileURL = paths.measurementTagRulesURL
    }

    // MARK: Read

    func loadCurrentEntries() -> [RuleEntry] {
        migrateUserRuleFileToCanonicalIfNeeded()
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
        migrateUserRuleFileToCanonicalIfNeeded()
        let definitions = definitions(from: RuleLoader.shared.loadCached().ruleSet)
        var seenRuleIDs: Set<String> = []
        return definitions.compactMap { definition in
            guard seenRuleIDs.insert(definition.ruleID).inserted else { return nil }
            return ConditionDefinitionOption(id: definition.ruleID, label: definition.label)
        }
    }

    @discardableResult
    func migrateUserRuleFileToCanonicalIfNeeded() -> Bool {
        guard fileManager.fileExists(atPath: userFileURL.path) else {
            return false
        }

        guard let data = try? Data(contentsOf: userFileURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            logger.warning(.import, "Rules migration skipped because user rule file could not be decoded", metadata: [
                "fileName": userFileURL.lastPathComponent
            ])
            return false
        }

        let result = RuleCanonicalizer.migrateUserRuleJSONToCanonical(json)
        json = result.json

        guard result.changed else { return false }
        guard let updatedData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            logger.warning(.import, "Rules migration failed during JSON encoding", metadata: [
                "fileName": userFileURL.lastPathComponent
            ])
            return false
        }
        do {
            try updatedData.write(to: userFileURL, options: .atomic)
            _ = RuleLoader.shared.reloadCached()
            return true
        } catch {
            logger.warning(.import, "Rules migration failed during file write", metadata: [
                "fileName": userFileURL.lastPathComponent,
                "reason": error.localizedDescription
            ])
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

    func saveWorkflowMatchRules(_ entries: [WorkflowMatchRuleEntry], approvalToken: RuleWriteToken) throws {
        let approval = try consumeApprovalToken(approvalToken, expectedScope: .workflowMatchRules)
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
        try finalizeApprovedWrite(
            scope: .workflowMatchRules,
            targetURL: workflowMatchRulesFileURL,
            approval: approval
        )
    }

    func loadSampleIDPatterns() -> [String] {
        if let separated = loadSeparatedSampleIDPatterns() {
            return separated
        }
        return RuleLoader.shared.loadCached().ruleSet.sampleId.patterns
    }

    func saveSampleIDPatterns(_ patterns: [String], approvalToken: RuleWriteToken) throws {
        let approval = try consumeApprovalToken(approvalToken, expectedScope: .sampleIDPatterns)
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
        try finalizeApprovedWrite(
            scope: .sampleIDPatterns,
            targetURL: sampleIDRulesFileURL,
            approval: approval
        )
    }

    func loadSeparatedConditions() -> SeparatedConditionsPatch? {
        SeparatedOverrideReader.readConditions(from: conditionsRulesFileURL)
    }

    func saveConditions(_ patch: SeparatedConditionsPatch, approvalToken: RuleWriteToken) throws {
        let approval = try consumeApprovalToken(approvalToken, expectedScope: .conditions)
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
        try finalizeApprovedWrite(scope: .conditions, targetURL: conditionsRulesFileURL, approval: approval)
    }

    func loadSeparatedSubstrateRules() -> SeparatedSubstratePatch? {
        SeparatedOverrideReader.readSubstrateRules(from: substrateRulesFileURL)
    }

    func saveSubstrateRules(_ patch: SeparatedSubstratePatch, approvalToken: RuleWriteToken) throws {
        let approval = try consumeApprovalToken(approvalToken, expectedScope: .substrateRules)
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
        try finalizeApprovedWrite(scope: .substrateRules, targetURL: substrateRulesFileURL, approval: approval)
    }

    func loadSeparatedMeasurementTagRules() -> [MatchRuleEntry]? {
        SeparatedOverrideReader.readMeasurementTagRules(from: measurementTagRulesFileURL)
    }

    func saveMeasurementTagRules(_ entries: [MatchRuleEntry], approvalToken: RuleWriteToken) throws {
        let approval = try consumeApprovalToken(approvalToken, expectedScope: .measurementTagRules)
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
        try finalizeApprovedWrite(
            scope: .measurementTagRules,
            targetURL: measurementTagRulesFileURL,
            approval: approval
        )
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

    /// Must be called only from an explicit user-confirmed flow (for example, after a visible diff review).
    /// Do not issue approvals from background/autonomous paths.
    func issueWriteApproval(for scope: WriteScope, actor: String) -> RuleWriteToken {
        approvalLock.lock()
        defer { approvalLock.unlock() }
        purgeExpiredApprovals(referenceDate: Date())
        let tokenID = UUID()
        let now = Date()
        let currentHash = RuleLoader.shared.loadCached().metadata.contentHash
        pendingApprovals[tokenID] = PendingApproval(
            scope: scope,
            baseHash: currentHash,
            createdAt: now,
            expiresAt: now.addingTimeInterval(approvalTTL),
            actor: actor
        )
        return RuleWriteToken(id: tokenID, scope: scope)
    }

    // MARK: Save

    /// Patches only mapped rule paths in the user rules file.
    /// Creates the file from the bundle if it doesn't exist yet.
    func save(_ entries: [RuleEntry], approvalToken: RuleWriteToken) throws {
        let approval = try consumeApprovalToken(approvalToken, expectedScope: .handbookEntries)
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
        try finalizeApprovedWrite(scope: .handbookEntries, targetURL: userFileURL, approval: approval)
    }

    // MARK: Export

    func export(to destinationURL: URL) throws {
        let sourceURL: URL
        if fileManager.fileExists(atPath: userFileURL.path) {
            sourceURL = userFileURL
        } else if let bundleURL = findBundleRuleFileURL() {
            sourceURL = bundleURL
        } else {
            throw HandbookError.bundleFileNotFound
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
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
            if normalizedBinding.hasPrefix("conditions.extraConditions.") {
                canonicalBinding = "conditions.extraConditions.\(normalizedRuleID)"
            } else {
                canonicalBinding = normalizedBinding
            }
        case .tokenMap:
            if normalizedBinding.hasPrefix("conditions.tokenMapRules.") {
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

    private func consumeApprovalToken(_ token: RuleWriteToken, expectedScope: WriteScope) throws -> PendingApproval {
        approvalLock.lock()
        defer { approvalLock.unlock() }
        purgeExpiredApprovals(referenceDate: Date())

        guard token.scope == expectedScope else {
            auditRuleWrite(
                scope: expectedScope,
                result: "denied",
                targetPath: nil,
                metadata: [
                    "reason": "scope_mismatch",
                    "tokenScope": token.scope.rawValue
                ]
            )
            throw HandbookError.unauthorizedWrite("Approval scope mismatch.")
        }

        guard let approval = pendingApprovals.removeValue(forKey: token.id) else {
            auditRuleWrite(
                scope: expectedScope,
                result: "denied",
                targetPath: nil,
                metadata: ["reason": "missing_or_consumed_token"]
            )
            throw HandbookError.unauthorizedWrite("Approval token is missing, expired, or already used.")
        }

        let currentHash = RuleLoader.shared.loadCached().metadata.contentHash
        guard approval.baseHash == currentHash else {
            auditRuleWrite(
                scope: expectedScope,
                result: "denied",
                targetPath: nil,
                metadata: [
                    "reason": "stale_base_hash",
                    "approvedBaseHash": approval.baseHash,
                    "currentBaseHash": currentHash
                ]
            )
            throw HandbookError.unauthorizedWrite("Rules changed since approval. Please review and save again.")
        }
        return approval
    }

    private func finalizeApprovedWrite(
        scope: WriteScope,
        targetURL: URL,
        approval: PendingApproval
    ) throws {
        let reloaded = RuleLoader.shared.reloadCached()
        auditRuleWrite(
            scope: scope,
            result: "success",
            targetPath: targetURL.path,
            metadata: [
                "actor": approval.actor,
                "targetPath": targetURL.path,
                "oldHash": approval.baseHash,
                "newHash": reloaded.metadata.contentHash,
                "approvedAt": ISO8601DateFormatter().string(from: approval.createdAt)
            ]
        )
    }

    private func purgeExpiredApprovals(referenceDate: Date) {
        pendingApprovals = pendingApprovals.filter { _, approval in
            approval.expiresAt > referenceDate
        }
    }

    private func auditRuleWrite(
        scope: WriteScope,
        result: String,
        targetPath: String?,
        metadata: [String: String]
    ) {
        auditLogger.logRuleWriteEvent(
            action: "rules_write_\(scope.rawValue)",
            result: result,
            sourceFilePath: targetPath ?? targetPathForScope(scope),
            metadata: metadata
        )
    }

    private func targetPathForScope(_ scope: WriteScope) -> String {
        switch scope {
        case .handbookEntries:
            return userFileURL.path
        case .workflowMatchRules:
            return workflowMatchRulesFileURL.path
        case .sampleIDPatterns:
            return sampleIDRulesFileURL.path
        case .conditions:
            return conditionsRulesFileURL.path
        case .substrateRules:
            return substrateRulesFileURL.path
        case .measurementTagRules:
            return measurementTagRulesFileURL.path
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
        SeparatedOverrideReader.readWorkflowMatchRules(from: workflowMatchRulesFileURL)
    }

    private func loadSeparatedSampleIDPatterns() -> [String]? {
        SeparatedOverrideReader.readSampleIDPatterns(from: sampleIDRulesFileURL)
    }

    // decodeMapRuleEntry moved to SeparatedOverrideReader.decodeMapRuleEntry

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

    // decodeWorkflowMatchRule moved to SeparatedOverrideReader.decodeWorkflowMatchRule

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

    enum HandbookError: LocalizedError {
        case bundleFileNotFound
        case invalidFormat
        case invalidEntries(String)
        case unauthorizedWrite(String)

        var errorDescription: String? {
            switch self {
            case .bundleFileNotFound:
                return "Could not locate bundled filename_rules.json"
            case .invalidFormat:
                return "Rules JSON format is invalid"
            case let .invalidEntries(message):
                return "Rule entries are invalid: \(message)"
            case let .unauthorizedWrite(message):
                return "Rule write rejected: \(message)"
            }
        }
    }
}
