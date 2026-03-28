import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.5 Rules Config Contract")
struct V225RulesConfigContractTests {
    @Test("rules config decodes and compiles without warnings")
    func rulesConfigDecodesAndCompilesWithoutWarnings() throws {
        var ruleSet = try loadRuleSet()
        let compileWarnings = ruleSet.compile()

        #expect(compileWarnings.isEmpty)
    }

    @Test("rules config contains required aliases and extension lists")
    func rulesConfigContainsRequiredAliasesAndExtensions() throws {
        let ruleSet = try loadRuleSet()
        let registry = try #require(ruleSet.registry)
        let importRules = try #require(ruleSet.importRules)
        let sharedSubstrate = try #require(ruleSet.sharedSubstrate)

        #expect(!registry.sampleHeaderAliases.isEmpty)
        #expect(!registry.batchHeaderAliases.isEmpty)
        #expect(!registry.substrateHeaderAliases.isEmpty)
        #expect(!registry.metadataLookupAliases.isEmpty)
        #expect(!importRules.supportedFileExtensions.isEmpty)
        #expect(!sharedSubstrate.treatmentKeywords.isEmpty)
        #expect(!sharedSubstrate.materialTokens.isEmpty)
    }

    @Test("rules schema version stays on supported runtime version")
    func rulesSchemaVersionMatchesRuntime() throws {
        let ruleSet = try loadRuleSet()
        #expect(ruleSet.version == RuleLoader.currentSchemaVersion)
    }

    private func loadRuleSet() throws -> FilenameRuleSet {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let ruleURL = projectRoot.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")
        let data = try Data(contentsOf: ruleURL)
        return try JSONDecoder().decode(FilenameRuleSet.self, from: data)
    }
}
