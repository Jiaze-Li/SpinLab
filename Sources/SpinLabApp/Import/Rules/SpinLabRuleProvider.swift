import Foundation

protocol SpinLabRuleProviding {
    func loadResult() -> RuleLoader.LoadResult
    func reloadResult() -> RuleLoader.LoadResult
    func ruleSet() -> FilenameRuleSet
    func registryRules() -> FilenameRuleSet.RegistryRules?
    func importRules() -> FilenameRuleSet.ImportRules
    func substrateConfig() -> FilenameRuleSet.SubstrateConfig?
}

struct SpinLabRuleProvider: SpinLabRuleProviding {
    static let shared = SpinLabRuleProvider()

    private let loader: RuleLoader
    private let fallback: FilenameRuleSet

    init(loader: RuleLoader = .shared) {
        self.loader = loader
        fallback = FilenameRuleSet.fallback()
    }

    func loadResult() -> RuleLoader.LoadResult {
        loader.loadCached()
    }

    func reloadResult() -> RuleLoader.LoadResult {
        loader.reloadCached()
    }

    func ruleSet() -> FilenameRuleSet {
        loadResult().ruleSet
    }

    func registryRules() -> FilenameRuleSet.RegistryRules? {
        ruleSet().registry
    }

    func importRules() -> FilenameRuleSet.ImportRules {
        ruleSet().importRules ?? fallback.importRules!
    }

    func substrateConfig() -> FilenameRuleSet.SubstrateConfig? {
        ruleSet().substrateConfig
    }
}

struct InlineRuleProvider: SpinLabRuleProviding {
    let cachedLoadResult: RuleLoader.LoadResult

    init(loadResult: RuleLoader.LoadResult) {
        cachedLoadResult = loadResult
    }

    func loadResult() -> RuleLoader.LoadResult {
        cachedLoadResult
    }

    func reloadResult() -> RuleLoader.LoadResult {
        cachedLoadResult
    }

    func ruleSet() -> FilenameRuleSet {
        cachedLoadResult.ruleSet
    }

    func registryRules() -> FilenameRuleSet.RegistryRules? {
        cachedLoadResult.ruleSet.registry
    }

    func importRules() -> FilenameRuleSet.ImportRules {
        cachedLoadResult.ruleSet.importRules ?? FilenameRuleSet.fallback().importRules!
    }

    func substrateConfig() -> FilenameRuleSet.SubstrateConfig? {
        cachedLoadResult.ruleSet.substrateConfig
    }
}
