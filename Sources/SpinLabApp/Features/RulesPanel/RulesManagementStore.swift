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
            scope = (try container.decodeIfPresent(String.self, forKey: .scope)) ?? "tokens"
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
            scope = (try container.decodeIfPresent(String.self, forKey: .scope)) ?? "tokens"
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
            try container.encode(type, forKey: .type)
            try container.encode(matchValues, forKey: .matchValues)
        }
    }
}

// measuring_condition.json
struct MeasuringConditionFileDraft: Codable {
    var version: Int
    var conditionDefinitions: [ConditionDefinition]

    struct ConditionDefinition: Identifiable {
        var id: String
        var displayName: String?
        var kind: String
        var unitPattern: String?
        var tokenMap: [MapRule]?
    }
}

extension MeasuringConditionFileDraft.ConditionDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, unitPattern, tokenMap, label, displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        unitPattern = try c.decodeIfPresent(String.self, forKey: .unitPattern)
        tokenMap = try c.decodeIfPresent([MapRule].self, forKey: .tokenMap)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            ?? c.decodeIfPresent(String.self, forKey: .label)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(unitPattern, forKey: .unitPattern)
        try c.encodeIfPresent(tokenMap, forKey: .tokenMap)
        try c.encodeIfPresent(displayName, forKey: .displayName)
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
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? Self.jsonDecoder.decode(T.self, from: data) else {
            return nil
        }
        openTimeHashes[section] = sha256Hex(of: data)
        return decoded
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
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.jsonDecoder.decode(T.self, from: data)
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
