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

// MARK: - Shared types

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

// MARK: - Draft types (Codable mirrors of each 5-book schema file)

// import_filters.json
struct ImportFiltersFileDraft: Codable {
    var version: Int
    var config: ImportConfig

    struct ImportConfig: Codable {
        var supportedFileExtensions: [String]
        var ignoredFileExtensions: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case config = "import"
    }
}

// filename_tokenization.json
struct FilenameTokenizationFileDraft: Codable {
    var version: Int
    var tokenization: Tokenization
    var sources: [String]
    var channel: Channel

    struct Tokenization: Codable {
        var separators: String
        var caseFold: String
    }
    struct Channel: Codable {
        var aliases: [String: String]
    }
}

// sample_identification.json
struct SampleIdentificationFileDraft: Codable {
    var version: Int
    var sampleId: SampleIdConfig
    var substrate: SubstrateConfig

    struct SampleIdConfig: Codable {
        var patterns: [String]
    }
    struct SubstrateConfig: Codable {
        var substrateTagRules: [MapRule]
        var shared: SharedSubstrate?

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
}

// workflow.json
struct WorkflowFileDraft: Codable {
    var version: Int
    var workflows: [WorkflowEntry]
    var measurementTagRules: [MapRule]

    struct WorkflowEntry: Codable, Identifiable {
        var id: String
        var displayName: String
        var matchRules: [WorkflowMatchSpec]
        var conditionFieldIDs: [String]
    }

    struct WorkflowMatchSpec: Codable, Hashable {
        var scope: String
        var type: String
        var value: String?
        var values: [String]?
    }
}

// measuring_condition.json
struct MeasuringConditionFileDraft: Codable {
    var version: Int
    var batch: Batch
    var conditions: Conditions
    var conditionDefinitions: [ConditionDefinition]

    struct Batch: Codable {
        var preferSampleId: Bool
        var fallbackPatterns: [String]
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

// MARK: - Store

@MainActor @Observable
final class RulesManagementStore {

    private(set) var currentSection: RulesPanelSection = .importFilters
    private(set) var dirtySections: Set<RulesPanelSection> = []

    private(set) var importFiltersDraft: ImportFiltersFileDraft?
    private(set) var filenameTokenizationDraft: FilenameTokenizationFileDraft?
    private(set) var sampleIdentificationDraft: SampleIdentificationFileDraft?
    private(set) var workflowDraft: WorkflowFileDraft?
    private(set) var measuringConditionDraft: MeasuringConditionFileDraft?

    // Derived from measuringConditionDraft; refreshed on load + external reload
    private(set) var availableConditionFieldIDs: [String] = []

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
        for section in RulesPanelSection.allCases {
            loadSection(section)
        }
    }

    // MARK: - Navigation

    func selectSection(_ section: RulesPanelSection) {
        currentSection = section
    }

    // MARK: - Draft updates (each call marks section dirty)

    func updateImportFilters(_ draft: ImportFiltersFileDraft) {
        importFiltersDraft = draft
        dirtySections.insert(.importFilters)
    }

    func updateFilenameTokenization(_ draft: FilenameTokenizationFileDraft) {
        filenameTokenizationDraft = draft
        dirtySections.insert(.filenameTokenization)
    }

    func updateSampleIdentification(_ draft: SampleIdentificationFileDraft) {
        sampleIdentificationDraft = draft
        dirtySections.insert(.sampleIdentification)
    }

    func updateWorkflow(_ draft: WorkflowFileDraft) {
        workflowDraft = draft
        dirtySections.insert(.workflow)
    }

    func updateMeasuringCondition(_ draft: MeasuringConditionFileDraft) {
        measuringConditionDraft = draft
        availableConditionFieldIDs = draft.conditionDefinitions.map(\.id)
        dirtySections.insert(.measuringCondition)
    }

    // MARK: - Save / Discard

    func saveCurrent() -> RulesPanelSaveOutcome {
        switch currentSection {
        case .importFilters:        return saveImportFilters()
        case .filenameTokenization: return saveFilenameTokenization()
        case .sampleIdentification: return saveSampleIdentification()
        case .workflow:             return saveWorkflow()
        case .measuringCondition:   return saveMeasuringCondition()
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

    func overrideWithCurrentDraft(section: RulesPanelSection) -> RulesPanelSaveOutcome {
        openTimeHashes.removeValue(forKey: section)
        switch section {
        case .importFilters:        return saveImportFilters()
        case .filenameTokenization: return saveFilenameTokenization()
        case .sampleIdentification: return saveSampleIdentification()
        case .workflow:             return saveWorkflow()
        case .measuringCondition:   return saveMeasuringCondition()
        }
    }

    func reloadAfterExternalChange(section: RulesPanelSection) {
        loadSection(section)
        dirtySections.remove(section)
    }

    // MARK: - Loading

    private func loadSection(_ section: RulesPanelSection) {
        switch section {
        case .importFilters:
            importFiltersDraft = loadAndCacheHash(url: paths.importFiltersURL, section: section)
        case .filenameTokenization:
            filenameTokenizationDraft = loadAndCacheHash(url: paths.filenameTokenizationURL, section: section)
        case .sampleIdentification:
            sampleIdentificationDraft = loadAndCacheHash(url: paths.sampleIdentificationURL, section: section)
        case .workflow:
            workflowDraft = loadAndCacheHash(url: paths.workflowURL, section: section)
        case .measuringCondition:
            let draft: MeasuringConditionFileDraft? = loadAndCacheHash(url: paths.measuringConditionURL, section: section)
            measuringConditionDraft = draft
            availableConditionFieldIDs = draft?.conditionDefinitions.map(\.id) ?? []
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

    // MARK: - Per-section save

    private func saveImportFilters() -> RulesPanelSaveOutcome {
        guard let draft = importFiltersDraft else {
            return .ioError(AppError.state("No import filters draft"))
        }
        var errors: [RulesPanelFieldError] = []

        // No extension may contain spaces
        let allExts = draft.config.supportedFileExtensions + draft.config.ignoredFileExtensions
        for ext in allExts where ext.contains(" ") {
            errors.append(.init(field: "extensions", message: "Extension '\(ext)' must not contain spaces"))
        }
        // No extension may start with '.'
        for ext in allExts where ext.hasPrefix(".") {
            errors.append(.init(field: "extensions", message: "Extension '\(ext)' must not start with '.'"))
        }
        // supported and ignored must not overlap
        let supported = Set(draft.config.supportedFileExtensions)
        let ignored = Set(draft.config.ignoredFileExtensions)
        let overlap = supported.intersection(ignored)
        for ext in overlap.sorted() {
            errors.append(.init(field: "extensions", message: "'\(ext)' is in both supported and ignored"))
        }

        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .importFilters, url: paths.importFiltersURL, value: draft)
    }

    private func saveFilenameTokenization() -> RulesPanelSaveOutcome {
        guard let draft = filenameTokenizationDraft else {
            return .ioError(AppError.state("No filename tokenization draft"))
        }
        var errors: [RulesPanelFieldError] = []

        if draft.tokenization.separators.isEmpty {
            errors.append(.init(field: "tokenization.separators", message: "Separators must not be empty"))
        }

        let allowedSources: Set<String> = ["file", "parent", "grandparent"]
        let dedupedSources = Array(NSOrderedSet(array: draft.sources)) as? [String] ?? draft.sources
        if dedupedSources.isEmpty {
            errors.append(.init(field: "sources", message: "Sources must contain at least one entry"))
        }
        for source in dedupedSources where !allowedSources.contains(source) {
            errors.append(.init(field: "sources", message: "Unknown source '\(source)'; allowed: file, parent, grandparent"))
        }

        for (key, value) in draft.channel.aliases {
            if key.isEmpty || value.isEmpty {
                errors.append(.init(field: "channel.aliases", message: "Alias key and value must not be empty"))
            }
        }

        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .filenameTokenization, url: paths.filenameTokenizationURL, value: draft)
    }

    private func saveSampleIdentification() -> RulesPanelSaveOutcome {
        guard let draft = sampleIdentificationDraft else {
            return .ioError(AppError.state("No sample identification draft"))
        }
        var errors: [RulesPanelFieldError] = []

        for pattern in draft.sampleId.patterns {
            validateRegex(pattern, field: "sampleId.patterns", errors: &errors)
        }

        if let shared = draft.substrate.shared {
            let materialSet = Set(shared.materialTokens)
            for (alias, target) in shared.materialAliases ?? [:] where !materialSet.contains(target) {
                errors.append(.init(field: "substrate.shared.materialAliases[\(alias)]",
                                    message: "'\(target)' not in materialTokens"))
            }
            let orientationSet = Set(shared.orientationTokens ?? [])
            for (alias, target) in shared.orientationAliases ?? [:] where !orientationSet.contains(target) {
                errors.append(.init(field: "substrate.shared.orientationAliases[\(alias)]",
                                    message: "'\(target)' not in orientationTokens"))
            }
            if let displayNames = shared.materialDisplayNames {
                for key in displayNames.keys where !materialSet.contains(key) {
                    errors.append(.init(field: "substrate.shared.materialDisplayNames[\(key)]",
                                        message: "'\(key)' not in materialTokens — will not take effect"))
                }
            }
            validateRegex(shared.orientationPattern, field: "substrate.shared.orientationPattern", errors: &errors)
        }

        for rule in draft.substrate.substrateTagRules where rule.match.type == "regex" {
            if let p = rule.match.value { validateRegex(p, field: "substrate.substrateTagRules", errors: &errors) }
            rule.match.values?.forEach { validateRegex($0, field: "substrate.substrateTagRules", errors: &errors) }
        }

        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .sampleIdentification, url: paths.sampleIdentificationURL, value: draft)
    }

    private func saveWorkflow() -> RulesPanelSaveOutcome {
        guard let draft = workflowDraft else {
            return .ioError(AppError.state("No workflow draft"))
        }
        var errors: [RulesPanelFieldError] = []

        // workflow IDs must be non-empty, no whitespace, unique
        var seenIDs: Set<String> = []
        for w in draft.workflows {
            if w.id.isEmpty || w.id.contains(where: \.isWhitespace) {
                errors.append(.init(field: "workflows[\(w.id)].id",
                                    message: "Workflow ID must be non-empty and contain no whitespace"))
            }
            if !seenIDs.insert(w.id).inserted {
                errors.append(.init(field: "workflows[\(w.id)].id",
                                    message: "Duplicate workflow ID '\(w.id)'"))
            }
            if w.displayName.isEmpty {
                errors.append(.init(field: "workflows[\(w.id)].displayName",
                                    message: "Display name must not be empty"))
            }
            if w.matchRules.isEmpty {
                errors.append(.init(field: "workflows[\(w.id)].matchRules",
                                    message: "Workflow '\(w.id)' must have at least one match rule"))
            }
            for spec in w.matchRules where spec.type == "regex" {
                if let p = spec.value { validateRegex(p, field: "workflows[\(w.id)].matchRules", errors: &errors) }
                spec.values?.forEach { validateRegex($0, field: "workflows[\(w.id)].matchRules", errors: &errors) }
            }
        }

        // conditionFieldIDs cross-section validation
        // Use dirty measuringConditionDraft if present, else load from disk
        let knownConditionIDs: Set<String>
        if dirtySections.contains(.measuringCondition), let mc = measuringConditionDraft {
            knownConditionIDs = Set(mc.conditionDefinitions.map(\.id))
        } else {
            let mc: MeasuringConditionFileDraft? = loadFromDiskOnly(url: paths.measuringConditionURL)
            knownConditionIDs = Set(mc?.conditionDefinitions.map(\.id) ?? [])
        }
        for w in draft.workflows {
            for fieldID in w.conditionFieldIDs where !knownConditionIDs.contains(fieldID) {
                errors.append(.init(field: "workflows[\(w.id)].conditionFieldIDs",
                                    message: "Condition '\(fieldID)' not found in measuring_condition.json"))
            }
        }

        for rule in draft.measurementTagRules where rule.match.type == "regex" {
            if let p = rule.match.value { validateRegex(p, field: "measurementTagRules", errors: &errors) }
            rule.match.values?.forEach { validateRegex($0, field: "measurementTagRules", errors: &errors) }
        }

        if !errors.isEmpty { return .validationFailed(errors) }
        return persist(section: .workflow, url: paths.workflowURL, value: draft)
    }

    private func saveMeasuringCondition() -> RulesPanelSaveOutcome {
        guard let draft = measuringConditionDraft else {
            return .ioError(AppError.state("No measuring condition draft"))
        }
        var errors: [RulesPanelFieldError] = []

        var seenIDs: Set<String> = []
        for def in draft.conditionDefinitions {
            if !seenIDs.insert(def.id).inserted {
                errors.append(.init(field: "conditionDefinitions", message: "Duplicate condition ID '\(def.id)'"))
            }
            guard def.kind == "unit_suffix" || def.kind == "token_map" else {
                errors.append(.init(field: "conditionDefinitions[\(def.id)].kind",
                                    message: "Unknown kind '\(def.kind)'"))
                continue
            }
            if def.kind == "unit_suffix" {
                if let pattern = draft.conditions.extraConditions[def.id] {
                    validateRegex(pattern, field: "conditions.extraConditions[\(def.id)]", errors: &errors)
                } else {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "unit_suffix kind requires entry in conditions.extraConditions"))
                }
            } else {
                if let rules = draft.conditions.tokenMapRules[def.id] {
                    for rule in rules where rule.match.type == "regex" {
                        if let p = rule.match.value {
                            validateRegex(p, field: "conditions.tokenMapRules[\(def.id)]", errors: &errors)
                        }
                        rule.match.values?.forEach {
                            validateRegex($0, field: "conditions.tokenMapRules[\(def.id)]", errors: &errors)
                        }
                    }
                } else {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "token_map kind requires entry in conditions.tokenMapRules"))
                }
            }
        }

        for pattern in draft.batch.fallbackPatterns {
            validateRegex(pattern, field: "batch.fallbackPatterns", errors: &errors)
        }

        if !errors.isEmpty { return .validationFailed(errors) }
        let outcome = persist(section: .measuringCondition, url: paths.measuringConditionURL, value: draft)

        // Soft warning: check for dangling references in workflow
        if case .saved = outcome {
            let savedIDs = Set(draft.conditionDefinitions.map(\.id))
            if let wf = workflowDraft ?? loadFromDiskOnly(url: paths.workflowURL) as WorkflowFileDraft? {
                let danglingWorkflows = wf.workflows.filter { w in
                    w.conditionFieldIDs.contains { !savedIDs.contains($0) }
                }
                if !danglingWorkflows.isEmpty {
                    // Not blocking — just surface via hook for potential UI display
                    let names = danglingWorkflows.map(\.id).joined(separator: ", ")
                    _ = names // Dangling reference warning available for UI layer if needed
                }
            }
        }
        return outcome
    }

    // MARK: - Persist

    private func persist<T: Encodable>(section: RulesPanelSection, url: URL, value: T) -> RulesPanelSaveOutcome {
        let data: Data
        do {
            data = try Self.jsonEncoder.encode(value)
        } catch {
            return .ioError(AppError.io("JSON encode failed: \(error.localizedDescription)"))
        }

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

    private func loadFromDiskOnly<T: Decodable>(url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.jsonDecoder.decode(T.self, from: data)
    }

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

private protocol _VersionedSchema {
    var version: Int { get }
}
extension ImportFiltersFileDraft: _VersionedSchema {}
extension FilenameTokenizationFileDraft: _VersionedSchema {}
extension SampleIdentificationFileDraft: _VersionedSchema {}
extension WorkflowFileDraft: _VersionedSchema {}
extension MeasuringConditionFileDraft: _VersionedSchema {}
