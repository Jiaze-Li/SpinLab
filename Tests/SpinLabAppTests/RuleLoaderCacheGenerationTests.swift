import Foundation
import Testing
@testable import SpinLabApp

/// Deterministic regression tests for the loadCached/configure interleaving: a load that
/// started before a Rule Book switch must not publish its (stale) result into the cache.
@Suite("RuleLoader cache generation", .serialized, .rulesGlobalState)
struct RuleLoaderCacheGenerationTests {

    @Test("a load captured before configure() cannot overwrite the new configuration's cache")
    func staleLoadIsNotPublishedAfterReconfigure() throws {
        try withTempRulesDirectory(prefix: "SL-gen-old") { _, oldPaths in
            try withTempRulesDirectory(prefix: "SL-gen-new") { _, newPaths in
                try writeMinimalRulesBook(to: oldPaths, batchPrefix: "OLD")
                try writeMinimalRulesBook(to: newPaths, batchPrefix: "NEW")

                RuleLoader.configure(bookPaths: oldPaths, internalPaths: AppInternalPaths())
                let staleGeneration = RuleLoader.currentConfigurationGeneration
                let staleResult = RuleLoader.shared.load()

                // Rule Book switch happens while the "old" load is still in flight.
                RuleLoader.configure(bookPaths: newPaths, internalPaths: AppInternalPaths())
                #expect(RuleLoader.storeCached(staleResult, ifGeneration: staleGeneration) == false)

                let current = RuleLoader.shared.loadCached()
                #expect(current.metadata.sourcePath == newPaths.importFiltersURL.path)
            }
        }
    }

    @Test("a stale not-configured result is not sticky after a Rule Book is configured")
    func staleUnconfiguredResultDoesNotSurviveConfigure() throws {
        try withTempRulesDirectory(prefix: "SL-gen-book") { _, paths in
            try writeMinimalRulesBook(to: paths)

            RuleLoader.configure(bookPaths: nil, internalPaths: AppInternalPaths())
            let staleGeneration = RuleLoader.currentConfigurationGeneration
            let unconfigured = RuleLoader.shared.load()
            #expect(unconfigured.metadata.sourcePath == "not-configured")

            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
            #expect(RuleLoader.storeCached(unconfigured, ifGeneration: staleGeneration) == false)

            let current = RuleLoader.shared.loadCached()
            #expect(current.metadata.sourcePath == paths.importFiltersURL.path)
            #expect(!current.ruleSet.importRules!.supportedFileExtensions.isEmpty)
        }
    }

    @Test("a load that started under the current configuration is published")
    func currentGenerationLoadIsPublished() throws {
        try withTempRulesDirectory(prefix: "SL-gen-ok") { _, paths in
            try writeMinimalRulesBook(to: paths)
            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
            let generation = RuleLoader.currentConfigurationGeneration
            let result = RuleLoader.shared.load()
            #expect(RuleLoader.storeCached(result, ifGeneration: generation))
            #expect(RuleLoader.shared.loadCached().metadata.contentHash == result.metadata.contentHash)
        }
    }
}
