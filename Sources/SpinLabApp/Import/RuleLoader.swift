import Foundation

struct RuleLoader {
    static let shared = RuleLoader()
    private static var cached: LoadResult?

    struct LoadResult {
        var ruleSet: FilenameRuleSet
        var warnings: [String]
    }

    func load() -> LoadResult {
        var warnings: [String] = []

        let appSupportURL = applicationSupportRuleURL()
        print("[RuleLoader] trying source=ApplicationSupport path=\(appSupportURL.path)")
        if let loaded = tryLoadRuleSet(from: appSupportURL, sourceLabel: "ApplicationSupport", warnings: &warnings) {
            return loaded
        }

        for bundleURL in bundleRuleCandidateURLs() {
            print("[RuleLoader] trying source=Bundle path=\(bundleURL.path)")
            if let loaded = tryLoadRuleSet(from: bundleURL, sourceLabel: "Bundle", warnings: &warnings) {
                return loaded
            }
        }

        warnings.append("Filename rules could not be loaded from Application Support or bundle candidates.")
        print("[RuleLoader] failed to load rules. reasons=\(warnings.joined(separator: " | "))")
        var fallback = FilenameRuleSet.fallback()
        fallback.loadWarnings = warnings
        return LoadResult(ruleSet: fallback, warnings: warnings)
    }

    func loadCached() -> LoadResult {
        if let cached = RuleLoader.cached {
            return cached
        }
        let loaded = load()
        RuleLoader.cached = loaded
        return loaded
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
            print("[RuleLoader] failed source=\(sourceLabel) path=\(url.path) reason=read_failed \(reason)")
            return nil
        }

        do {
            var ruleSet = try decodeRuleSet(from: data, source: "\(sourceLabel):\(url.path)")
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "\(sourceLabel) compile warning: \($0)" })
            }
            ruleSet.loadWarnings = warnings
            print("[RuleLoader] loaded source=\(sourceLabel) path=\(url.path)")
            print("[RuleLoader] sampleId patterns: \(ruleSet.sampleId.patterns)")
            return LoadResult(ruleSet: ruleSet, warnings: warnings)
        } catch {
            let reason = error.localizedDescription
            warnings.append("\(sourceLabel) decode failed at \(url.path): \(reason)")
            print("[RuleLoader] failed source=\(sourceLabel) path=\(url.path) reason=decode_failed \(reason)")
            return nil
        }
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
