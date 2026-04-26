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

    @Test("workflow uses file token when file and parent provide conflicting workflow categories")
    func parserPrefersFileWorkflowOverParentWorkflowCategory() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/20260317_PN49to61_RT_MR_AHE/RT_1mA_ch1_PN59_ch2_PN60_ch3_PN61_wafer.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.workflowID == "RT")
    }

    @Test("condition value prefers file token over parent folder token in same category")
    func parserPrefersFileConditionOverParentCondition() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/RT_300K_folder/RT_80K_1mA_ch1_PN40_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.temperature == "80K")
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
        #expect(ch2?.sampleID == "PN36 HF STO 111")
        #expect(ch2?.tags == ["HF", "STO 111"])

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

    @Test("channel-only winner is selected without ambiguity warning under channel-first priority")
    func parserSelectsChannelOnlyWinnerWithoutAmbiguityWarning() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_PN40_ch2_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN40")
        #expect(!parsed.warnings.contains(where: { $0.lowercased().contains("ambiguous") }))
    }

    @Test("single file sample shortcut wins before score aggregation")
    func parserSingleFileSampleShortcutWinsBeforeScoring() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN42/RT_run/RT_1mA_PN40_ch1_PN42_ch2_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN40")
        #expect(!parsed.warnings.contains(where: { $0.lowercased().contains("score fallback") }))
    }

    @Test("file-only winner is high-confidence and does not emit score fallback warning")
    func parserDoesNotWarnForFileOnlyWinner() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_PN40_PN41_1mA_ch1_PN40_ch2_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN40")
        #expect(!parsed.warnings.contains(where: { $0.lowercased().contains("score fallback") }))
    }

    @Test("single channel sample shortcut wins before single folder sample shortcut")
    func parserSingleChannelSampleShortcutWinsBeforeSingleFolderSampleShortcut() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_1mA_ch1_PN41_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN41")
    }

    @Test("score aggregation lets channel evidence outrank split file and folder evidence")
    func parserScoreAggregationLetsChannelEvidenceOutrankFileAndFolder() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/PN42/RT_run/RT_PN40_PN41_1mA_ch1_PN42_ch2_PN43_AMR.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN42")
        #expect(!parsed.warnings.contains(where: { $0.lowercased().contains("ambiguous") }))
    }

    @Test("trailing file-level condition after channels is still parsed as global condition")
    func parserParsesTrailingFileLevelConditionAfterChannels() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/misc/C1_PN21_STO_001_C2_PN21_STO_111_C3_PN20_STO_001_80K.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.temperature == "80K")
        #expect(parsed.channelHints.count == 3)
    }

    @Test("channel test-content tokens are not interpreted as channel sample keys")
    func parserKeepsChannelTestContentOutOfChannelSampleKeys() throws {
        let ruleSet = try loadBundledRuleSetForTests()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let fileURL = URL(
            fileURLWithPath: "/tmp/misc/XY_90shift_80K_PN36_original_STO111_wafer_ch2_AMR_ch3_PHE_8T_1mA.dat"
        )

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.defaultSampleKey == "PN36")
        #expect(parsed.temperature == "80K")
        #expect(parsed.field == "8T")
        #expect(parsed.current == "1mA")
        #expect(parsed.channelHints.first(where: { $0.channel == "ch2" })?.sampleID == nil)
        #expect(parsed.channelHints.first(where: { $0.channel == "ch3" })?.sampleID == nil)
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

        #expect(parsed.conditionValues["abc"] == "12abc")
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

        #expect(parsed.conditionValues["wafer_type"] == "wafer")
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

        #expect(parsed.conditionValues["mode"] == "mode-token")
        #expect(parsed.warnings.contains(where: { $0.contains("matched both token-map and unit-suffix") }))
    }

    private func loadBundledRuleSetForTests() throws -> FilenameRuleSet {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let configDir = testsDir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true)

        let parseData = try Data(contentsOf: configDir.appendingPathComponent("filename_parse_rules.json"))
        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: parseData)

        struct SampleIDFile: Decodable { let patterns: [String] }
        struct SubstrateFile: Decodable {
            let substrateTagRules: [FilenameRuleSet.MapRule]
            let sharedSubstrate: FilenameRuleSet.SharedSubstrateRules?
        }
        struct MeasurementTagFile: Decodable { let rules: [FilenameRuleSet.MapRule] }
        struct WorkflowMatchFile: Decodable {
            let rules: [Rule]
            struct Rule: Decodable {
                let workflowID: String
                let scope: String
                let type: String
                let matchValues: [String]
            }
        }

        if let data = try? Data(contentsOf: configDir.appendingPathComponent("sample_id_rules.json")),
           let file = try? JSONDecoder().decode(SampleIDFile.self, from: data) {
            ruleSet.sampleId = FilenameRuleSet.SampleIdRules(patterns: file.patterns)
        }
        if let data = try? Data(contentsOf: configDir.appendingPathComponent("substrate_normalization_rules.json")),
           let file = try? JSONDecoder().decode(SubstrateFile.self, from: data) {
            ruleSet.substrateTagRules = file.substrateTagRules
            ruleSet.sharedSubstrate = file.sharedSubstrate
        }
        if let data = try? Data(contentsOf: configDir.appendingPathComponent("measurement_tag_rules.json")),
           let file = try? JSONDecoder().decode(MeasurementTagFile.self, from: data) {
            ruleSet.measurementTagRules = file.rules
        }
        if let data = try? Data(contentsOf: configDir.appendingPathComponent("library_import_rules.json")),
           let file = try? JSONDecoder().decode(LibraryImportRulesFile.self, from: data) {
            ruleSet.registry = file.registry
            ruleSet.importRules = file.importRules
        }
        if let data = try? Data(contentsOf: configDir.appendingPathComponent("workflow_match_rules.json")),
           let file = try? JSONDecoder().decode(WorkflowMatchFile.self, from: data) {
            ruleSet.measurementNameRules += file.rules.compactMap { rule in
                guard !rule.workflowID.isEmpty, !rule.matchValues.isEmpty,
                      let scope = FilenameRuleSet.MatchScope(rawValue: rule.scope),
                      let matchType = FilenameRuleSet.MatchType(rawValue: rule.type) else { return nil }
                let spec = FilenameRuleSet.MatchSpec(
                    scope: scope,
                    type: matchType,
                    value: rule.matchValues.count == 1 ? rule.matchValues[0] : nil,
                    values: rule.matchValues.count > 1 ? rule.matchValues : nil
                )
                return FilenameRuleSet.MapRule(match: spec, value: rule.workflowID)
            }
        }

        ruleSet.loadWarnings = ruleSet.compile()
        return ruleSet
    }
}
