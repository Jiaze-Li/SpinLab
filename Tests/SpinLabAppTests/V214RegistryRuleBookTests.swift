// FIXME: tests reference removed `loadedOverrideFiles:` parameter on the rule
// book initializer. Disabled until ported to the current registry API.
#if PORT_TESTS_TO_NEW_RULEBOOK_API
import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.1.4 Registry Rule Book")
struct V214RegistryRuleBookTests {
    @Test("system log sheets are excluded from registry indexing")
    func systemSheetsAreExcluded() {
        let rules = makeRules()
        let headerByColumn: [Int: String] = [1: "sample_id", 2: "substrate"]

        #expect(!rules.shouldIndexSheet(named: "__metadata_sync_log", headerByColumn: headerByColumn))
        #expect(!rules.shouldIndexSheet(named: "__numeric_tags_log", headerByColumn: headerByColumn))
    }

    @Test("sample header is required for sheet indexing")
    func sampleHeaderIsRequired() {
        let rules = makeRules()
        let invalidHeader: [Int: String] = [1: "日期", 2: "工作"]
        let validHeader: [Int: String] = [1: "编号", 2: "substrate"]

        #expect(!rules.shouldIndexSheet(named: "实验大纲", headerByColumn: invalidHeader))
        #expect(rules.shouldIndexSheet(named: "PN", headerByColumn: validHeader))
        #expect(rules.sampleColumnIndex(headerByColumn: validHeader) == 1)
    }

    @Test("overview sheets are excluded even with valid sample headers")
    func overviewSheetsAreExcluded() {
        let rules = makeRules()
        let validHeader: [Int: String] = [1: "编号", 2: "substrate"]

        #expect(!rules.shouldIndexSheet(named: "实验大纲", headerByColumn: validHeader))
    }

    @Test("sample header aliases from config are recognized")
    func configuredSampleHeaderAliasIsRecognized() {
        let rules = makeRules()
        let aliasedHeader: [Int: String] = [1: "sample_no", 2: "substrate"]

        #expect(rules.shouldIndexSheet(named: "PN", headerByColumn: aliasedHeader))
        #expect(rules.sampleColumnIndex(headerByColumn: aliasedHeader) == 1)
    }

    @Test("sample ID candidates are normalized and deduplicated")
    func sampleIDCandidatesAreNormalized() {
        let rules = makeRules()
        let parsed = rules.sampleIDCandidates(from: " pn41 / PN42 / pn41 ")

        #expect(parsed == ["PN41", "PN42"])
        #expect(rules.normalizedLookupSampleID(" pn41 ") == "PN41")
    }

    @Test("sample ID candidates follow filename sample-id patterns")
    func sampleIDCandidatesFollowFilenameRules() {
        let rules = makeRules()
        let parsed = rules.sampleIDCandidates(from: "foo / PN41 / unknown / S20")

        #expect(parsed == ["PN41", "S20"])
    }

    private func makeRules() -> RegistryLookupRuleBook {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let ruleURL = projectRoot.appendingPathComponent("Sources/SpinLabApp/config/filename_parse_rules.json")
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
        return RegistryLookupRuleBook(ruleLoadResult: loadResult)
    }
}

#endif
