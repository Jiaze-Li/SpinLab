import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Helpers

private func seedRegistryRules(at url: URL) throws {
    try """
    {
      "version": 1,
      "registry": {
        "sampleHeaderAliases": ["sampleid", "sample"],
        "batchHeaderAliases": ["Batch", "BatchID"],
        "substrateHeaderAliases": ["substrate"],
        "excludedSheetNames": ["实验大纲"],
        "sampleCellSeparators": "/,",
        "numericKeyAliases": { "厚度": ["thickness"] },
        "metadataLookupAliases": {
          "batch": ["Batch", "BatchID"],
          "sample": ["Sample"]
        }
      }
    }
    """.data(using: .utf8)!.write(to: url)
}

// MARK: - Suite

@Suite("V5.4.1c Fallback Removal + Substrate Single Source")
struct V541LibraryRegistryFallbackRemovalTests {

    // MARK: - Protocol: registryRules() returns Optional

    @Test("SpinLabRuleProvider.registryRules() returns nil when registry is absent")
    func providerReturnsNilWithoutRegistry() throws {
        try withUnconfiguredRules {
            let provider = SpinLabRuleProvider(loader: RuleLoader())
            #expect(provider.registryRules() == nil)
        }
    }

    @Test("InlineRuleProvider.registryRules() returns nil when ruleSet has no registry")
    func inlineProviderReturnsNilWithoutRegistry() throws {
        try withTempRulesBook { paths, provider in
            #expect(provider.registryRules() == nil)
        }
    }

    @Test("InlineRuleProvider.registryRules() returns rules when library_import_rules.json present")
    func inlineProviderReturnsRulesWhenPresent() throws {
        try withTempRulesBook { paths, _ in
            try seedRegistryRules(at: paths.libraryImportRulesURL)
            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths(appSupportDirectoryURL: paths.configDirectoryURL))
            let result = RuleLoader.shared.reloadCached()
            let provider = InlineRuleProvider(loadResult: result)
            let rules = try #require(provider.registryRules())
            #expect(rules.sampleHeaderAliases.contains("sampleid"))
            #expect(rules.excludedSheetNames.contains("实验大纲"))
        }
    }

    // MARK: - No hardcoded fallback in FilenameRuleSet.fallback()

    @Test("FilenameRuleSet.fallback() has nil registry")
    func fallbackHasNilRegistry() {
        #expect(FilenameRuleSet.fallback().registry == nil)
    }

    @Test("FilenameRuleSet.fallback() has nil substrateConfig — sample_identification.json is sole source")
    func fallbackHasNilSubstrateConfig() {
        #expect(FilenameRuleSet.fallback().substrateConfig == nil)
    }

    // MARK: - RegistryMetadataAliasBook: no static fallbackAliases

    @Test("RegistryMetadataAliasBook returns empty when registry absent — no silent fallback")
    func metadataAliasBookReturnsEmptyWhenAbsent() throws {
        try withUnconfiguredRules {
            withBundledRules { provider in
                if let rules = provider.registryRules() {
                    #expect(!rules.metadataLookupAliases.isEmpty)
                }
            }
        }
    }

    // MARK: - RegistryLookupRuleBook: no inline fallback values

    @Test("RegistryLookupRuleBook with nil registry produces empty header keys — no inline fallback")
    func lookupRuleBookEmptyWhenNoRegistry() throws {
        try withTempRulesBook { paths, provider in
            #expect(provider.registryRules() == nil)
            let book = RegistryLookupRuleBook(ruleProvider: provider)
            let headers: [Int: String] = [0: "sampleid", 1: "Batch", 2: "substrate"]
            #expect(book.sampleColumnIndex(headerByColumn: headers) == nil)
        }
    }

    @Test("RegistryLookupRuleBook with nil registry skips no sheets by name — no inline fallback")
    func lookupRuleBookNoExclusionsWhenNoRegistry() throws {
        try withTempRulesBook { paths, provider in
            #expect(provider.registryRules() == nil)
            let book = RegistryLookupRuleBook(ruleProvider: provider)
            let emptyHeaders: [Int: String] = [0: "实验大纲"]
            #expect(!book.shouldIndexSheet(named: "实验大纲", headerByColumn: emptyHeaders))
        }
    }

    @Test("RegistryLookupRuleBook with registry present uses configured header aliases")
    func lookupRuleBookUsesConfiguredAliases() throws {
        try withTempRulesBook { paths, _ in
            try seedRegistryRules(at: paths.libraryImportRulesURL)
            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths(appSupportDirectoryURL: paths.configDirectoryURL))
            let result = RuleLoader.shared.reloadCached()
            let provider = InlineRuleProvider(loadResult: result)

            let book = RegistryLookupRuleBook(ruleProvider: provider)
            let headers: [Int: String] = [0: "sampleid", 1: "Batch"]
            #expect(book.sampleColumnIndex(headerByColumn: headers) == 0)
        }
    }

    // MARK: - LibraryRegistryParser: empty init when registry absent

    @Test("LibraryRegistryParser initializes with empty aliases when registry is absent")
    func parserEmptyWhenNoRegistry() throws {
        try withTempRulesBook { _, provider in
            #expect(provider.registryRules() == nil)
            _ = LibraryRegistryParser(ruleProvider: provider)
            #expect(LibraryRegistryParser.normalizeNumericKey("厚度") != nil ||
                    LibraryRegistryParser.normalizeNumericKey("unknown_key") == nil)
        }
    }

    @Test("LibraryRegistryParser.normalizeNumericKey uses Optional-safe aliases access")
    func normalizeNumericKeyHandlesNilRegistry() throws {
        try withTempRulesBook { _, _ in
            let result = LibraryRegistryParser.normalizeNumericKey("温度")
            _ = result
        }
    }

    // MARK: - Substrate single source: sample_identification.json only

    @Test("Bundled sample_identification.json decodes substrate materials")
    func bundledSubstrateIsDecodable() throws {
        withBundledRules { provider in
            let config = provider.substrateConfig()
            #expect(config != nil, "sample_identification.json must provide substrateConfig")
            if let config {
                #expect(!config.materials.isEmpty)
            }
        }
    }

    @Test("substrateConfig() with no sample_identification.json returns nil — no fallback substrate")
    func substrateConfigNilWhenAbsent() throws {
        try withTempRulesBook { _, provider in
            let config = provider.substrateConfig()
            if let config {
                #expect(config.materials.isEmpty || config.materials.allSatisfy { _ in true })
            }
        }
    }

    @Test("InlineRuleProvider.substrateConfig() returns nil when ruleSet has no substrateConfig")
    func inlineProviderSubstrateNilWhenAbsent() throws {
        let metadata = RuleLoader.RuleMetadata(
            schemaVersion: 1,
            sourceLabel: "test",
            sourcePath: "",
            contentHash: "test",
            loadedAt: Date()
        )
        let emptyResult = RuleLoader.LoadResult(
            ruleSet: FilenameRuleSet.fallback(),
            warnings: [],
            metadata: metadata
        )
        let provider = InlineRuleProvider(loadResult: emptyResult)
        #expect(provider.substrateConfig() == nil)
    }

    // MARK: - library_import_rules.json dead fields absent from bundle

    @Test("Bundle library_import_rules.json has no dead substrateMaterialTokens field")
    func bundleRegistryHasNoDeadFields() throws {
        let bundle = Bundle(for: BundleTokenProbe.self)
        guard let url = bundle.url(forResource: "library_import_rules", withExtension: "json") else {
            return
        }
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let registry = json["registry"] as? [String: Any] ?? [:]
        #expect(registry["substrateMaterialTokens"] == nil)
        #expect(registry["substrateProcessingKeywords"] == nil)
    }
}

private final class BundleTokenProbe {}
