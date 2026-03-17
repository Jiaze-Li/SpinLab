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

        if let appSupportURL = applicationSupportRuleURL(),
           let data = try? Data(contentsOf: appSupportURL) {
            let decoded = decodeRuleSet(from: data, source: appSupportURL.path, warnings: &warnings)
            print("[RuleLoader] loaded rules from: \(appSupportURL.path)")
            print("[RuleLoader] sampleId patterns: \(decoded.sampleId.patterns)")
            return LoadResult(ruleSet: decoded, warnings: warnings)
        }

        if let bundleURL = Bundle.main.url(forResource: "filename_rules", withExtension: "json", subdirectory: "config"),
           let data = try? Data(contentsOf: bundleURL) {
            let decoded = decodeRuleSet(from: data, source: bundleURL.path, warnings: &warnings)
            print("[RuleLoader] loaded rules from: \(bundleURL.path)")
            print("[RuleLoader] sampleId patterns: \(decoded.sampleId.patterns)")
            return LoadResult(ruleSet: decoded, warnings: warnings)
        }

        warnings.append("Filename rules not found in Application Support or bundle.")
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

    private func decodeRuleSet(from data: Data, source: String, warnings: inout [String]) -> FilenameRuleSet {
        do {
            let decoder = JSONDecoder()
            var ruleSet = try decoder.decode(FilenameRuleSet.self, from: data)
            let compileWarnings = ruleSet.compile()
            if !compileWarnings.isEmpty {
                warnings.append(contentsOf: compileWarnings.map { "\(source): \($0)" })
            }
            ruleSet.loadWarnings = warnings
            return ruleSet
        } catch {
            warnings.append("Failed to decode filename rules from \(source): \(error)")
            var fallback = FilenameRuleSet.fallback()
            fallback.loadWarnings = warnings
            return fallback
        }
    }

    private func applicationSupportRuleURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appFolder = Bundle.main.bundleIdentifier ?? "SpinLab"
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("filename_rules.json")
    }
}
