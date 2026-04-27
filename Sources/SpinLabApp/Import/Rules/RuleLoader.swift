import Foundation
import CryptoKit

struct RuleLoader {
    static let shared = RuleLoader()
    static let currentSchemaVersion = 3
    private static var cached: LoadResult?
    private static let cacheLock = NSLock()
    private let logger = AppLogger.shared

    struct RuleMetadata {
        var version: Int
        var sourceLabel: String
        var sourcePath: String
        var contentHash: String
        var loadedAt: Date

        var fingerprint: String {
            "v\(version):\(contentHash)"
        }

        var contentHashPrefix8: String {
            String(contentHash.prefix(8))
        }
    }

    struct LoadResult {
        var ruleSet: FilenameRuleSet
        var warnings: [String]
        var metadata: RuleMetadata
    }

    func load() -> LoadResult {
        var warnings: [String] = []
        let paths = RulesConfigPaths()

        // Try loading all 5 schema files from runtime first, fall back to bundle
        if let result = tryLoadFromDirectory(paths.configDirectoryURL, label: "Runtime", warnings: &warnings) {
            return result
        }

        // Bundle fallback
        if let result = tryLoadFromBundle(warnings: &warnings) {
            return result
        }

        warnings.append("Rules could not be loaded from runtime or bundle; using built-in fallback.")
        logger.error(.import, "Rule loading failed", metadata: ["reasons": warnings.joined(separator: " | ")])
        var fallback = FilenameRuleSet.fallback()
        fallback.loadWarnings = warnings
        return LoadResult(
            ruleSet: fallback,
            warnings: warnings,
            metadata: RuleMetadata(
                version: fallback.version,
                sourceLabel: "Fallback",
                sourcePath: "builtin:fallback",
                contentHash: hashHex(for: Data("fallback".utf8)),
                loadedAt: Date()
            )
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

    func loadFromBundleOnly() -> LoadResult {
        var warnings: [String] = []
        if let result = tryLoadFromBundle(warnings: &warnings) {
            return result
        }
        warnings.append("Bundle rules not available; using built-in fallback.")
        var fallback = FilenameRuleSet.fallback()
        fallback.loadWarnings = warnings
        return LoadResult(
            ruleSet: fallback,
            warnings: warnings,
            metadata: RuleMetadata(
                version: fallback.version,
                sourceLabel: "Fallback",
                sourcePath: "builtin:fallback",
                contentHash: hashHex(for: Data("fallback".utf8)),
                loadedAt: Date()
            )
        )
    }

    // MARK: - Cache

    private static func withCacheLock<T>(_ action: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return action()
    }

    private func shouldReloadCached(_ cached: LoadResult) -> Bool {
        let path = cached.metadata.sourcePath
        guard !path.hasPrefix("builtin:") else { return false }

        let paths = RulesConfigPaths()
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

    private func tryLoadFromDirectory(_ dir: URL, label: String, warnings: inout [String]) -> LoadResult? {
        let paths = RulesConfigPaths()
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
                version: ruleSet.version,
                sourceLabel: label,
                sourcePath: paths.importFiltersURL.path,
                contentHash: hash,
                loadedAt: Date()
            )
            logger.info(.import, "Rules loaded", metadata: [
                "source": label,
                "sampleIdPatternCount": "\(ruleSet.sampleId.patterns.count)",
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

    private func tryLoadFromBundle(warnings: inout [String]) -> LoadResult? {
        let locator = BundleFileLocator()
        do {
            var ruleSet = try assembleRuleSetFromBundle(locator: locator, warnings: &warnings)
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "Bundle compile warning: \($0)" })
            }
            ruleSet.loadWarnings = warnings
            let hash = bundleCompositeHash(locator: locator)
            let metadata = RuleMetadata(
                version: ruleSet.version,
                sourceLabel: "Bundle",
                sourcePath: "bundle:import_filters.json",
                contentHash: hash,
                loadedAt: Date()
            )
            logger.info(.import, "Rules loaded from bundle", metadata: [
                "sampleIdPatternCount": "\(ruleSet.sampleId.patterns.count)",
                "ruleVersion": "\(ruleSet.version)"
            ])
            return LoadResult(ruleSet: ruleSet, warnings: warnings, metadata: metadata)
        } catch {
            warnings.append("Bundle rule assembly failed: \(error.localizedDescription)")
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
            version: 3,
            tokenization: tokenizationFile.tokenization,
            sources: tokenizationFile.sources,
            sampleId: sampleIdentFile.sampleId,
            measurementNameRules: workflowFile.measurementNameRules,
            measurementTagRules: workflowFile.measurementTagRules,
            substrateTagRules: sampleIdentFile.substrateTagRules,
            channel: tokenizationFile.channel,
            conditions: conditionFile.conditions ?? FilenameRuleSet.ConditionRules(),
            conditionDefinitions: conditionFile.conditionDefinitions,
            registry: nil,
            importRules: importFiltersFile.importRules,
            sharedSubstrate: sampleIdentFile.sharedSubstrate,
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

    private func assembleRuleSetFromBundle(locator: BundleFileLocator, warnings: inout [String]) throws -> FilenameRuleSet {
        let importFiltersData = try requireBundleData(locator: locator, name: "import_filters")
        let tokenizationData = try requireBundleData(locator: locator, name: "filename_tokenization")
        let sampleIdentData = try requireBundleData(locator: locator, name: "sample_identification")
        let workflowData = try requireBundleData(locator: locator, name: "workflow")
        let conditionData = try requireBundleData(locator: locator, name: "measuring_condition")

        let importFiltersFile = try decodeBundleFile(ImportFiltersFile.self, from: importFiltersData, name: "import_filters.json")
        let tokenizationFile = try decodeBundleFile(FilenameTokenizationFile.self, from: tokenizationData, name: "filename_tokenization.json")
        let sampleIdentFile = try decodeBundleFile(SampleIdentificationFile.self, from: sampleIdentData, name: "sample_identification.json")
        let workflowFile = try decodeBundleFile(WorkflowFile.self, from: workflowData, name: "workflow.json")
        let conditionFile = try decodeBundleFile(MeasuringConditionFile.self, from: conditionData, name: "measuring_condition.json")

        var ruleSet = FilenameRuleSet(
            version: 3,
            tokenization: tokenizationFile.tokenization,
            sources: tokenizationFile.sources,
            sampleId: sampleIdentFile.sampleId,
            measurementNameRules: workflowFile.measurementNameRules,
            measurementTagRules: workflowFile.measurementTagRules,
            substrateTagRules: sampleIdentFile.substrateTagRules,
            channel: tokenizationFile.channel,
            conditions: conditionFile.conditions ?? FilenameRuleSet.ConditionRules(),
            conditionDefinitions: conditionFile.conditionDefinitions,
            registry: nil,
            importRules: importFiltersFile.importRules,
            sharedSubstrate: sampleIdentFile.sharedSubstrate,
            substrateConfig: sampleIdentFile.substrateConfig
        )

        // library_import_rules.json: registry only (optional)
        if let data = try? locator.data(for: "library_import_rules"),
           let file = try? JSONDecoder().decode(LibraryImportRulesFile.self, from: data) {
            ruleSet.registry = file.registry
        }

        let schemaWarnings = migrateRuleSetSchemaIfNeeded(ruleSet: &ruleSet, sourceLabel: "Bundle")
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

    private func requireBundleData(locator: BundleFileLocator, name: String) throws -> Data {
        guard let data = try? locator.data(for: name) else {
            throw NSError(domain: "RuleLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bundle \(name).json missing"])
        }
        return data
    }

    private func decodeBundleFile<T: Decodable>(_ type: T.Type, from data: Data, name: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NSError(domain: "RuleLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode bundle \(name): \(error.localizedDescription)"])
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

    private func bundleCompositeHash(locator: BundleFileLocator) -> String {
        let names = ["import_filters", "filename_tokenization", "sample_identification", "workflow", "measuring_condition"]
        var combined = Data()
        for name in names {
            guard let data = try? locator.data(for: name) else { continue }
            combined.append(Data(name.utf8))
            combined.append(data)
        }
        return hashHex(for: combined)
    }

    private func hashHex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
    let substrate: SubstrateSection

    var substrateTagRules: [FilenameRuleSet.MapRule] { substrate.substrateTagRules }
    var sharedSubstrate: FilenameRuleSet.SharedSubstrateRules? { substrate.shared }
    var substrateConfig: FilenameRuleSet.SubstrateConfig? { substrate.substrateConfig }

    struct SubstrateSection: Decodable {
        let substrateTagRules: [FilenameRuleSet.MapRule]
        let shared: FilenameRuleSet.SharedSubstrateRules?
        let substrateConfig: FilenameRuleSet.SubstrateConfig?

        private enum CodingKeys: String, CodingKey {
            case substrateTagRules
            case shared
            case materials
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            substrateTagRules = try container.decodeIfPresent([FilenameRuleSet.MapRule].self, forKey: .substrateTagRules) ?? []
            if container.contains(.materials) {
                substrateConfig = try FilenameRuleSet.SubstrateConfig(from: decoder)
                shared = nil
            } else {
                substrateConfig = nil
                shared = try container.decodeIfPresent(FilenameRuleSet.SharedSubstrateRules.self, forKey: .shared)
            }
        }
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

// MARK: - Bundle locator

struct BundleFileLocator {
    func data(for resourceName: String) throws -> Data? {
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let devURL = cwd.appendingPathComponent("Sources/SpinLabApp/config/\(resourceName).json")
        if FileManager.default.fileExists(atPath: devURL.path) {
            return try Data(contentsOf: devURL)
        }
        return nil
    }
}
