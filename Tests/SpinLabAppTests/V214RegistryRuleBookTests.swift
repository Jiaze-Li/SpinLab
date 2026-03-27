import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.1.4 Registry Rule Book")
struct V214RegistryRuleBookTests {
    private let rules = RegistryLookupRuleBook()

    @Test("system log sheets are excluded from registry indexing")
    func systemSheetsAreExcluded() {
        let headerByColumn: [Int: String] = [1: "sample_id", 2: "substrate"]

        #expect(!rules.shouldIndexSheet(named: "__metadata_sync_log", headerByColumn: headerByColumn))
        #expect(!rules.shouldIndexSheet(named: "__numeric_tags_log", headerByColumn: headerByColumn))
    }

    @Test("sample header is required for sheet indexing")
    func sampleHeaderIsRequired() {
        let invalidHeader: [Int: String] = [1: "日期", 2: "工作"]
        let validHeader: [Int: String] = [1: "编号", 2: "substrate"]

        #expect(!rules.shouldIndexSheet(named: "实验大纲", headerByColumn: invalidHeader))
        #expect(rules.shouldIndexSheet(named: "PN", headerByColumn: validHeader))
        #expect(rules.sampleColumnIndex(headerByColumn: validHeader) == 1)
    }

    @Test("sample ID candidates are normalized and deduplicated")
    func sampleIDCandidatesAreNormalized() {
        let parsed = rules.sampleIDCandidates(from: " pn41 / PN42 / pn41 ")

        #expect(parsed == ["PN41", "PN42"])
        #expect(rules.normalizedLookupSampleID(" pn41 ") == "PN41")
    }
}
