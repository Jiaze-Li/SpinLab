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
    case savedWithMirrorWarning(reason: String)
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
        var matchValues: [String]

        enum CodingKeys: String, CodingKey {
            case scope, type, matchValues, value, values
        }

        init(scope: String, type: String, matchValues: [String]) {
            self.scope = scope
            self.type = type
            self.matchValues = matchValues
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Legacy files may omit scope. Default to "tokens" (a valid MatchScope in
            // FilenameRuleSet); defaulting to "" would round-trip through encode and
            // break the runtime loader on next read.
            scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? "tokens"
            type = try container.decode(String.self, forKey: .type)
            if let mv = try container.decodeIfPresent([String].self, forKey: .matchValues) {
                matchValues = mv
            } else if let vs = try container.decodeIfPresent([String].self, forKey: .values) {
                matchValues = vs
            } else if let v = try container.decodeIfPresent(String.self, forKey: .value) {
                matchValues = [v]
            } else {
                matchValues = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scope, forKey: .scope)
            try container.encode(type, forKey: .type)
            try container.encode(matchValues, forKey: .matchValues)
        }
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
        var batchPrefixes: [String]
    }

    struct SubstrateEntry: Codable, Identifiable {
        struct Match: Codable {
            var type: String
            var value: String
        }
        var displayName: String
        var matches: [Match]
        var id: String { displayName }
    }

    struct SubstrateConfig: Codable {
        var materials: [SubstrateEntry]
        var treatments: [SubstrateEntry]
        var orientations: [SubstrateEntry]
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
        var matchValues: [String]

        enum CodingKeys: String, CodingKey {
            case scope, type, matchValues, value, values
        }

        init(scope: String, type: String, matchValues: [String]) {
            self.scope = scope
            self.type = type
            self.matchValues = matchValues
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Legacy files may omit scope. Default to "tokens" (a valid MatchScope in
            // FilenameRuleSet); defaulting to "" would round-trip through encode and
            // break the runtime loader on next read.
            scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? "tokens"
            type = try container.decode(String.self, forKey: .type)
            if let mv = try container.decodeIfPresent([String].self, forKey: .matchValues) {
                matchValues = mv
            } else if let vs = try container.decodeIfPresent([String].self, forKey: .values) {
                matchValues = vs
            } else if let v = try container.decodeIfPresent(String.self, forKey: .value) {
                matchValues = [v]
            } else {
                matchValues = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scope, forKey: .scope)
            try container.encode(type, forKey: .type)
            try container.encode(matchValues, forKey: .matchValues)
        }
    }
}

// measuring_condition.json
struct MeasuringConditionFileDraft: Codable {
    var version: Int
    var conditionDefinitions: [ConditionDefinition]

    struct ConditionDefinition: Codable, Identifiable {
        var id: String
        var label: String?
        var kind: String
        var unitPattern: String?
        var tokenMap: [MapRule]?
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

    private(set) var syncStartupOutcome: StartupOutcome = .skipped
    private(set) var mirrorWarningSectionLabel: String?
    private(set) var mirrorWarningReason: String?

    private let paths = RulesConfigPaths()
    private let atomicWriter = AtomicFileWriter()
    @ObservationIgnored private var syncEngine: RulesSyncEngine?

    private static let jsonEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    private static let jsonDecoder = JSONDecoder()

    init(
        onRulesSaved: @escaping () -> Void = {},
        syncEngine: RulesSyncEngine? = nil,
        syncStartupOutcome: StartupOutcome = .skipped
    ) {
        self.onRulesSaved = onRulesSaved
        self.syncEngine = syncEngine
        self.syncStartupOutcome = syncStartupOutcome
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

        var seenMaterialNames: Set<String> = []
        for m in draft.substrate.materials {
            if m.displayName.isEmpty {
                errors.append(.init(field: "substrate.materials", message: "Material displayName must not be empty"))
            }
            if !seenMaterialNames.insert(m.displayName).inserted {
                errors.append(.init(field: "substrate.materials[\(m.displayName)]", message: "Duplicate material '\(m.displayName)'"))
            }
        }

        var seenTreatmentNames: Set<String> = []
        for t in draft.substrate.treatments {
            if t.displayName.isEmpty {
                errors.append(.init(field: "substrate.treatments", message: "Treatment displayName must not be empty"))
            }
            if !seenTreatmentNames.insert(t.displayName).inserted {
                errors.append(.init(field: "substrate.treatments[\(t.displayName)]", message: "Duplicate treatment '\(t.displayName)'"))
            }
        }

        var seenOrientationNames: Set<String> = []
        for o in draft.substrate.orientations {
            if o.displayName.isEmpty {
                errors.append(.init(field: "substrate.orientations", message: "Orientation displayName must not be empty"))
            }
            if !seenOrientationNames.insert(o.displayName).inserted {
                errors.append(.init(field: "substrate.orientations[\(o.displayName)]", message: "Duplicate orientation '\(o.displayName)'"))
            }
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
                spec.matchValues.forEach { validateRegex($0, field: "workflows[\(w.id)].matchRules", errors: &errors) }
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
            rule.match.matchValues.forEach { validateRegex($0, field: "measurementTagRules", errors: &errors) }
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
                if def.tokenMap != nil {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "unit_suffix must not have tokenMap"))
                }
                let pattern = def.unitPattern ?? ""
                if pattern.isEmpty {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "unit_suffix requires a non-empty unitPattern"))
                } else {
                    validateRegex(pattern, field: "conditionDefinitions[\(def.id)].unitPattern", errors: &errors)
                }
            } else {
                if def.unitPattern != nil {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "token_map must not have unitPattern"))
                }
                if def.tokenMap == nil {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "token_map requires tokenMap"))
                }
                for rule in def.tokenMap ?? [] where rule.match.type == "regex" {
                    rule.match.matchValues.forEach {
                        validateRegex($0, field: "conditionDefinitions[\(def.id)].tokenMap", errors: &errors)
                    }
                }
            }
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

        let dualWriteOutcome: DualWriteOutcome
        do {
            if let syncEngine {
                dualWriteOutcome = try syncEngine.dualWrite(runtimeURL: url, data: data, sectionLabel: section.rawValue)
            } else {
                try atomicWriter.write(data, to: url)
                dualWriteOutcome = .runtimeOnly
            }
        } catch {
            return .ioError(error)
        }

        let newHash = sha256Hex(of: data)
        openTimeHashes[section] = newHash

        _ = RuleLoader.shared.reloadCached()
        _ = RuleLoader.shared.bumpRuleSetVersion()
        onRulesSaved()

        let version = (value as? any _VersionedSchema)?.version ?? 0
        persistenceHook?.didPersist?(section.rawValue, url, version, newHash, dualWriteOutcome)

        dirtySections.remove(section)
        switch dualWriteOutcome {
        case .runtimeOnly, .mirrored:
            mirrorWarningSectionLabel = nil
            mirrorWarningReason = nil
            return .saved
        case .mirrorFailedRuntimeOk(let reason):
            mirrorWarningSectionLabel = section.rawValue
            mirrorWarningReason = reason
            return .savedWithMirrorWarning(reason: reason)
        }
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
