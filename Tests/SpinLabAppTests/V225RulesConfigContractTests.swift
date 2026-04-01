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
        #expect(!(sharedSubstrate.orientationTokens ?? []).isEmpty)
        #expect(!(sharedSubstrate.materialDisplayNames ?? [:]).isEmpty)
    }

    @Test("rules schema version stays on supported runtime version")
    func rulesSchemaVersionMatchesRuntime() throws {
        let ruleSet = try loadRuleSet()
        #expect(ruleSet.version == RuleLoader.currentSchemaVersion)
    }

    @Test("single-letter treatment token follows configured canonical mapping")
    func singleLetterTreatmentTokenFollowsConfiguredCanonicalMapping() throws {
        let rules = try loadRuleSet()
        let substrate = try #require(rules.sharedSubstrate)
        let canonical = substrate.treatmentKeywords.first { _, keywords in
            keywords.contains(where: { $0.lowercased() == "b" })
        }?.key
        let expected = try #require(canonical)

        #expect(SampleSemanticDescriptor.normalizedProcessingTokenForRules("B") == expected)
    }

    @Test("legacy rule set without conditionDefinitions is migrated correctly")
    func legacyRuleSetWithoutConditionDefinitionsIsMigrated() {
        var legacy = FilenameRuleSet.fallback()
        legacy.conditionDefinitions = []
        legacy.conditions.extraConditions = [:]
        legacy.conditions.tokenMapRules = [:]
        legacy.conditions.temperaturePattern = "^-?\\d+(?:\\.\\d+)?(?:K)$"
        legacy.conditions.currentPattern = ""
        legacy.conditions.fieldPattern = ""
        legacy.deviceRules = [
            .init(
                match: .init(scope: .tokens, type: .equals, value: "wafer", values: nil),
                value: "wafer"
            )
        ]

        let warnings = RuleLoader.normalizeConditionDefinitionBindings(
            ruleSet: &legacy,
            sourceLabel: "Test"
        )

        #expect(!warnings.isEmpty)
        #expect(
            legacy.conditionDefinitions.contains {
                $0.id == "temperature"
                    && $0.kind == .unitSuffix
                    && $0.binding == "conditions.extraConditions.temperature"
            }
        )
        #expect(
            legacy.conditionDefinitions.contains {
                $0.id == "device"
                    && $0.kind == .tokenMap
                    && $0.binding == "conditions.tokenMapRules.device"
            }
        )
        #expect(legacy.conditions.extraConditions["temperature"] == "^-?\\d+(?:\\.\\d+)?(?:K)$")
        #expect(legacy.conditions.tokenMapRules["device"]?.count == 1)

        legacy.loadWarnings = legacy.compile()
        let parser = FilenameRuleParser(ruleSet: legacy)
        let parsed = parser.parse(from: URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_25K_wafer.dat"))
        #expect(parsed.temperature == "25K")
        #expect(parsed.deviceName == "wafer")
    }

    private func loadRuleSet() throws -> FilenameRuleSet {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let ruleURL = projectRoot.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")
        let data = try Data(contentsOf: ruleURL)
        return try JSONDecoder().decode(FilenameRuleSet.self, from: data)
    }
}
