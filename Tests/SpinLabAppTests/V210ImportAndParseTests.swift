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
            try Data("content-\(name)".utf8).write(to: url)
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

    @Test("managed storage deduplicates same-content files across different paths")
    func managedStorageDeduplicatesByContentFingerprint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-tests-\(UUID().uuidString)", isDirectory: true)
        let left = root.appendingPathComponent("left", isDirectory: true)
        let right = root.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileName = "XY_90shift_80K_PN39_STO111_wafer_ch2_AMR.dat"
        let contents = Data("same-content".utf8)
        try contents.write(to: left.appendingPathComponent(fileName))
        try contents.write(to: right.appendingPathComponent(fileName))

        let storage = SpinLabManagedStorage(rootURL: root)
        let imported = storage.importMeasurementFiles(
            from: [left, right],
            allowedFileExtensions: ["dat"]
        )

        #expect(imported.count == 1)
        #expect(imported.first?.fileName == fileName)
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

        #expect(parsed.workflowID == "RT")
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
        #expect(ch2?.sampleID == "PN36 HF STO111 STO")
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

        #expect(parsed.workflowID == nil)
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

    @Test("parser strips whitespace before tokenization so spaced unit suffix tokens are recognized")
    func parserRecognizesSpacedUnitSuffixTokensAfterWhitespaceNormalization() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN69/RT_run/20260328000728_3w_0deg_O_Position_0.000000 degree_Iac_0.001000 A_T_160.002 K_Vg_0.000000 V_Ig_0.000000 A.lvm")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.temperature == "160K")
        #expect(parsed.current == "0.001A")
    }

    @Test("parser rounds field values to nearest half-step and removes trailing .0")
    func parserRoundsFieldToHalfStep() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)

        let parsed61 = parser.parse(from: URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_6.1T_1mA.dat"))
        #expect(parsed61.field == "6T")

        let parsed65 = parser.parse(from: URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_6.5T_1mA.dat"))
        #expect(parsed65.field == "6.5T")
    }

    @Test("parser trims current floating noise with fixed precision rounding")
    func parserTrimsCurrentFloatingNoise() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_0.0001001A_1T.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.current == "0.0001A")
    }

    @Test("parser resolves device from unit-suffix definition when handbook defines device as unit-suffix")
    func parserResolvesDeviceFromUnitSuffixDefinition() throws {
        var ruleSet = try loadBundledRuleSetForTests()
        ruleSet.conditionDefinitions.append(
            .init(
                id: "device",
                label: "Device",
                kind: .unitSuffix,
                binding: "conditions.extraConditions.device"
            )
        )
        ruleSet.conditions.extraConditions["device"] = "^-?\\d+(?:\\.\\d+)?(?:deg)$"
        ruleSet.loadWarnings = ruleSet.compile()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN69/RT_run/run_0deg_1mA.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.deviceName == "0deg")
    }

    @Test("parser recognizes dynamic extra conditions when definition exists")
    func parserRecognizesDynamicExtraConditions() throws {
        var ruleSet = try loadBundledRuleSetForTests()
        ruleSet.conditionDefinitions.append(
            .init(
                id: "abc",
                label: "ABC",
                kind: .unitSuffix,
                binding: "conditions.extraConditions.abc"
            )
        )
        ruleSet.conditions.extraConditions["abc"] = "^-?\\d+(?:\\.\\d+)?(?:abc)$"
        ruleSet.loadWarnings = ruleSet.compile()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_12abc_1mA.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.extraConditionValues["abc"] == "12abc")
    }

    @Test("parser recognizes dynamic token-map conditions without schema changes")
    func parserRecognizesDynamicTokenMapConditions() throws {
        var ruleSet = try loadBundledRuleSetForTests()
        ruleSet.conditionDefinitions.append(
            .init(
                id: "wafer_type",
                label: "Wafer Type",
                kind: .tokenMap,
                binding: "conditions.tokenMapRules.wafer_type"
            )
        )
        ruleSet.conditions.tokenMapRules["wafer_type"] = [
            .init(
                match: .init(scope: .tokens, type: .equals, value: "wafer", values: nil),
                value: "wafer"
            )
        ]
        ruleSet.loadWarnings = ruleSet.compile()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_wafer_1mA.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.extraConditionValues["wafer_type"] == "wafer")
    }

    @Test("token-map wins when same label matches both token-map and unit-suffix")
    func tokenMapWinsWhenDualMatched() throws {
        var ruleSet = try loadBundledRuleSetForTests()
        ruleSet.conditionDefinitions.append(
            .init(
                id: "mode",
                label: "Mode",
                kind: .unitSuffix,
                binding: "conditions.extraConditions.mode"
            )
        )
        ruleSet.conditionDefinitions.append(
            .init(
                id: "mode",
                label: "Mode",
                kind: .tokenMap,
                binding: "conditions.tokenMapRules.mode"
            )
        )
        ruleSet.conditions.extraConditions["mode"] = "^-?\\d+(?:\\.\\d+)?(?:k)$"
        ruleSet.conditions.tokenMapRules["mode"] = [
            .init(
                match: .init(scope: .tokens, type: .equals, value: "1k", values: nil),
                value: "mode-token"
            )
        ]
        ruleSet.loadWarnings = ruleSet.compile()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_1k_1mA.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.extraConditionValues["mode"] == "mode-token")
        #expect(parsed.warnings.contains(where: { $0.contains("matched both token-map and unit-suffix") }))
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
