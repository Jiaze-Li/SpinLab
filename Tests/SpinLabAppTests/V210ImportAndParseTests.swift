import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.1.0 Import And Parse")
struct V210ImportAndParseTests {
    @Test("managed storage applies allow list and explicit ignore list")
    func managedStorageFiltersByExtensionRules() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-tests-\(UUID().uuidString)", isDirectory: true)
        let input = root.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let names = [
            "a.dat",
            "b.lvm",
            "c.txt",
            "d.csv",
            "e.gph"
        ]
        for name in names {
            let url = input.appendingPathComponent(name)
            try Data("content".utf8).write(to: url)
        }

        let storage = SpinLabManagedStorage(rootURL: root)
        let imported = storage.importMeasurementFiles(
            from: [input],
            allowedFileExtensions: ["dat", "lvm", "txt", "csv"],
            ignoredFileExtensions: ["gph"]
        )
        let importedNames = Set(imported.map(\.fileName))

        #expect(imported.count == 4)
        #expect(importedNames == Set(["a.dat", "b.lvm", "c.txt", "d.csv"]))
        #expect(!importedNames.contains("e.gph"))
    }

    @Test("import pipeline rejects gph files even if they are passed in")
    func importPipelineRejectsGph() throws {
        let temp = FileManager.default.temporaryDirectory
        let sourceURL = temp.appendingPathComponent("sample.gph")
        let managedURL = temp.appendingPathComponent("\(UUID().uuidString)-sample.gph")
        let file = ImportedMeasurementFile(
            fileName: "sample.gph",
            sourceFileURL: managedURL,
            originalFileURL: sourceURL
        )

        let imported = WorkflowRegistry.shared
            .defaultBundle()
            .importPipeline
            .importFiles([file])
        #expect(imported.isEmpty)
    }

    @Test("parser emits workflow and default sample from parent folder fallback")
    func parserEmitsParentDerivedDefaultSampleKey() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_1mA_ch1_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.workflowName == "RT")
        #expect(parsed.defaultSampleKey == "PN40")
        #expect(parsed.folderDerivedSampleKeys == ["PN40"])
        #expect(parsed.temperature == nil)
        #expect(parsed.current == "1mA")
    }

    @Test("parser keeps channel substrate tags out of file-level substrate tags")
    func parserSeparatesFileAndChannelScopesByFirstChannelToken() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/RT_1mA_ch1_PN36_ch2_PN36_HF_STO111_ch3_PN37_wafer.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.substrateTags.isEmpty)
        #expect(parsed.channelHints.count == 3)

        let ch1 = parsed.channelHints.first(where: { $0.channel == "ch1" })
        #expect(ch1?.sampleID == "PN36")
        #expect(ch1?.tags.isEmpty == true)

        let ch2 = parsed.channelHints.first(where: { $0.channel == "ch2" })
        #expect(ch2?.sampleID == "PN36")
        #expect(ch2?.tags == ["HF", "STO111", "STO"])

        let ch3 = parsed.channelHints.first(where: { $0.channel == "ch3" })
        #expect(ch3?.sampleID == "PN37")
        #expect(ch3?.tags.isEmpty == true)
    }

    @Test("parser emits conflict warning when filename and folder sample ids disagree")
    func parserEmitsConflictWarningForDisjointFileAndFolderSamples() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_1mA_PN41_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.sampleIDs.contains("PN40"))
        #expect(parsed.sampleIDs.contains("PN41"))
        #expect(parsed.warnings.contains(where: { $0.lowercased().contains("conflict") }))
    }

    @Test("parser score arbitration selects unique winner when no single-source shortcut applies")
    func parserSelectsUniqueScoreArbitrationWinner() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_1mA_PN40_PN41_ch1_PN40_ch2_PN41_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN40")
        #expect(!parsed.warnings.contains(where: { $0.lowercased().contains("ambiguous") }))
    }

    @Test("parser leaves default sample empty when top score arbitration ties")
    func parserLeavesDefaultSampleEmptyOnArbitrationTie() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_PN40_PN41_ch1_PN40_ch2_PN41_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == nil)
        #expect(parsed.warnings.contains(where: { $0.lowercased().contains("arbitration is ambiguous") }))
    }

    @Test("parser emits score-fallback warning when low-confidence channel-only winner is chosen")
    func parserEmitsScoreFallbackWarningForLowConfidenceWinner() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_PN40_ch2_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN40")
        #expect(parsed.warnings.contains(where: { $0.lowercased().contains("score fallback") }))
    }

    @Test("parser falls back to file stem when no workflow token is detected")
    func parserFallsBackToFileStemWithoutWorkflowMatch() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/misc/unknown_pattern_file.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.workflowName == nil)
        #expect(parsed.measurementName == "unknown_pattern_file")
    }

    @Test("parser recognizes expanded current and field units")
    func parserRecognizesExpandedCurrentAndFieldUnits() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_0.5A_250mT_ch1_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.current == "0.5A")
        #expect(parsed.field == "250mT")
    }

    @Test("parser recognizes celsius temperature tokens")
    func parserRecognizesCelsiusTemperatureTokens() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_25C_1mA_ch1_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.temperature == "25C")
    }

    private func loadBundledRuleSetForTests() throws -> FilenameRuleSet {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let ruleURL = projectRoot.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")
        let data = try Data(contentsOf: ruleURL)
        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: data)
        ruleSet.loadWarnings = ruleSet.compile()
        return ruleSet
    }
}
