import Foundation
import CryptoKit

struct RuleLoader {
    static let shared = RuleLoader()
    static let currentSchemaVersion = 4
    private static var cached: LoadResult?
    private static var configuredBookPaths: RulesConfigPaths?
    private static var configuredInternalPaths: AppInternalPaths = AppInternalPaths()
    private static let cacheLock = NSLock()
    private let logger = AppLogger.shared

    static func configure(bookPaths: RulesConfigPaths?, internalPaths: AppInternalPaths) {
        withCacheLock {
            configuredBookPaths = bookPaths
            configuredInternalPaths = internalPaths
            cached = nil
        }
    }

    static var currentBookPaths: RulesConfigPaths? {
        withCacheLock { configuredBookPaths }
    }

    /// Loads from Sources/SpinLabApp/config/ relative to the process working directory.
    /// For use in tests and dev tooling only — not called in production.
    func loadFromBundleOnly() -> LoadResult {
        var warnings: [String] = []
        let internalPaths = Self.withCacheLock { Self.configuredInternalPaths }
        let ruleSetVersion = readRuleSetVersion(from: internalPaths.ruleSetStateURL)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let configDir = cwd.appendingPathComponent("Sources/SpinLabApp/config")
        let paths = RulesConfigPaths(configDirectoryURL: configDir)
        if var result = tryLoadFromDirectory(paths, label: "Bundle", warnings: &warnings) {
            result.ruleSetVersion = ruleSetVersion
            return result
        }
        warnings.append("Dev fixture rules not available at \(configDir.path); using built-in fallback.")
        var fallback = FilenameRuleSet.fallback()
        fallback.loadWarnings = warnings
        return LoadResult(
            ruleSet: fallback,
            warnings: warnings,
            metadata: RuleMetadata(
                schemaVersion: fallback.version,
                sourceLabel: "Fallback",
                sourcePath: "builtin:fallback",
                contentHash: hashHex(for: Data("fallback".utf8)),
                loadedAt: Date()
            ),
            ruleSetVersion: ruleSetVersion
        )
    }

    struct RuleMetadata {
        var schemaVersion: Int
        var sourceLabel: String
        var sourcePath: String
        var contentHash: String
        var loadedAt: Date

        var fingerprint: String {
            "v\(schemaVersion):\(contentHash)"
        }

        var contentHashPrefix8: String {
            String(contentHash.prefix(8))
        }
    }

    struct LoadResult {
        var ruleSet: FilenameRuleSet
        var warnings: [String]
        var metadata: RuleMetadata
        var ruleSetVersion: Int

        var ruleSetFingerprint: String { metadata.fingerprint }

        init(
            ruleSet: FilenameRuleSet,
            warnings: [String],
            metadata: RuleMetadata,
            ruleSetVersion: Int = 1
        ) {
            self.ruleSet = ruleSet
            self.warnings = warnings
            self.metadata = metadata
            self.ruleSetVersion = ruleSetVersion
        }
    }

    func load() -> LoadResult {
        var warnings: [String] = []
        let bookPaths = Self.withCacheLock { Self.configuredBookPaths }
        let internalPaths = Self.withCacheLock { Self.configuredInternalPaths }
        let ruleSetVersion = readRuleSetVersion(from: internalPaths.ruleSetStateURL)

        guard let paths = bookPaths else {
            return notConfiguredResult(ruleSetVersion: ruleSetVersion)
        }

        if var result = tryLoadFromDirectory(paths, label: "RulesBook", warnings: &warnings) {
            result.ruleSetVersion = ruleSetVersion
            return result
        }

        warnings.append("Rules could not be loaded from Rules Book at \(paths.configDirectoryURL.path).")
        logger.error(.import, "Rule loading failed", metadata: ["reasons": warnings.joined(separator: " | ")])
        var fallback = FilenameRuleSet.fallback()
        fallback.loadWarnings = warnings
        return LoadResult(
            ruleSet: fallback,
            warnings: warnings,
            metadata: RuleMetadata(
                schemaVersion: fallback.version,
                sourceLabel: "Fallback",
                sourcePath: "builtin:fallback",
                contentHash: hashHex(for: Data("fallback".utf8)),
                loadedAt: Date()
            ),
            ruleSetVersion: ruleSetVersion
        )
    }

    private func notConfiguredResult(ruleSetVersion: Int) -> LoadResult {
        logger.warning(.import, "RuleLoader: no Rules Book configured")
        var fallback = FilenameRuleSet.fallback()
        let warning = "No Rules Book configured."
        fallback.loadWarnings = [warning]
        return LoadResult(
            ruleSet: fallback,
            warnings: [warning],
            metadata: RuleMetadata(
                schemaVersion: fallback.version,
                sourceLabel: "NotConfigured",
                sourcePath: "not-configured",
                contentHash: hashHex(for: Data("not-configured".utf8)),
                loadedAt: Date()
            ),
            ruleSetVersion: ruleSetVersion
        )
    }

    func loadCached() -> LoadResult {
        if let cached = Self.withCacheLock({ Self.cached }),
           !shouldReloadCached(cached) {
            return cached
        }
        let reloaded = load()
        Self.withCacheLock { Self.cached = reloaded }
        return reloaded
    }

    func reloadCached() -> LoadResult {
        let loaded = load()
        Self.withCacheLock { Self.cached = loaded }
        return loaded
    }

    // MARK: - Cache

    private static func withCacheLock<T>(_ action: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return action()
    }

    private func shouldReloadCached(_ cached: LoadResult) -> Bool {
        let path = cached.metadata.sourcePath
        guard !path.hasPrefix("builtin:") && path != "not-configured" else { return false }

        guard let paths = Self.withCacheLock({ Self.configuredBookPaths }) else { return true }
        let hashes = compositeHash(paths: paths)
        let changed = hashes != cached.metadata.contentHash
        if changed {
            logger.info(.import, "Rule cache invalidated (schema file changed)", metadata: [
                "cachedFingerprint": cached.metadata.fingerprint
            ])
        }
        return changed
    }

    // MARK: - Loading

    private func tryLoadFromDirectory(_ paths: RulesConfigPaths, label: String, warnings: inout [String]) -> LoadResult? {
        guard FileManager.default.fileExists(atPath: paths.importFiltersURL.path) else {
            return nil
        }

        do {
            var ruleSet = try assembleRuleSet(from: paths, label: label, warnings: &warnings)
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "\(label) compile warning: \($0)" })
            }
            ruleSet.loadWarnings = warnings
            let hash = compositeHash(paths: paths)
            let metadata = RuleMetadata(
                schemaVersion: ruleSet.version,
                sourceLabel: label,
                sourcePath: paths.importFiltersURL.path,
                contentHash: hash,
                loadedAt: Date()
            )
            logger.info(.import, "Rules loaded", metadata: [
                "source": label,
                "sampleIdPrefixCount": "\(ruleSet.sampleId.matches.count)",
                "ruleVersion": "\(ruleSet.version)",
                "fingerprint": metadata.fingerprint
            ])
            return LoadResult(ruleSet: ruleSet, warnings: warnings, metadata: metadata)
        } catch {
            warnings.append("\(label) rule assembly failed: \(error.localizedDescription)")
            logger.error(.import, "Rule assembly failed", metadata: ["source": label, "reason": error.localizedDescription])
            return nil
        }
    }

    // MARK: - Assembly

    private func assembleRuleSet(from paths: RulesConfigPaths, label: String, warnings: inout [String]) throws -> FilenameRuleSet {
        // D11: fail-fast — any missing file throws immediately
        let requiredFiles: [(URL, String)] = [
            (paths.importFiltersURL, "import_filters.json"),
            (paths.filenameTokenizationURL, "filename_tokenization.json"),
            (paths.sampleIdentificationURL, "sample_identification.json"),
            (paths.workflowURL, "workflow.json"),
            (paths.measuringConditionURL, "measuring_condition.json"),
        ]
        for (url, name) in requiredFiles where !FileManager.default.fileExists(atPath: url.path) {
            throw NSError(domain: "RuleLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(label) \(name) missing at \(url.path)"])
        }

        let importFiltersFile = try loadAndDecode(ImportFiltersFile.self, from: paths.importFiltersURL, label: label)
        let tokenizationFile = try loadAndDecode(FilenameTokenizationFile.self, from: paths.filenameTokenizationURL, label: label)
        let sampleIdentFile = try loadAndDecode(SampleIdentificationFile.self, from: paths.sampleIdentificationURL, label: label)
        let workflowFile = try loadAndDecode(WorkflowFile.self, from: paths.workflowURL, label: label)
        let conditionFile = try loadAndDecode(MeasuringConditionFile.self, from: paths.measuringConditionURL, label: label)

        var ruleSet = FilenameRuleSet(
            version: sampleIdentFile.version,
            tokenization: tokenizationFile.tokenization,
            sources: tokenizationFile.sources,
            sampleId: sampleIdentFile.sampleId,
            measurementNameRules: workflowFile.measurementNameRules,
            measurementTagRules: workflowFile.measurementTagRules,
            channel: tokenizationFile.channel,
            conditions: conditionFile.conditions ?? FilenameRuleSet.ConditionRules(),
            conditionDefinitions: conditionFile.conditionDefinitions,
            registry: nil,
            importRules: importFiltersFile.importRules,
            substrateConfig: sampleIdentFile.substrateConfig
        )

        // library_import_rules.json: registry only (optional)
        if FileManager.default.fileExists(atPath: paths.libraryImportRulesURL.path),
           let data = try? Data(contentsOf: paths.libraryImportRulesURL),
           let file = try? JSONDecoder().decode(LibraryImportRulesFile.self, from: data) {
            ruleSet.registry = file.registry
        }

        let schemaWarnings = migrateRuleSetSchemaIfNeeded(ruleSet: &ruleSet, sourceLabel: label)
        warnings.append(contentsOf: schemaWarnings)
        return ruleSet
    }

    // MARK: - Decode helpers

    private func loadAndDecode<T: Decodable>(_ type: T.Type, from url: URL, label: String) throws -> T {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NSError(domain: "RuleLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode \(url.lastPathComponent) from \(label): \(error.localizedDescription)"])
        }
    }

    // MARK: - Schema migration

    private func migrateRuleSetSchemaIfNeeded(
        ruleSet: inout FilenameRuleSet,
        sourceLabel: String
    ) -> [String] {
        var warnings: [String] = []
        warnings.append(contentsOf: Self.normalizeConditionDefinitionBindings(ruleSet: &ruleSet, sourceLabel: sourceLabel))
        return warnings
    }

    static func normalizeConditionDefinitionBindings(
        ruleSet: inout FilenameRuleSet,
        sourceLabel: String
    ) -> [String] {
        RuleCanonicalizer.normalizeConditionDefinitionBindings(
            ruleSet: &ruleSet,
            sourceLabel: sourceLabel
        )
    }

    // MARK: - Hash

    private func compositeHash(paths: RulesConfigPaths) -> String {
        var parts: [Data] = []
        for url in paths.allSchemaFileURLs {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { continue }
            parts.append(Data(url.lastPathComponent.utf8))
            parts.append(data)
        }
        return hashHex(for: parts.reduce(into: Data(), { $0.append($1) }))
    }

    private func hashHex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - RuleSetState IO (§1.4)

    private struct RuleSetState: Codable {
        var version: Int = 1
        var ruleSetVersion: Int
        var updatedAt: Date
    }

    private func readRuleSetState(from url: URL) -> RuleSetState {
        guard let data = try? Data(contentsOf: url) else {
            return RuleSetState(ruleSetVersion: 1, updatedAt: Date())
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(RuleSetState.self, from: data) else {
            return RuleSetState(ruleSetVersion: 1, updatedAt: Date())
        }
        return state
    }

    private func readRuleSetVersion(from url: URL) -> Int {
        readRuleSetState(from: url).ruleSetVersion
    }

    /// Increments ruleSetVersion by 1 and atomically persists to rule_set_state.json.
    /// Call after a successful Rules Panel save (single section or Save All).
    @discardableResult
    func bumpRuleSetVersion() -> Result<Int, Error> {
        let url = Self.withCacheLock { Self.configuredInternalPaths }.ruleSetStateURL
        var state = readRuleSetState(from: url)
        state.ruleSetVersion += 1
        state.updatedAt = Date()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error(.import, "rule_set_state.json write failed",
                         metadata: ["error": error.localizedDescription])
            return .failure(error)
        }
        let newVersion = state.ruleSetVersion
        Self.withCacheLock { Self.cached?.ruleSetVersion = newVersion }
        logger.info(.import, "ruleSetVersion bumped",
                    metadata: ["version": "\(newVersion)"])
        return .success(newVersion)
    }
}

// MARK: - Per-file Decodable types

private struct ImportFiltersFile: Decodable {
    let version: Int
    let `import`: ImportSection

    var importRules: FilenameRuleSet.ImportRules {
        FilenameRuleSet.ImportRules(
            supportedFileExtensions: `import`.supportedFileExtensions,
            ignoredFileExtensions: `import`.ignoredFileExtensions
        )
    }

    struct ImportSection: Decodable {
        let supportedFileExtensions: [String]
        let ignoredFileExtensions: [String]
    }
}

private struct FilenameTokenizationFile: Decodable {
    let version: Int
    let tokenization: FilenameRuleSet.Tokenization
    let sources: [FilenameRuleSet.Source]
    let channel: FilenameRuleSet.ChannelRules
}

private struct SampleIdentificationFile: Decodable {
    let version: Int
    let sampleId: FilenameRuleSet.SampleIdRules
    let substrateConfig: FilenameRuleSet.SubstrateConfig?

    private enum TopKeys: String, CodingKey { case version, sampleId, substrate }
    private enum SubstrateKeys: String, CodingKey { case materials }

    // v3 material/treatment/orientation intermediate types for inline conversion
    private struct V3Material: Decodable {
        var id: String
        var tokens: [String]
        var aliases: [String]
        var displayName: String
    }
    private struct V3Treatment: Decodable {
        var id: String
        var displayName: String
        var keywords: [String]
        var standaloneTokens: [String]
        var containsTokens: [String]
    }
    private struct V3OrientationConfig: Decodable {
        struct Row: Decodable {
            var id: String
            var tokens: [String]
            var aliases: [String]
        }
        var rows: [Row]
    }
    private struct V3SubstrateSection: Decodable {
        var materials: [V3Material]
        var treatments: [V3Treatment]
        var orientations: V3OrientationConfig
    }

    init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: TopKeys.self)
        version = try top.decode(Int.self, forKey: .version)
        sampleId = try top.decodeIfPresent(FilenameRuleSet.SampleIdRules.self, forKey: .sampleId) ?? .init()
        let sub = try top.nestedContainer(keyedBy: SubstrateKeys.self, forKey: .substrate)

        if version >= 4 {
            // v4: materials/treatments/orientations as SubstrateEntry[]
            substrateConfig = try FilenameRuleSet.SubstrateConfig(from: top.superDecoder(forKey: .substrate))
        } else if sub.contains(.materials) {
            // v3: structured substrate — convert inline to v4
            let v3 = try V3SubstrateSection(from: top.superDecoder(forKey: .substrate))
            substrateConfig = Self.convertV3ToV4(v3)
        } else {
            substrateConfig = nil
        }
    }

    private static func convertV3ToV4(_ v3: V3SubstrateSection) -> FilenameRuleSet.SubstrateConfig {
        let materials: [FilenameRuleSet.SubstrateEntry] = v3.materials.map { m in
            var matches: [FilenameRuleSet.MatchSpec] = []
            for token in m.tokens where token.uppercased() != m.displayName.uppercased() {
                matches.append(.init(type: .equals, value: token))
            }
            for alias in m.aliases {
                matches.append(.init(type: .equals, value: alias))
            }
            return FilenameRuleSet.SubstrateEntry(displayName: m.displayName, matches: matches)
        }
        let treatments: [FilenameRuleSet.SubstrateEntry] = v3.treatments.map { t in
            var matches: [FilenameRuleSet.MatchSpec] = []
            for token in t.standaloneTokens {
                matches.append(.init(type: .equals, value: token))
            }
            for token in t.containsTokens {
                matches.append(.init(type: .contains, value: token))
            }
            for kw in t.keywords
            where !t.standaloneTokens.contains(kw) && !t.containsTokens.contains(kw) {
                matches.append(.init(type: .contains, value: kw))
            }
            return FilenameRuleSet.SubstrateEntry(displayName: t.displayName, matches: matches)
        }
        let orientations: [FilenameRuleSet.SubstrateEntry] = v3.orientations.rows.map { row in
            var matches: [FilenameRuleSet.MatchSpec] = []
            for token in row.tokens where token != row.id {
                matches.append(.init(type: .equals, value: token))
            }
            for alias in row.aliases {
                matches.append(.init(type: .equals, value: alias))
            }
            return FilenameRuleSet.SubstrateEntry(displayName: row.id, matches: matches)
        }
        return FilenameRuleSet.SubstrateConfig(
            materials: materials,
            treatments: treatments,
            orientations: orientations
        )
    }
}

private struct WorkflowFile: Decodable {
    let version: Int
    let workflows: [WorkflowEntry]
    let measurementTagRules: [FilenameRuleSet.MapRule]

    var measurementNameRules: [FilenameRuleSet.MapRule] {
        workflows.flatMap { wf in
            wf.matchRules.map { spec in FilenameRuleSet.MapRule(match: spec, value: wf.id) }
        }
    }

    struct WorkflowEntry: Decodable {
        let id: String
        let matchRules: [FilenameRuleSet.MatchSpec]
    }
}

private struct MeasuringConditionFile: Decodable {
    let version: Int
    let conditions: FilenameRuleSet.ConditionRules?
    let conditionDefinitions: [FilenameRuleSet.ConditionDefinition]
}

struct LibraryImportRulesFile: Decodable {
    let version: Int
    let registry: FilenameRuleSet.RegistryRules?
    let `import`: ImportSection?

    var importRules: FilenameRuleSet.ImportRules? {
        guard let imp = `import` else { return nil }
        return FilenameRuleSet.ImportRules(
            supportedFileExtensions: imp.supportedFileExtensions,
            ignoredFileExtensions: imp.ignoredFileExtensions
        )
    }

    struct ImportSection: Decodable {
        let supportedFileExtensions: [String]
        let ignoredFileExtensions: [String]
    }
}

