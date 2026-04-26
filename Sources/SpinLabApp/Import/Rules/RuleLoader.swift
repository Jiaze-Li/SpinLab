import Foundation
import CryptoKit

struct RuleLoader {
    static let shared = RuleLoader()
    static let currentSchemaVersion = 1
    private static var cached: LoadResult?
    private static let cacheLock = NSLock()
    private let logger = AppLogger.shared

    struct RuleMetadata {
        var version: Int
        var sourceLabel: String
        var sourcePath: String
        var contentHash: String
        var loadedOverrideFiles: [String]
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

        let appSupportURL = rulesConfigPaths().ruleURL
        logger.info(.import, "Rule source probe", metadata: [
            "source": "ApplicationSupport",
            "path": appSupportURL.path
        ])
        if let loaded = tryLoadRuleSet(
            from: appSupportURL,
            sourceLabel: "ApplicationSupport",
            appendsMissingToWarnings: true,
            warnings: &warnings
        ) {
            return loaded
        }

        for bundleURL in bundleRuleCandidateURLs() {
            logger.info(.import, "Rule source probe", metadata: [
                "source": "Bundle",
                "path": bundleURL.path
            ])
            if let loaded = tryLoadRuleSet(
                from: bundleURL,
                sourceLabel: "Bundle",
                appendsMissingToWarnings: false,
                warnings: &warnings
            ) {
                return loaded
            }
        }

        warnings.append("Filename rules could not be loaded from Application Support or bundle candidates.")
        logger.error(.import, "Rule loading failed", metadata: [
            "reasons": warnings.joined(separator: " | ")
        ])
        var fallback = FilenameRuleSet.fallback()
        fallback.loadWarnings = warnings
        let fallbackMetadata = RuleMetadata(
            version: fallback.version,
            sourceLabel: "Fallback",
            sourcePath: "builtin:fallback",
            contentHash: hashHex(for: Data("fallback".utf8)),
            loadedOverrideFiles: [],
            loadedAt: Date()
        )
        return LoadResult(ruleSet: fallback, warnings: warnings, metadata: fallbackMetadata)
    }

    func loadCached() -> LoadResult {
        if let cached = Self.withCacheLock({ Self.cached }),
           !shouldReloadCached(cached) {
            return cached
        }
        let reloaded = load()
        Self.withCacheLock {
            Self.cached = reloaded
        }
        return reloaded
    }

    func reloadCached() -> LoadResult {
        let loaded = load()
        Self.withCacheLock {
            Self.cached = loaded
        }
        return loaded
    }

    private static func withCacheLock<T>(_ action: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return action()
    }

    private func shouldReloadCached(_ cached: LoadResult) -> Bool {
        let path = cached.metadata.sourcePath
        if path.hasPrefix("builtin:") {
            return false
        }

        guard FileManager.default.fileExists(atPath: path) else {
            logger.info(.import, "Rule cache invalidated because source file disappeared", metadata: [
                "path": path,
                "cachedFingerprint": cached.metadata.fingerprint
            ])
            return true
        }

        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.info(.import, "Rule cache invalidated because source file cannot be read", metadata: [
                "path": path,
                "cachedFingerprint": cached.metadata.fingerprint,
                "reason": error.localizedDescription
            ])
            return true
        }

        let latestHash = compositeHash(primaryData: data, primaryURL: url)
        let changed = latestHash != cached.metadata.contentHash
        if changed {
            logger.info(.import, "Rule cache invalidated because source hash changed", metadata: [
                "path": path,
                "cachedFingerprint": cached.metadata.fingerprint,
                "latestHash": latestHash
            ])
        }
        return changed
    }

    private func tryLoadRuleSet(
        from url: URL,
        sourceLabel: String,
        appendsMissingToWarnings: Bool,
        warnings: inout [String]
    ) -> LoadResult? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if appendsMissingToWarnings {
                warnings.append("\(sourceLabel) file missing at \(url.path)")
            } else {
                logger.info(.import, "Bundle candidate not present", metadata: [
                    "source": sourceLabel,
                    "path": url.path
                ])
            }
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let reason = error.localizedDescription
            warnings.append("\(sourceLabel) read failed at \(url.path): \(reason)")
            logger.error(.import, "Rule source read failed", metadata: [
                "source": sourceLabel,
                "path": url.path,
                "reason": reason
            ])
            return nil
        }

        do {
            var ruleSet = try decodeRuleSet(from: data, source: "\(sourceLabel):\(url.path)")
            let schemaWarnings = migrateRuleSetSchemaIfNeeded(ruleSet: &ruleSet, sourceLabel: sourceLabel)
            warnings.append(contentsOf: schemaWarnings)
            let overrideResult = applySeparatedOverrides(ruleSet: &ruleSet)
            warnings.append(contentsOf: overrideResult.warnings)
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "\(sourceLabel) compile warning: \($0)" })
            }
            ruleSet.loadWarnings = warnings
            let metadata = RuleMetadata(
                version: ruleSet.version,
                sourceLabel: sourceLabel,
                sourcePath: url.path,
                contentHash: compositeHash(primaryData: data, primaryURL: url),
                loadedOverrideFiles: overrideResult.loadedOverrideFiles,
                loadedAt: Date()
            )
            logger.info(.import, "Rule source loaded", metadata: [
                "source": sourceLabel,
                "path": url.path,
                "sampleIdPatternCount": "\(ruleSet.sampleId.patterns.count)",
                "ruleVersion": "\(ruleSet.version)",
                "ruleFingerprint": metadata.fingerprint,
                "ruleHashPrefix": metadata.contentHashPrefix8,
                "loadedOverrideFiles": metadata.loadedOverrideFiles.joined(separator: ",")
            ])
            return LoadResult(ruleSet: ruleSet, warnings: warnings, metadata: metadata)
        } catch {
            let reason = error.localizedDescription
            warnings.append("\(sourceLabel) decode failed at \(url.path): \(reason)")
            logger.error(.import, "Rule source decode failed", metadata: [
                "source": sourceLabel,
                "path": url.path,
                "reason": reason
            ])
            return nil
        }
    }

    private func hashHex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func decodeRuleSet(from data: Data, source: String) throws -> FilenameRuleSet {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(FilenameRuleSet.self, from: data)
        } catch {
            throw NSError(
                domain: "RuleLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode rules from \(source): \(error.localizedDescription)"]
            )
        }
    }

    private struct OverrideApplyResult {
        var warnings: [String]
        var loadedOverrideFiles: [String]
    }

    /// Resolves the override file URL: prefers Application Support, falls back to bundle.
    /// In test environments (without explicit opt-in), only bundle is checked.
    private func resolveOverrideURL(filename: String) -> URL? {
        let isTest = RulesConfigPaths.isRunningTests() && !shouldEnableSeparatedOverridesDuringTests()
        if !isTest {
            let runtimeURL = rulesConfigPaths().configDirectoryURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: runtimeURL.path) {
                return runtimeURL
            }
        }
        // Bundle fallback: check all candidate bundle config directories.
        for candidate in bundleOverrideCandidateURLs(filename: filename) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func bundleOverrideCandidateURLs(filename: String) -> [URL] {
        // SwiftPM `.process("config")` flattens files into the module's resource
        // bundle root, so look up via `Bundle.module` without a `subdirectory:`.
        let resourceName = filename.replacingOccurrences(of: ".json", with: "")
        var candidates: [URL] = []
        if let direct = Bundle.module.url(forResource: resourceName, withExtension: "json") {
            candidates.append(direct)
        }
        // Dev fallback: `swift test` invoked from the project root.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(cwd.appendingPathComponent("Sources/SpinLabApp/config/\(filename)"))
        return candidates
    }

    private func applySeparatedOverrides(ruleSet: inout FilenameRuleSet) -> OverrideApplyResult {
        var warnings: [String] = []
        var loadedOverrideFiles: [String] = []

        // --- sample_id_rules.json ---
        if let sampleIDURL = resolveOverrideURL(filename: "sample_id_rules.json") {
            if let patterns = SeparatedOverrideReader.readSampleIDPatterns(from: sampleIDURL) {
                ruleSet.sampleId = .init(patterns: patterns)
                loadedOverrideFiles.append(sampleIDURL.lastPathComponent)
            } else {
                warnings.append("sample_id_rules.json contains no valid patterns or is unreadable; keeping existing sampleId rules.")
            }
        }

        // --- workflow_match_rules.json ---
        if let workflowURL = resolveOverrideURL(filename: "workflow_match_rules.json") {
            if let entries = SeparatedOverrideReader.readWorkflowMatchRules(from: workflowURL) {
                let parsed = entries.map { $0.asMapRule() }
                if parsed.isEmpty {
                    warnings.append("workflow_match_rules.json contains no valid rules; keeping existing workflow rules.")
                } else {
                    ruleSet.measurementNameRules = parsed
                    loadedOverrideFiles.append(workflowURL.lastPathComponent)
                }
            } else {
                warnings.append("workflow_match_rules.json is invalid or unreadable; ignoring workflow override.")
            }
        }

        // --- conditions_rules.json ---
        if let conditionsURL = resolveOverrideURL(filename: "conditions_rules.json") {
            if let patch = SeparatedOverrideReader.readConditions(from: conditionsURL) {
                // Apply extra conditions: set values and remove deleted keys.
                for (key, pattern) in patch.extraConditions {
                    ruleSet.conditions.extraConditions[key] = pattern
                }
                for key in patch.deletedExtraConditionKeys {
                    ruleSet.conditions.extraConditions.removeValue(forKey: key)
                }
                // Apply token map rules: each key from override replaces existing.
                for (key, mappings) in patch.tokenMapRules {
                    ruleSet.conditions.tokenMapRules[key] = mappings.map { $0.asMapRule() }
                }
                loadedOverrideFiles.append(conditionsURL.lastPathComponent)
            } else {
                warnings.append("conditions_rules.json contains no supported keys or is unreadable; keeping existing condition rules.")
            }
        }

        // --- substrate_rules.json ---
        if let substrateURL = resolveOverrideURL(filename: "substrate_rules.json") {
            if let patch = SeparatedOverrideReader.readSubstrateRules(from: substrateURL) {
                if let tagRules = patch.substrateTagRules {
                    let converted = tagRules.map { $0.asMapRule() }
                    if converted.isEmpty {
                        warnings.append("substrate_rules.json substrateTagRules is empty; keeping existing substrateTagRules.")
                    } else {
                        ruleSet.substrateTagRules = converted
                    }
                }
                if let shared = patch.sharedSubstrate {
                    ruleSet.sharedSubstrate = shared
                }
                loadedOverrideFiles.append(substrateURL.lastPathComponent)
            } else {
                warnings.append("substrate_rules.json contains no supported keys or is unreadable; keeping existing substrate rules.")
            }
        }

        // --- measurement_tag_rules.json ---
        if let measurementTagURL = resolveOverrideURL(filename: "measurement_tag_rules.json") {
            if let entries = SeparatedOverrideReader.readMeasurementTagRules(from: measurementTagURL) {
                let converted = entries.map { $0.asMapRule() }
                if converted.isEmpty {
                    warnings.append("measurement_tag_rules.json contains empty rules; keeping existing measurementTagRules.")
                } else {
                    ruleSet.measurementTagRules = converted
                    loadedOverrideFiles.append(measurementTagURL.lastPathComponent)
                }
            } else {
                warnings.append("measurement_tag_rules.json is invalid or unreadable; keeping existing measurementTagRules.")
            }
        }

        loadedOverrideFiles = Array(Set(loadedOverrideFiles)).sorted()
        return OverrideApplyResult(warnings: warnings, loadedOverrideFiles: loadedOverrideFiles)
    }

    private func migrateRuleSetSchemaIfNeeded(
        ruleSet: inout FilenameRuleSet,
        sourceLabel: String
    ) -> [String] {
        var warnings: [String] = []
        warnings.append(contentsOf: Self.normalizeConditionDefinitionBindings(ruleSet: &ruleSet, sourceLabel: sourceLabel))

        if ruleSet.version == Self.currentSchemaVersion {
            return warnings
        }

        if ruleSet.version < Self.currentSchemaVersion {
            warnings.append(
                "\(sourceLabel) schema v\(ruleSet.version) is older than supported v\(Self.currentSchemaVersion); applying compatibility migration."
            )
            // Keep decoded values; only normalize the schema marker so metadata/reporting
            // reflects the runtime schema interpretation.
            ruleSet.version = Self.currentSchemaVersion
            return warnings
        }

        warnings.append(
            "\(sourceLabel) schema v\(ruleSet.version) is newer than supported v\(Self.currentSchemaVersion); loading in compatibility mode."
        )
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

    private func rulesConfigPaths() -> RulesConfigPaths {
        RulesConfigPaths(fileManager: .default)
    }

    private func compositeHash(primaryData: Data, primaryURL: URL) -> String {
        var parts: [Data] = [primaryData]
        let paths = rulesConfigPaths()
        for url in [
            paths.sampleIDRulesURL,
            paths.workflowMatchRulesURL,
            paths.conditionsRulesURL,
            paths.substrateRulesURL,
            paths.measurementTagRulesURL
        ] {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                continue
            }
            parts.append(Data(url.path.utf8))
            parts.append(data)
        }
        return hashHex(for: parts.reduce(into: Data(), { $0.append($1) }))
    }

    private func shouldEnableSeparatedOverridesDuringTests() -> Bool {
        let value = ProcessInfo.processInfo.environment["SPINLAB_ENABLE_SEPARATED_OVERRIDES_IN_TESTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    private func bundleRuleCandidateURLs() -> [URL] {
        // SwiftPM `.process("config")` flattens files into the module's resource
        // bundle root, so look up via `Bundle.module` without a `subdirectory:`.
        var candidates: [URL] = []
        if let direct = Bundle.module.url(forResource: "filename_rules", withExtension: "json") {
            candidates.append(direct)
        }
        // Dev fallback: `swift test` invoked from the project root.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(cwd.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json"))

        var seen: Set<String> = []
        return candidates.filter { url in
            let standardized = url.standardizedFileURL.path
            guard !seen.contains(standardized) else {
                return false
            }
            seen.insert(standardized)
            return true
        }
    }
}
