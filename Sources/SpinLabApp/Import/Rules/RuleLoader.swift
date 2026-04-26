import Foundation
import CryptoKit

struct RuleLoader {
    static let shared = RuleLoader()
    static let currentSchemaVersion = 2
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

        // Try loading all 7 schema files from runtime first, fall back to bundle
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
        guard FileManager.default.fileExists(atPath: paths.filenameParsRulesURL.path) else {
            warnings.append("\(label) filename_parse_rules.json missing at \(paths.filenameParsRulesURL.path)")
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
                sourcePath: paths.filenameParsRulesURL.path,
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
        guard let parseData = try? locator.data(for: "filename_parse_rules") else {
            warnings.append("Bundle filename_parse_rules.json missing")
            return nil
        }

        do {
            var ruleSet = try assembleRuleSetFromBundle(locator: locator, parseData: parseData, warnings: &warnings)
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "Bundle compile warning: \($0)" })
            }
            ruleSet.loadWarnings = warnings
            let hash = hashHex(for: parseData)
            let metadata = RuleMetadata(
                version: ruleSet.version,
                sourceLabel: "Bundle",
                sourcePath: "bundle:filename_parse_rules.json",
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
        let parseData = try Data(contentsOf: paths.filenameParsRulesURL)
        var ruleSet = try decodeFilenameParseRules(from: parseData, source: label)

        // sample_id_rules.json
        if FileManager.default.fileExists(atPath: paths.sampleIDRulesURL.path),
           let data = try? Data(contentsOf: paths.sampleIDRulesURL),
           let file = try? JSONDecoder().decode(SampleIDRulesFile.self, from: data) {
            ruleSet.sampleId = FilenameRuleSet.SampleIdRules(patterns: file.patterns)
        } else {
            warnings.append("\(label) sample_id_rules.json missing or invalid; using empty patterns")
        }

        // substrate_normalization_rules.json
        if FileManager.default.fileExists(atPath: paths.substrateNormalizationRulesURL.path),
           let data = try? Data(contentsOf: paths.substrateNormalizationRulesURL),
           let file = try? JSONDecoder().decode(SubstrateNormalizationRulesFile.self, from: data) {
            ruleSet.substrateTagRules = file.substrateTagRules
            ruleSet.sharedSubstrate = file.sharedSubstrate
        } else {
            warnings.append("\(label) substrate_normalization_rules.json missing or invalid; substrate rules empty")
        }

        // measurement_tag_rules.json
        if FileManager.default.fileExists(atPath: paths.measurementTagRulesURL.path),
           let data = try? Data(contentsOf: paths.measurementTagRulesURL),
           let file = try? JSONDecoder().decode(MeasurementTagRulesFile.self, from: data) {
            ruleSet.measurementTagRules = file.rules
        } else {
            warnings.append("\(label) measurement_tag_rules.json missing or invalid; using empty measurement tags")
        }

        // library_import_rules.json
        if FileManager.default.fileExists(atPath: paths.libraryImportRulesURL.path),
           let data = try? Data(contentsOf: paths.libraryImportRulesURL),
           let file = try? JSONDecoder().decode(LibraryImportRulesFile.self, from: data) {
            ruleSet.registry = file.registry
            ruleSet.importRules = file.importRules
        } else {
            warnings.append("\(label) library_import_rules.json missing or invalid; library rules empty")
        }

        // workflow_match_rules.json
        if FileManager.default.fileExists(atPath: paths.workflowMatchRulesURL.path),
           let data = try? Data(contentsOf: paths.workflowMatchRulesURL),
           let file = try? JSONDecoder().decode(WorkflowMatchRulesFile.self, from: data) {
            ruleSet.measurementNameRules += file.rules.compactMap { mapRuleFromWorkflowMatch($0) }
        }

        let schemaWarnings = migrateRuleSetSchemaIfNeeded(ruleSet: &ruleSet, sourceLabel: label)
        warnings.append(contentsOf: schemaWarnings)
        return ruleSet
    }

    private func assembleRuleSetFromBundle(locator: BundleFileLocator, parseData: Data, warnings: inout [String]) throws -> FilenameRuleSet {
        var ruleSet = try decodeFilenameParseRules(from: parseData, source: "Bundle")

        if let data = try? locator.data(for: "sample_id_rules"),
           let file = try? JSONDecoder().decode(SampleIDRulesFile.self, from: data) {
            ruleSet.sampleId = FilenameRuleSet.SampleIdRules(patterns: file.patterns)
        }

        if let data = try? locator.data(for: "substrate_normalization_rules"),
           let file = try? JSONDecoder().decode(SubstrateNormalizationRulesFile.self, from: data) {
            ruleSet.substrateTagRules = file.substrateTagRules
            ruleSet.sharedSubstrate = file.sharedSubstrate
        }

        if let data = try? locator.data(for: "measurement_tag_rules"),
           let file = try? JSONDecoder().decode(MeasurementTagRulesFile.self, from: data) {
            ruleSet.measurementTagRules = file.rules
        }

        if let data = try? locator.data(for: "library_import_rules"),
           let file = try? JSONDecoder().decode(LibraryImportRulesFile.self, from: data) {
            ruleSet.registry = file.registry
            ruleSet.importRules = file.importRules
        }

        if let data = try? locator.data(for: "workflow_match_rules"),
           let file = try? JSONDecoder().decode(WorkflowMatchRulesFile.self, from: data) {
            ruleSet.measurementNameRules += file.rules.compactMap { mapRuleFromWorkflowMatch($0) }
        }

        let schemaWarnings = migrateRuleSetSchemaIfNeeded(ruleSet: &ruleSet, sourceLabel: "Bundle")
        warnings.append(contentsOf: schemaWarnings)
        return ruleSet
    }

    // MARK: - Decode

    private func decodeFilenameParseRules(from data: Data, source: String) throws -> FilenameRuleSet {
        do {
            return try JSONDecoder().decode(FilenameRuleSet.self, from: data)
        } catch {
            throw NSError(
                domain: "RuleLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode filename_parse_rules from \(source): \(error.localizedDescription)"]
            )
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

    // MARK: - WorkflowMatch conversion

    private func mapRuleFromWorkflowMatch(_ rule: WorkflowMatchRulesFile.Rule) -> FilenameRuleSet.MapRule? {
        guard !rule.workflowID.isEmpty, !rule.matchValues.isEmpty else { return nil }
        guard let scope = FilenameRuleSet.MatchScope(rawValue: rule.scope),
              let matchType = FilenameRuleSet.MatchType(rawValue: rule.type) else { return nil }
        let spec = FilenameRuleSet.MatchSpec(
            scope: scope,
            type: matchType,
            value: rule.matchValues.count == 1 ? rule.matchValues[0] : nil,
            values: rule.matchValues.count > 1 ? rule.matchValues : nil
        )
        return FilenameRuleSet.MapRule(match: spec, value: rule.workflowID)
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
}

// MARK: - Per-file Decodable types

private struct SampleIDRulesFile: Decodable {
    let version: Int
    let patterns: [String]
}

private struct SubstrateNormalizationRulesFile: Decodable {
    let version: Int
    let substrateTagRules: [FilenameRuleSet.MapRule]
    let sharedSubstrate: FilenameRuleSet.SharedSubstrateRules?
}

private struct MeasurementTagRulesFile: Decodable {
    let version: Int
    let rules: [FilenameRuleSet.MapRule]
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

private struct WorkflowMatchRulesFile: Decodable {
    let version: Int
    let rules: [Rule]

    struct Rule: Decodable {
        let workflowID: String
        let scope: String
        let type: String
        let matchValues: [String]
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
