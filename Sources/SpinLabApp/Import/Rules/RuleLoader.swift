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
        var loadedAt: Date

        var fingerprint: String {
            "v\(version):\(contentHash)"
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
        if let loaded = tryLoadRuleSet(from: appSupportURL, sourceLabel: "ApplicationSupport", warnings: &warnings) {
            return loaded
        }

        for bundleURL in bundleRuleCandidateURLs() {
            logger.info(.import, "Rule source probe", metadata: [
                "source": "Bundle",
                "path": bundleURL.path
            ])
            if let loaded = tryLoadRuleSet(from: bundleURL, sourceLabel: "Bundle", warnings: &warnings) {
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

    private func tryLoadRuleSet(from url: URL, sourceLabel: String, warnings: inout [String]) -> LoadResult? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            warnings.append("\(sourceLabel) file missing at \(url.path)")
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
            warnings.append(contentsOf: applySeparatedOverrides(ruleSet: &ruleSet))
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
                loadedAt: Date()
            )
            logger.info(.import, "Rule source loaded", metadata: [
                "source": sourceLabel,
                "path": url.path,
                "sampleIdPatternCount": "\(ruleSet.sampleId.patterns.count)",
                "ruleVersion": "\(ruleSet.version)",
                "ruleFingerprint": metadata.fingerprint
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

    private func applySeparatedOverrides(ruleSet: inout FilenameRuleSet) -> [String] {
        var warnings: [String] = []
        if RulesConfigPaths.isRunningTests(), !shouldEnableSeparatedOverridesDuringTests() {
            return warnings
        }

        let sampleIDURL = rulesConfigPaths().sampleIDRulesURL
        if FileManager.default.fileExists(atPath: sampleIDURL.path) {
            do {
                let data = try Data(contentsOf: sampleIDURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let patterns = json["patterns"] as? [String] {
                    let normalized = patterns
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !normalized.isEmpty {
                        ruleSet.sampleId = .init(patterns: normalized)
                    } else {
                        warnings.append("sample_id_rules.json contains no valid patterns; keeping existing sampleId rules.")
                    }
                } else {
                    warnings.append("sample_id_rules.json is invalid; ignoring sample-id override.")
                }
            } catch {
                warnings.append("sample_id_rules.json read failed: \(error.localizedDescription)")
            }
        }

        let workflowURL = rulesConfigPaths().workflowMatchRulesURL
        if FileManager.default.fileExists(atPath: workflowURL.path) {
            do {
                let data = try Data(contentsOf: workflowURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rules = json["rules"] as? [[String: Any]] {
                    let parsed: [FilenameRuleSet.MapRule] = rules.compactMap { rule in
                        guard let scopeRaw = rule["scope"] as? String,
                              let typeRaw = rule["type"] as? String,
                              let workflowID = rule["workflowID"] as? String,
                              let scope = FilenameRuleSet.MatchScope(rawValue: scopeRaw),
                              let type = FilenameRuleSet.MatchType(rawValue: typeRaw) else {
                            return nil
                        }
                        let values = ((rule["matchValues"] as? [String]) ?? [])
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        guard !values.isEmpty else { return nil }

                        let match: FilenameRuleSet.MatchSpec
                        switch type {
                        case .equalsAny, .containsAny, .equalsOrContainsAny:
                            match = .init(scope: scope, type: type, value: nil, values: values)
                        default:
                            match = .init(scope: scope, type: type, value: values.first, values: nil)
                        }
                        let normalizedWorkflowID = workflowID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !normalizedWorkflowID.isEmpty else { return nil }
                        return .init(
                            match: match,
                            value: normalizedWorkflowID
                        )
                    }
                    if parsed.isEmpty {
                        warnings.append("workflow_match_rules.json contains no valid rules; keeping existing workflow rules.")
                    } else {
                        ruleSet.measurementNameRules = parsed
                    }
                } else {
                    warnings.append("workflow_match_rules.json is invalid; ignoring workflow override.")
                }
            } catch {
                warnings.append("workflow_match_rules.json read failed: \(error.localizedDescription)")
            }
        }

        let conditionsURL = rulesConfigPaths().conditionsRulesURL
        if FileManager.default.fileExists(atPath: conditionsURL.path) {
            do {
                let data = try Data(contentsOf: conditionsURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let hasExtraConditions = json["extraConditions"] as? [String: Any] != nil
                    let hasTokenMapRules = json["tokenMapRules"] as? [String: Any] != nil
                    if !hasExtraConditions && !hasTokenMapRules {
                        warnings.append("conditions_rules.json contains no supported keys; keeping existing condition rules.")
                    }

                    if let extraConditions = json["extraConditions"] as? [String: Any] {
                        for (rawKey, value) in extraConditions {
                            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty else { continue }
                            if value is NSNull {
                                ruleSet.conditions.extraConditions.removeValue(forKey: key)
                                continue
                            }
                            guard let pattern = value as? String else { continue }
                            let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !normalizedPattern.isEmpty else { continue }
                            ruleSet.conditions.extraConditions[key] = normalizedPattern
                        }
                    }

                    if let tokenMapRules = json["tokenMapRules"] as? [String: Any] {
                        for (rawKey, rawRules) in tokenMapRules {
                            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty else { continue }
                            guard let mapped = rawRules as? [[String: Any]] else { continue }

                            let parsedRules: [FilenameRuleSet.MapRule] = mapped.compactMap { rawRule in
                                guard let matchTypeRaw = rawRule["matchType"] as? String,
                                      let matchType = TokenMatchType(rawValue: matchTypeRaw),
                                      let pattern = (rawRule["pattern"] as? String)?
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                      !pattern.isEmpty else {
                                    return nil
                                }
                                let value = (rawRule["value"] as? String)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .nilIfEmpty ?? "$MATCH"

                                let matchSpec: FilenameRuleSet.MatchSpec
                                switch matchType {
                                case .equals:
                                    matchSpec = .init(scope: .tokens, type: .equals, value: pattern, values: nil)
                                case .regex:
                                    matchSpec = .init(
                                        scope: .tokens,
                                        type: .regex,
                                        value: RulePatternCodec.regexPattern(from: pattern),
                                        values: nil
                                    )
                                }
                                return .init(match: matchSpec, value: value)
                            }

                            // Merge semantics: key provided by override always wins.
                            // Empty array means explicit clear.
                            ruleSet.conditions.tokenMapRules[key] = parsedRules
                        }
                    }
                } else {
                    warnings.append("conditions_rules.json is invalid; ignoring conditions override.")
                }
            } catch {
                warnings.append("conditions_rules.json read failed: \(error.localizedDescription)")
            }
        }

        let substrateURL = rulesConfigPaths().substrateRulesURL
        if FileManager.default.fileExists(atPath: substrateURL.path) {
            do {
                let data = try Data(contentsOf: substrateURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let hasTagRules = json["substrateTagRules"] != nil
                    let hasSharedSubstrate = json["sharedSubstrate"] != nil
                    if !hasTagRules && !hasSharedSubstrate {
                        warnings.append("substrate_rules.json contains no supported keys; keeping existing substrate rules.")
                    }

                    if let rawTagRules = json["substrateTagRules"] {
                        let fragmentData = try JSONSerialization.data(withJSONObject: rawTagRules)
                        let decoded = try JSONDecoder().decode([FilenameRuleSet.MapRule].self, from: fragmentData)
                        if decoded.isEmpty {
                            warnings.append("substrate_rules.json substrateTagRules is empty; keeping existing substrateTagRules.")
                        } else {
                            ruleSet.substrateTagRules = decoded
                        }
                    }

                    if let rawSharedSubstrate = json["sharedSubstrate"] {
                        let fragmentData = try JSONSerialization.data(withJSONObject: rawSharedSubstrate)
                        let decoded = try JSONDecoder().decode(FilenameRuleSet.SharedSubstrateRules.self, from: fragmentData)
                        ruleSet.sharedSubstrate = decoded
                    }
                } else {
                    warnings.append("substrate_rules.json is invalid; ignoring substrate override.")
                }
            } catch {
                warnings.append("substrate_rules.json read failed: \(error.localizedDescription)")
            }
        }

        let measurementTagURL = rulesConfigPaths().measurementTagRulesURL
        if FileManager.default.fileExists(atPath: measurementTagURL.path) {
            do {
                let data = try Data(contentsOf: measurementTagURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let rawRules = json["rules"] {
                        let fragmentData = try JSONSerialization.data(withJSONObject: rawRules)
                        let decoded = try JSONDecoder().decode([FilenameRuleSet.MapRule].self, from: fragmentData)
                        if decoded.isEmpty {
                            warnings.append("measurement_tag_rules.json contains empty rules; keeping existing measurementTagRules.")
                        } else {
                            ruleSet.measurementTagRules = decoded
                        }
                    } else {
                        warnings.append("measurement_tag_rules.json has no rules key; keeping existing measurementTagRules.")
                    }
                } else {
                    warnings.append("measurement_tag_rules.json is invalid; ignoring measurement-tag override.")
                }
            } catch {
                warnings.append("measurement_tag_rules.json read failed: \(error.localizedDescription)")
            }
        }

        return warnings
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
        var candidates: [URL] = []

        if let direct = Bundle.main.url(forResource: "filename_rules", withExtension: "json", subdirectory: "config") {
            candidates.append(direct)
        }

        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("config/filename_rules.json"))
            candidates.append(resources.appendingPathComponent("SpinLab_SpinLabApp.bundle/filename_rules.json"))
        }

        let bundleRoot = Bundle.main.bundleURL
        candidates.append(bundleRoot.appendingPathComponent("Contents/Resources/config/filename_rules.json"))
        candidates.append(bundleRoot.appendingPathComponent("Contents/Resources/SpinLab_SpinLabApp.bundle/filename_rules.json"))
        candidates.append(bundleRoot.appendingPathComponent("SpinLab_SpinLabApp.bundle/filename_rules.json"))

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDir.appendingPathComponent("SpinLab_SpinLabApp.bundle/filename_rules.json"))
        }

        // SwiftPM test fallback: running from project root where rules live in source tree.
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
