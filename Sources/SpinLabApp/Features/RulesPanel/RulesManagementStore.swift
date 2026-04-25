import Foundation
import CryptoKit
import Observation

// MARK: - Save outcome

struct RulesPanelFieldError: Identifiable {
    let id: UUID = UUID()
    let field: String
    let message: String
}

enum RulesPanelSaveOutcome {
    case saved
    case validationFailed([RulesPanelFieldError])
    case externalConflict(externalChecksum: String)
    case ioError(Error)
}

// MARK: - Draft types (Codable mirrors of each schema file)

// filename_parse_rules.json
struct FilenameParseRulesFileDraft: Codable {
    var version: Int
    var tokenization: Tokenization
    var sources: [String]
    var batch: Batch
    var channel: Channel
    var rotationHintRules: [MapRule]
    var measurementNameRules: [MapRule]
    var conditions: Conditions
    var conditionDefinitions: [ConditionDefinition]

    struct Tokenization: Codable {
        var separators: String
        var caseFold: String
    }
    struct Batch: Codable {
        var preferSampleId: Bool
        var fallbackPatterns: [String]
    }
    struct Channel: Codable {
        var aliases: [String: String]
    }
    struct MapRule: Codable, Hashable {
        var match: MatchSpec
        var value: String
        struct MatchSpec: Codable, Hashable {
            var scope: String
            var type: String
            var value: String?
            var values: [String]?
        }
    }
    struct Conditions: Codable {
        var extraConditions: [String: String]
        var tokenMapRules: [String: [MapRule]]
        var displayLabels: [String: String]
    }
    struct ConditionDefinition: Codable, Identifiable {
        var id: String
        var label: String?
        var kind: String
        var binding: String
    }
}

// sample_id_rules.json
struct SampleIDRulesFileDraft: Codable {
    var version: Int
    var patterns: [String]
}

// workflow_match_rules.json
struct WorkflowMatchRulesFileDraft: Codable {
    var version: Int
    var rules: [WorkflowMatchRule]

    struct WorkflowMatchRule: Codable, Identifiable {
        var id: UUID
        var workflowID: String
        var scope: String
        var type: String
        var matchValues: [String]

        init(
            id: UUID = UUID(),
            workflowID: String = "",
            scope: String = "tokens",
            type: String = "equals",
            matchValues: [String] = []
        ) {
            self.id = id
            self.workflowID = workflowID
            self.scope = scope
            self.type = type
            self.matchValues = matchValues
        }

        private enum CodingKeys: String, CodingKey {
            case workflowID, scope, type, matchValues
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            workflowID = try container.decode(String.self, forKey: .workflowID)
            scope = try container.decode(String.self, forKey: .scope)
            type = try container.decode(String.self, forKey: .type)
            matchValues = try container.decode([String].self, forKey: .matchValues)
        }
    }
}

// substrate_normalization_rules.json
struct SubstrateNormalizationRulesFileDraft: Codable {
    var version: Int
    var substrateTagRules: [FilenameParseRulesFileDraft.MapRule]
    var sharedSubstrate: SharedSubstrate?

    struct SharedSubstrate: Codable {
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
    }
}

// Placeholder data for read-only sections

struct MeasurementTagSummary {
    var version: Int
    var ruleCount: Int
    var previewValues: [String]
}

struct WorkflowIDPolicySummary {
    var version: Int
    var preferredAlphabet: String?
    var fallbackPrefix: String?
}

// MARK: - Store

@MainActor @Observable
final class RulesManagementStore {

    private(set) var currentSection: RulesPanelSection = .filenameParse
    private(set) var dirtySections: Set<RulesPanelSection> = []

    private(set) var filenameParseDraft: FilenameParseRulesFileDraft?
    private(set) var sampleIDDraft: SampleIDRulesFileDraft?
    private(set) var workflowMatchDraft: WorkflowMatchRulesFileDraft?
    private(set) var substrateDraft: SubstrateNormalizationRulesFileDraft?
    private(set) var measurementTagSummary: MeasurementTagSummary?
    private(set) var workflowIDPolicySummary: WorkflowIDPolicySummary?
    private(set) var availableWorkflowIDs: [String] = []

    @ObservationIgnored var persistenceHook: RulesPersistenceHook?
    @ObservationIgnored private var openTimeHashes: [RulesPanelSection: String] = [:]
    @ObservationIgnored private let onRulesSaved: () -> Void

    private let paths = RulesConfigPaths()
    private let atomicWriter = AtomicFileWriter()

    private static let jsonEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    private static let jsonDecoder = JSONDecoder()

    init(onRulesSaved: @escaping () -> Void = {}) {
        self.onRulesSaved = onRulesSaved
    }

    // MARK: - Lifecycle

    func present() {
        availableWorkflowIDs = loadAvailableWorkflowIDs()
        for section in RulesPanelSection.allCases {
            loadSection(section)
        }
    }

    // MARK: - Navigation

    func selectSection(_ section: RulesPanelSection) {
        currentSection = section
    }

    // MARK: - Draft updates (each call marks section dirty)

    func updateFilenameParse(_ draft: FilenameParseRulesFileDraft) {
        filenameParseDraft = draft
        dirtySections.insert(.filenameParse)
    }

    func updateSampleID(_ draft: SampleIDRulesFileDraft) {
        sampleIDDraft = draft
        dirtySections.insert(.sampleID)
    }

    func updateWorkflowMatch(_ draft: WorkflowMatchRulesFileDraft) {
        workflowMatchDraft = draft
        dirtySections.insert(.workflowMatch)
    }

    func updateSubstrate(_ draft: SubstrateNormalizationRulesFileDraft) {
        substrateDraft = draft
        dirtySections.insert(.substrate)
    }

    // MARK: - Save / Discard

    func saveCurrent() -> RulesPanelSaveOutcome {
        switch currentSection {
        case .filenameParse:    return saveFilenameParse()
        case .sampleID:         return saveSampleID()
        case .workflowMatch:    return saveWorkflowMatch()
        case .substrate:        return saveSubstrate()
        case .measurementTag, .workflowIDPolicy:
            return .validationFailed([])
        }
    }

    func discardCurrent() {
        loadSection(currentSection)
        dirtySections.remove(currentSection)
    }

    func reloadFromDisk(_ section: RulesPanelSection) {
        loadSection(section)
        dirtySections.remove(section)
    }

    // Called after user picks "Override With My Edits" on a conflict alert
    func overrideWithCurrentDraft(section: RulesPanelSection) -> RulesPanelSaveOutcome {
        openTimeHashes.removeValue(forKey: section)
        switch section {
        case .filenameParse:    return saveFilenameParse()
        case .sampleID:         return saveSampleID()
        case .workflowMatch:    return saveWorkflowMatch()
        case .substrate:        return saveSubstrate()
        case .measurementTag, .workflowIDPolicy: return .validationFailed([])
        }
    }

    // Called after user picks "Reload External Changes" on a conflict alert
    func reloadAfterExternalChange(section: RulesPanelSection) {
        loadSection(section)
        dirtySections.remove(section)
    }

    // MARK: - Loading

    private func loadSection(_ section: RulesPanelSection) {
        switch section {
        case .filenameParse:
            filenameParseDraft = loadAndCacheHash(url: paths.filenameParsRulesURL, section: section)
        case .sampleID:
            sampleIDDraft = loadAndCacheHash(url: paths.sampleIDRulesURL, section: section)
        case .workflowMatch:
            workflowMatchDraft = loadAndCacheHash(url: paths.workflowMatchRulesURL, section: section)
        case .substrate:
            substrateDraft = loadAndCacheHash(url: paths.substrateNormalizationRulesURL, section: section)
        case .measurementTag:
            measurementTagSummary = loadMeasurementTagSummary()
        case .workflowIDPolicy:
            workflowIDPolicySummary = loadWorkflowIDPolicySummary()
        }
    }

    private func loadAndCacheHash<T: Decodable>(url: URL, section: RulesPanelSection) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? Self.jsonDecoder.decode(T.self, from: data) else {
            return nil
        }
        openTimeHashes[section] = sha256Hex(of: data)
        return decoded
    }

    private func loadMeasurementTagSummary() -> MeasurementTagSummary? {
        struct File: Decodable {
            let version: Int
            let rules: [Rule]
            struct Rule: Decodable { let value: String }
        }
        guard let data = try? Data(contentsOf: paths.measurementTagRulesURL),
              let file = try? Self.jsonDecoder.decode(File.self, from: data) else { return nil }
        openTimeHashes[.measurementTag] = sha256Hex(of: data)
        return MeasurementTagSummary(
            version: file.version,
            ruleCount: file.rules.count,
            previewValues: file.rules.prefix(5).map(\.value)
        )
    }

    private func loadWorkflowIDPolicySummary() -> WorkflowIDPolicySummary? {
        struct File: Decodable {
            let version: Int
            let preferredAlphabet: String?
            let fallbackPrefix: String?
        }
        guard let data = try? Data(contentsOf: paths.workflowIDPolicyURL),
              let file = try? Self.jsonDecoder.decode(File.self, from: data) else { return nil }
        openTimeHashes[.workflowIDPolicy] = sha256Hex(of: data)
        return WorkflowIDPolicySummary(
            version: file.version,
            preferredAlphabet: file.preferredAlphabet,
            fallbackPrefix: file.fallbackPrefix
        )
    }

    private func loadAvailableWorkflowIDs() -> [String] {
        let url = WorkflowRegistryStore.defaultRegistryFileURL()
        guard let data = try? Data(contentsOf: url),
              let defs = try? Self.jsonDecoder.decode([WorkflowDefinition].self, from: data) else {
            return []
        }
        return defs.map(\.id).sorted()
    }

    // MARK: - Per-section save

    private func saveFilenameParse() -> RulesPanelSaveOutcome {
        guard let draft = filenameParseDraft else {
            return .ioError(AppError.state("No filename parse draft"))
        }
        var errors: [RulesPanelFieldError] = []

        // conditionDefinition IDs must be unique
        var seenIDs: Set<String> = []
        for def in draft.conditionDefinitions {
            guard seenIDs.insert(def.id).inserted else {
                errors.append(.init(field: "conditionDefinitions", message: "Duplicate condition ID: '\(def.id)'"))
                continue
            }
        }

        // bindings must be canonical
        for def in draft.conditionDefinitions {
            let expected: String
            switch def.kind {
            case "unit_suffix": expected = "conditions.extraConditions.\(def.id)"
            case "token_map":   expected = "conditions.tokenMapRules.\(def.id)"
            default:
                errors.append(.init(field: "conditionDefinitions[\(def.id)].kind", message: "Unknown kind '\(def.kind)'"))
                continue
            }
            if def.binding != expected {
                errors.append(.init(field: "conditionDefinitions[\(def.id)].binding", message: "Must be '\(expected)'"))
            }
        }

        // regex fields
        for (key, pattern) in draft.conditions.extraConditions {
            validateRegex(pattern, field: "conditions.extraConditions[\(key)]", errors: &errors)
        }
        for pattern in draft.batch.fallbackPatterns {
            validateRegex(pattern, field: "batch.fallbackPatterns", errors: &errors)
        }
        for (_, rules) in draft.conditions.tokenMapRules {
            for rule in rules where rule.match.type == "regex" {
                if let p = rule.match.value { validateRegex(p, field: "conditions.tokenMapRules", errors: &errors) }
                rule.match.values?.forEach { validateRegex($0, field: "conditions.tokenMapRules", errors: &errors) }
            }
        }

        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .filenameParse, url: paths.filenameParsRulesURL, value: draft)
    }

    private func saveSampleID() -> RulesPanelSaveOutcome {
        guard let draft = sampleIDDraft else {
            return .ioError(AppError.state("No sample ID draft"))
        }
        var errors: [RulesPanelFieldError] = []
        for pattern in draft.patterns {
            validateRegex(pattern, field: "patterns", errors: &errors)
        }
        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .sampleID, url: paths.sampleIDRulesURL, value: draft)
    }

    private func saveWorkflowMatch() -> RulesPanelSaveOutcome {
        guard let draft = workflowMatchDraft else {
            return .ioError(AppError.state("No workflow match draft"))
        }
        var errors: [RulesPanelFieldError] = []
        var tokenToWorkflow: [String: String] = [:]
        for rule in draft.rules {
            for matchValue in rule.matchValues {
                let key = "\(rule.scope):\(rule.type):\(matchValue)"
                if let existing = tokenToWorkflow[key], existing != rule.workflowID {
                    errors.append(.init(
                        field: "rules",
                        message: "Token '\(matchValue)' maps to both '\(existing)' and '\(rule.workflowID)'"
                    ))
                } else {
                    tokenToWorkflow[key] = rule.workflowID
                }
            }
            if rule.type == "regex" {
                for pattern in rule.matchValues {
                    validateRegex(pattern, field: "rules[\(rule.workflowID)].matchValues", errors: &errors)
                }
            }
        }
        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .workflowMatch, url: paths.workflowMatchRulesURL, value: draft)
    }

    private func saveSubstrate() -> RulesPanelSaveOutcome {
        guard let draft = substrateDraft else {
            return .ioError(AppError.state("No substrate draft"))
        }
        var errors: [RulesPanelFieldError] = []
        if let shared = draft.sharedSubstrate {
            let materialSet = Set(shared.materialTokens)
            for (alias, target) in shared.materialAliases ?? [:] where !materialSet.contains(target) {
                errors.append(.init(field: "sharedSubstrate.materialAliases[\(alias)]", message: "'\(target)' not in materialTokens"))
            }
            let orientationSet = Set(shared.orientationTokens ?? [])
            for (alias, target) in shared.orientationAliases ?? [:] where !orientationSet.contains(target) {
                errors.append(.init(field: "sharedSubstrate.orientationAliases[\(alias)]", message: "'\(target)' not in orientationTokens"))
            }
            validateRegex(shared.orientationPattern, field: "sharedSubstrate.orientationPattern", errors: &errors)
        }
        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .substrate, url: paths.substrateNormalizationRulesURL, value: draft)
    }

    // MARK: - Persist

    private func persist<T: Encodable>(section: RulesPanelSection, url: URL, value: T) -> RulesPanelSaveOutcome {
        let data: Data
        do {
            data = try Self.jsonEncoder.encode(value)
        } catch {
            return .ioError(AppError.io("JSON encode failed: \(error.localizedDescription)"))
        }

        // Hash precondition
        if let openHash = openTimeHashes[section] {
            let currentHash = fileHash(at: url)
            if currentHash != openHash {
                return .externalConflict(externalChecksum: currentHash ?? "")
            }
        }

        do {
            try atomicWriter.write(data, to: url)
        } catch {
            return .ioError(error)
        }

        let newHash = sha256Hex(of: data)
        openTimeHashes[section] = newHash

        _ = RuleLoader.shared.reloadCached()
        onRulesSaved()

        let version = (value as? any _VersionedSchema)?.version ?? 0
        persistenceHook?.didPersist?(section.rawValue, url, version, newHash)

        dirtySections.remove(section)
        return .saved
    }

    // MARK: - Helpers

    private func validateRegex(_ pattern: String, field: String, errors: inout [RulesPanelFieldError]) {
        guard !pattern.isEmpty else { return }
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            errors.append(.init(field: field, message: "Invalid regex '\(pattern)': \(error.localizedDescription)"))
        }
    }

    private func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileHash(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256Hex(of: data)
    }
}

// Internal protocol used only to extract schema version from typed drafts in persist().
private protocol _VersionedSchema {
    var version: Int { get }
}
extension FilenameParseRulesFileDraft: _VersionedSchema {}
extension SampleIDRulesFileDraft: _VersionedSchema {}
extension WorkflowMatchRulesFileDraft: _VersionedSchema {}
extension SubstrateNormalizationRulesFileDraft: _VersionedSchema {}
