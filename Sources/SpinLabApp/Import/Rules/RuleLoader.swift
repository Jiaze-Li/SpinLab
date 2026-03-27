import Foundation
import CryptoKit

struct RuleLoader {
    static let shared = RuleLoader()
    private static var cached: LoadResult?
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

        let appSupportURL = applicationSupportRuleURL()
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
        if let cached = RuleLoader.cached {
            if shouldReloadCached(cached) {
                let reloaded = load()
                RuleLoader.cached = reloaded
                return reloaded
            }
            return cached
        }
        let loaded = load()
        RuleLoader.cached = loaded
        return loaded
    }

    func reloadCached() -> LoadResult {
        let loaded = load()
        RuleLoader.cached = loaded
        return loaded
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

        let latestHash = hashHex(for: data)
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
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "\(sourceLabel) compile warning: \($0)" })
            }
            ruleSet.loadWarnings = warnings
            let metadata = RuleMetadata(
                version: ruleSet.version,
                sourceLabel: sourceLabel,
                sourcePath: url.path,
                contentHash: hashHex(for: data),
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

    private func applicationSupportRuleURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let appFolder = Bundle.main.bundleIdentifier ?? "com.spinlab.app"
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("filename_rules.json")
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
