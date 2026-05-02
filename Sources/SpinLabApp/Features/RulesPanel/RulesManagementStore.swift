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

struct ConditionStandardization: Codable, Hashable {
    var standardUnit: String?
    var precision: String?

    var parsedPrecision: Decimal? {
        guard let s = precision?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
              let d = Decimal(string: s), d > 0 else { return nil }
        return d
    }
}

struct MapRule: Codable, Hashable {
    var match: MatchSpec
    var value: String
    var transform: String?

    struct MatchSpec: Codable, Hashable {
        var type: String
        var value: String

        enum CodingKeys: String, CodingKey {
            case type, value, matchValues, values
        }

        init(type: String, value: String) {
            self.type = type
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            if let v = try container.decodeIfPresent(String.self, forKey: .value) {
                value = v
            } else if let mv = try container.decodeIfPresent([String].self, forKey: .matchValues) {
                value = mv.first ?? ""
            } else if let vs = try container.decodeIfPresent([String].self, forKey: .values) {
                value = vs.first ?? ""
            } else {
                value = ""
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    enum CodingKeys: String, CodingKey { case match, value, transform }

    init(match: MatchSpec, value: String, transform: String? = nil) {
        self.match = match
        self.value = value
        self.transform = transform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = try c.decode(MatchSpec.self, forKey: .match)
        value = try c.decode(String.self, forKey: .value)
        transform = try c.decodeIfPresent(String.self, forKey: .transform)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(match, forKey: .match)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(transform, forKey: .transform)
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
        // batchPrefixes retained for view compat; Codable bridges to s12+ "matches" schema
        var batchPrefixes: [String]

        private enum CodingKeys: String, CodingKey { case batchPrefixes, matches }

        init(batchPrefixes: [String]) { self.batchPrefixes = batchPrefixes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            struct Entry: Decodable { let type: String?; let value: String? }
            if let entries = try c.decodeIfPresent([Entry].self, forKey: .matches) {
                batchPrefixes = entries
                    .filter { $0.type == "starts-with" }
                    .compactMap(\.value)
                    .filter { !$0.isEmpty }
            } else {
                batchPrefixes = try c.decodeIfPresent([String].self, forKey: .batchPrefixes) ?? []
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            let matches = batchPrefixes.filter { !$0.isEmpty }.map { ["type": "starts-with", "value": $0] }
            try c.encode(matches, forKey: .matches)
        }
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
        var type: String
        var value: String

        enum CodingKeys: String, CodingKey {
            case type, value, matchValues, values
        }

        init(type: String, value: String) {
            self.type = type
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            if let v = try container.decodeIfPresent(String.self, forKey: .value) {
                value = v
            } else if let mv = try container.decodeIfPresent([String].self, forKey: .matchValues) {
                value = mv.first ?? ""
            } else if let vs = try container.decodeIfPresent([String].self, forKey: .values) {
                value = vs.first ?? ""
            } else {
                value = ""
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

// measuring_condition.json
struct MeasuringConditionFileDraft: Codable {
    var version: Int
    var conditionDefinitions: [ConditionDefinition]

    struct ConditionDefinition: Identifiable, Codable {
        var id: String
        var displayName: String?
        var standardization: ConditionStandardization
        var matches: [MapRule]

        private enum CodingKeys: String, CodingKey {
            case id, displayName, label, standardization, matches
        }

        init(id: String, displayName: String?, standardization: ConditionStandardization = ConditionStandardization(), matches: [MapRule]) {
            self.id = id
            self.displayName = displayName
            self.standardization = standardization
            self.matches = matches
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
                ?? c.decodeIfPresent(String.self, forKey: .label)
            standardization = try c.decodeIfPresent(ConditionStandardization.self, forKey: .standardization)
                ?? ConditionStandardization()
            matches = try c.decodeIfPresent([MapRule].self, forKey: .matches) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(displayName, forKey: .displayName)
            try c.encode(standardization, forKey: .standardization)
            try c.encode(matches, forKey: .matches)
        }
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

    func setBatchPrefixes(from specs: [FilenameRuleSet.MatchSpec]) {
        guard var draft = sampleIdentificationDraft else { return }
        draft.sampleId.batchPrefixes = specs.filter { $0.type == .startsWith }.map(\.value)
        updateSampleIdentification(draft)
    }

    // MARK: - Save / Discard

    func saveCurrent() -> RulesPanelSaveOutcome {
        saveSection(currentSection)
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
        return saveSection(section)
    }

    func reloadAfterExternalChange(section: RulesPanelSection) {
        loadSection(section)
        dirtySections.remove(section)
    }

    // MARK: - Loading

    private func loadSection(_ section: RulesPanelSection) {
        switch section {
        case .importFilters:
            importFiltersDraft = loadWithStrategy(
                ImportFiltersStrategy(runtimeURL: paths.importFiltersURL), section: section)
        case .filenameTokenization:
            filenameTokenizationDraft = loadWithStrategy(
                FilenameTokenizationStrategy(runtimeURL: paths.filenameTokenizationURL), section: section)
        case .sampleIdentification:
            sampleIdentificationDraft = loadWithStrategy(
                SampleIdentificationStrategy(runtimeURL: paths.sampleIdentificationURL), section: section)
        case .workflow:
            workflowDraft = loadWithStrategy(
                WorkflowStrategy(runtimeURL: paths.workflowURL), section: section)
        case .measuringCondition:
            measuringConditionDraft = loadWithStrategy(
                MeasuringConditionStrategy(runtimeURL: paths.measuringConditionURL), section: section)
        }
    }

    private func loadWithStrategy<S: SectionPersistenceStrategy>(
        _ strategy: S, section: RulesPanelSection
    ) -> S.Draft? {
        guard let draft: S.Draft = loadAndCacheHash(url: strategy.runtimeURL, section: section) else {
            return nil
        }
        let effect = strategy.postLoad(draft, context: makeStoreContext())
        applyPostLoadEffect(effect)
        return draft
    }

    private func applyPostLoadEffect(_ effect: PostLoadEffect) {
        switch effect {
        case .none: break
        case .updateConditionFieldIDs(let ids): availableConditionFieldIDs = ids
        }
    }

    private func loadAndCacheHash<T: Decodable>(url: URL, section: RulesPanelSection) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            AppLogger.shared.error(.system, "rules read failed: \(url.lastPathComponent)", metadata: ["error": error.localizedDescription])
            return nil
        }
        do {
            let decoded = try Self.jsonDecoder.decode(T.self, from: data)
            openTimeHashes[section] = sha256Hex(of: data)
            return decoded
        } catch {
            AppLogger.shared.error(.system, "rules decode failed: \(url.lastPathComponent)", metadata: ["error": error.localizedDescription])
            return nil
        }
    }

    // MARK: - Save dispatch

    private func saveSection(_ section: RulesPanelSection) -> RulesPanelSaveOutcome {
        switch section {
        case .importFilters:
            return saveWithStrategy(
                ImportFiltersStrategy(runtimeURL: paths.importFiltersURL),
                draft: importFiltersDraft, section: section)
        case .filenameTokenization:
            return saveWithStrategy(
                FilenameTokenizationStrategy(runtimeURL: paths.filenameTokenizationURL),
                draft: filenameTokenizationDraft, section: section)
        case .sampleIdentification:
            return saveWithStrategy(
                SampleIdentificationStrategy(runtimeURL: paths.sampleIdentificationURL),
                draft: sampleIdentificationDraft, section: section)
        case .workflow:
            return saveWithStrategy(
                WorkflowStrategy(runtimeURL: paths.workflowURL),
                draft: workflowDraft, section: section)
        case .measuringCondition:
            return saveWithStrategy(
                MeasuringConditionStrategy(runtimeURL: paths.measuringConditionURL),
                draft: measuringConditionDraft, section: section)
        }
    }

    private func saveWithStrategy<S: SectionPersistenceStrategy>(
        _ strategy: S, draft: S.Draft?, section: RulesPanelSection
    ) -> RulesPanelSaveOutcome {
        guard let d = draft else {
            return .ioError(AppError.state("No \(section.rawValue) draft loaded"))
        }
        let context = makeStoreContext()
        let errors = strategy.validate(d, context: context)
        if !errors.isEmpty { return .validationFailed(errors) }
        let outcome = persist(section: section, url: strategy.runtimeURL, value: d)
        switch outcome {
        case .saved, .savedWithMirrorWarning:
            strategy.postPersist(d, context: context)
        default: break
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

    // MARK: - Context factory

    private func makeStoreContext() -> StoreContext {
        StoreContext(
            dirtyMeasuringCondition: dirtySections.contains(.measuringCondition) ? measuringConditionDraft : nil,
            dirtyWorkflow: dirtySections.contains(.workflow) ? workflowDraft : nil,
            loadMeasuringConditionFromDisk: { [weak self] in
                guard let self else { return nil }
                return self.loadFromDiskOnly(url: self.paths.measuringConditionURL)
            },
            loadWorkflowFromDisk: { [weak self] in
                guard let self else { return nil }
                return self.loadFromDiskOnly(url: self.paths.workflowURL)
            }
        )
    }

    // MARK: - Helpers

    private func loadFromDiskOnly<T: Decodable>(url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            AppLogger.shared.error(.system, "rules read failed: \(url.lastPathComponent)", metadata: ["error": error.localizedDescription])
            return nil
        }
        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            AppLogger.shared.error(.system, "rules decode failed: \(url.lastPathComponent)", metadata: ["error": error.localizedDescription])
            return nil
        }
    }

    private func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileHash(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return sha256Hex(of: data)
        } catch {
            AppLogger.shared.error(.system, "rules read failed: \(url.lastPathComponent)", metadata: ["error": error.localizedDescription])
            return nil
        }
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
