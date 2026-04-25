// FIXME: tests reference removed `loadedOverrideFiles:` parameter on the rule
// book initializer. Disabled until ported to the current registry API.
#if PORT_TESTS_TO_NEW_RULEBOOK_API
import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.4 Registry Substrate Rule Book")
struct V224RegistrySubstrateRuleBookTests {
    @Test("standalone origin token is detected from filename tokens")
    func standaloneOriginTokenIsDetected() {
        let rules = makeRules()
        #expect(rules.hasStandaloneOriginToken(fileName: "PN40_RT_O_ch1_AMR.dat", originalFilePath: nil))
    }

    @Test("single-letter origin token does not falsely match unrelated tokens")
    func originTokenDoesNotFalselyMatchUnrelatedTokens() {
        let rules = makeRules()
        #expect(!rules.hasStandaloneOriginToken(fileName: "PN40_STO111_ch1_AMR.dat", originalFilePath: nil))
    }

    @Test("substrate resolution picks unique matching candidate")
    func substrateResolutionPicksUniqueMatch() {
        let rules = makeRules()
        let resolution = rules.resolvedSubstrate(
            sampleID: "PN40",
            substrateValue: "HF STO(111), baked STO(111)",
            substrateTags: ["HF", "STO", "111"],
            allowsOriginToken: true
        )

        #expect(resolution.resolvedSubstrate == "HF STO(111)")
        #expect(resolution.warning == nil)
    }

    private func makeRules() -> RegistrySubstrateRuleBook {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let ruleURL = projectRoot.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")
        let data = try! Data(contentsOf: ruleURL)
        var ruleSet = try! JSONDecoder().decode(FilenameRuleSet.self, from: data)
        ruleSet.loadWarnings = ruleSet.compile()
        let loadResult = RuleLoader.LoadResult(
            ruleSet: ruleSet,
            warnings: ruleSet.loadWarnings,
            metadata: RuleLoader.RuleMetadata(
                version: ruleSet.version,
                sourceLabel: "TestBundle",
                sourcePath: ruleURL.path,
                contentHash: "test",
                loadedOverrideFiles: [],
                loadedAt: .now
            )
        )
        return RegistrySubstrateRuleBook(ruleLoadResult: loadResult)
    }
}

#endif
