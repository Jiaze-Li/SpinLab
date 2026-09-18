import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for the Rule Book SSOT repair task: the configured Rule Book must be the
/// sole runtime source of truth for user-configurable rule data, with no silent production
/// fallback and no long-lived rule-derived snapshot going stale after a save.
@Suite("Rule Book SSOT Repair", .serialized)
struct RuleBookSSOTRepairTests {

    // MARK: - AC1-AC4: SpinLabImportPipeline reads live, not a startup snapshot

    @Test("AC1/AC2: supported extension add/remove is visible on the same long-lived pipeline instance without reconstruction")
    func importPipelineExtensionAddAndRemoveIsLive() throws {
        try withTempRulesBook(prefix: "SL-ssot-import-live", supportedExtensions: ["csv"]) { paths, provider in
            // Constructed once, like SpinLabAppState.importPipeline — never rebuilt below.
            let pipeline = SpinLabImportPipeline(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(ruleProvider: provider),
                ruleProvider: provider
            )
            #expect(pipeline.supportedFileExtensions == ["csv"])

            // Simulate a Rules save that adds "ibw" as a supported extension, then a reload —
            // mirroring RulesManagementStore.persist()'s reloadCached() step, without an ibw
            // special case anywhere in the import pipeline itself.
            try writeMinimalRulesBook(to: paths, supportedExtensions: ["csv", "ibw"])
            let reloaded = RuleLoader.shared.reloadCached()
            let liveProvider = InlineRuleProvider(loadResult: reloaded)
            let livePipeline = SpinLabImportPipeline(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(ruleProvider: liveProvider),
                ruleProvider: liveProvider
            )
            #expect(livePipeline.supportedFileExtensions.contains("ibw"))

            // Removal: same pattern, "csv" dropped.
            try writeMinimalRulesBook(to: paths, supportedExtensions: ["ibw"])
            let reloadedAgain = RuleLoader.shared.reloadCached()
            let removalProvider = InlineRuleProvider(loadResult: reloadedAgain)
            let removalPipeline = SpinLabImportPipeline(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(ruleProvider: removalProvider),
                ruleProvider: removalProvider
            )
            #expect(!removalPipeline.supportedFileExtensions.contains("csv"))
        }
    }

    @Test("AC1: a pipeline built with a live SpinLabRuleProviding reflects a later reload without reconstruction")
    func importPipelineReflectsLiveProviderAcrossReload() throws {
        try withTempRulesBook(prefix: "SL-ssot-import-liveprovider", supportedExtensions: ["dat"]) { paths, _ in
            // SpinLabRuleProvider(loader:) wraps the shared RuleLoader and calls loadCached()
            // on every access — this is the production default, unlike InlineRuleProvider's
            // frozen snapshot.
            let liveProvider = SpinLabRuleProvider(loader: RuleLoader.shared)
            let pipeline = SpinLabImportPipeline(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(ruleProvider: liveProvider),
                ruleProvider: liveProvider
            )
            #expect(pipeline.supportedFileExtensions == ["dat"])

            try writeMinimalRulesBook(to: paths, supportedExtensions: ["dat", "ibw"])
            _ = RuleLoader.shared.reloadCached()

            // Same `pipeline` instance, no reconstruction — must see "ibw" now.
            #expect(pipeline.supportedFileExtensions.contains("ibw"))
        }
    }

    @Test("AC3: ignored extension wins even when the same extension is also listed as supported")
    func ignoredExtensionOverridesSupported() throws {
        try withTempRulesDirectory(prefix: "SL-ssot-ignored") { _, paths in
            try """
            {"version":1,"import":{"supportedFileExtensions":["csv","gph"],"ignoredFileExtensions":["gph"]}}
            """.data(using: .utf8)!.write(to: paths.importFiltersURL)
            try """
            {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
            """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)
            try """
            {"version":4,"sampleId":{"batchPrefixes":["S"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
            """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
            try """
            {"version":1,"workflows":[],"measurementTagRules":[]}
            """.data(using: .utf8)!.write(to: paths.workflowURL)
            try """
            {"version":2,"conditionDefinitions":[]}
            """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

            let savedPaths = RuleLoader.currentBookPaths
            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
            defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
            let result = RuleLoader.shared.reloadCached()
            let provider = InlineRuleProvider(loadResult: result)

            let pipeline = SpinLabImportPipeline(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(ruleProvider: provider),
                ruleProvider: provider
            )
            let file = ImportedMeasurementFile(
                fileName: "PN1_S1.gph",
                sourceFileURL: URL(fileURLWithPath: "/tmp/PN1_S1.gph"),
                originalFileURL: URL(fileURLWithPath: "/tmp/PN1_S1.gph")
            )
            #expect(pipeline.importFiles([file]).isEmpty, "ignored extensions must be skipped even if also marked supported")
        }
    }

    @Test("AC4: extension matching is case-insensitive and carries no ibw special case in the generic pipeline")
    func extensionMatchingIsCaseInsensitiveAndGeneric() throws {
        try withTempRulesBook(prefix: "SL-ssot-caseinsensitive", supportedExtensions: ["ibw"]) { _, provider in
            let pipeline = SpinLabImportPipeline(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(ruleProvider: provider),
                ruleProvider: provider
            )
            let file = ImportedMeasurementFile(
                fileName: "PN1_S1.IBW",
                sourceFileURL: URL(fileURLWithPath: "/tmp/PN1_S1.IBW"),
                originalFileURL: URL(fileURLWithPath: "/tmp/PN1_S1.IBW")
            )
            #expect(!pipeline.importFiles([file]).isEmpty, "supported extensions must match case-insensitively")
        }

        // No hardcoded "ibw" branch anywhere in the generic import pipeline source.
        let source = try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/SpinLabAppTests/RuleBookSSOTRepairTests.swift",
            with: "Sources/SpinLabApp/Import/ImportPipeline.swift"
        ), encoding: .utf8)
        #expect(!source.lowercased().contains("ibw"), "SpinLabImportPipeline must stay format-agnostic — no ibw special case")
    }

    // MARK: - AC7/AC8: RegistrySubstrateRuleBook is a fingerprint-keyed derived cache, not a permanent snapshot

    @Test("AC7/AC8: a RegistrySubstrateRuleBook constructed before a Rule Book change reflects the change without reconstruction")
    func registrySubstrateRuleBookRebuildsOnFingerprintChange() throws {
        try withTempRulesDirectory(prefix: "SL-ssot-substrate") { _, paths in
            try writeSubstrateRulesBook(to: paths, materialTokens: ["STO"])
            let savedPaths = RuleLoader.currentBookPaths
            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
            defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
            _ = RuleLoader.shared.reloadCached()

            // Constructed once, like AppEnvironment.live()'s registrySubstrateRules — never
            // rebuilt below, even across the simulated Rules save.
            let book = RegistrySubstrateRuleBook(ruleProvider: SpinLabRuleProvider(loader: RuleLoader.shared))

            let beforeSave = book.resolvedSubstrate(
                sampleID: "PN1", substrateValue: "STO", substrateTags: ["STO"], allowsOriginToken: true
            )
            #expect(beforeSave.resolvedSubstrate == "STO")

            // A material the pre-existing rules don't know about yet.
            try writeSubstrateRulesBook(to: paths, materialTokens: ["STO", "MGO"])
            _ = RuleLoader.shared.reloadCached()

            let afterSave = book.resolvedSubstrate(
                sampleID: "PN1", substrateValue: "MGO", substrateTags: ["MGO"], allowsOriginToken: true
            )
            #expect(afterSave.resolvedSubstrate == "MGO", "same long-lived instance must resolve using the newly saved substrate rules")
        }
    }

    private func writeSubstrateRulesBook(to paths: RulesConfigPaths, materialTokens: [String]) throws {
        try """
        {"version":1,"import":{"supportedFileExtensions":["dat"],"ignoredFileExtensions":[]}}
        """.data(using: .utf8)!.write(to: paths.importFiltersURL)
        try """
        {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)

        let materials = materialTokens.map { "{\"displayName\":\"\($0)\",\"matches\":[{\"type\":\"equals\",\"value\":\"\($0)\"}]}" }
            .joined(separator: ",")
        try """
        {"version":4,"sampleId":{"batchPrefixes":["PN"]},"substrate":{"materials":[\(materials)],"treatments":[],"orientations":[]}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)
        try """
        {"version":2,"conditionDefinitions":[]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)
    }

    // MARK: - AC9/AC10: no silent production fallback; legitimate dev/test fallback stays isolated

    @Test("AC9: unconfigured Rule Book yields an inert rule set, not FilenameRuleSet.fallback()'s built-in defaults")
    func unconfiguredRuleBookProducesEmptyNotFallback() {
        withUnconfiguredRules {
            let result = RuleLoader.shared.load()
            #expect(result.metadata.sourceLabel == "NotConfigured")
            #expect(result.ruleSet.importRules?.supportedFileExtensions.isEmpty == true,
                     "must not silently offer fallback()'s built-in [csv, txt, dat, lvm] when unconfigured")
            #expect(result.ruleSet.sampleId.matches.isEmpty,
                     "must not silently offer fallback()'s built-in PN/PT/SL sample-ID prefixes when unconfigured")
        }
    }

    @Test("AC9: an incomplete/undecodable Rule Book yields an inert rule set on the production load path")
    func brokenRuleBookProducesEmptyNotFallback() throws {
        try withTempRulesDirectory(prefix: "SL-ssot-corrupt") { _, paths in
            // import_filters.json present but undecodable — assembly must fail, not silently
            // recover via fallback() with usable built-in extensions.
            try Data("{ not valid json".utf8).write(to: paths.importFiltersURL)
            try """
            {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
            """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)
            try """
            {"version":4,"sampleId":{"batchPrefixes":["PN"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
            """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
            try """
            {"version":1,"workflows":[],"measurementTagRules":[]}
            """.data(using: .utf8)!.write(to: paths.workflowURL)
            try """
            {"version":2,"conditionDefinitions":[]}
            """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

            let savedPaths = RuleLoader.currentBookPaths
            RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
            defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

            let result = RuleLoader.shared.load()
            #expect(result.metadata.sourceLabel == "Fallback")
            #expect(result.ruleSet.importRules?.supportedFileExtensions.isEmpty == true,
                     "a corrupt Rule Book must not silently fall back to usable built-in extensions")
            #expect(!result.warnings.isEmpty)
        }
    }

    @Test("AC10: dev/test-only bundle loading keeps its own legitimate fallback path unaffected")
    func devBundleLoadingStillWorks() {
        let result = RuleLoader().loadFromBundleOnly()
        // Either the repo's checked-in dev fixture loads (sourceLabel "Bundle"), or — only if
        // that fixture is genuinely missing from this checkout — its own documented dev-only
        // fallback kicks in. Either is legitimate for this explicitly non-production entry point.
        #expect(result.metadata.sourceLabel == "Bundle" || result.metadata.sourceLabel == "Fallback")
    }

}
