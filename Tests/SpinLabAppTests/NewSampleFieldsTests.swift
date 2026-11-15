import Foundation
import Testing
@testable import SpinLabApp

@Suite("New Sample Fields")
struct NewSampleFieldsTests {
    private func choices() -> NativeSampleSubstrateChoices {
        NativeSampleSubstrateChoices(
            treatments: ["o", "b"], materials: ["STO"], orientations: ["001"], defaultTreatment: "o"
        )
    }

    private func fields() -> NewSampleFields {
        var f = NewSampleFields()
        f.batch = "PN200"
        f.growthMaterial = "SRO"
        f.substrateMaterial = "STO"
        f.substrateOrientation = "001"
        return f
    }

    private func draft(_ f: NewSampleFields) throws -> CreateNativeSampleDraft {
        try f.makeDraft(sampleUID: "uid-1", choices: choices()).get()
    }

    @Test("Batch, growth material and substrate material/orientation are required")
    func requiredFields() {
        for blank in [\NewSampleFields.batch, \.growthMaterial, \.substrateMaterial, \.substrateOrientation] {
            var f = fields()
            f[keyPath: blank] = "  "
            #expect(throws: CreateNativeSampleError.self) { try f.makeDraft(sampleUID: "u", choices: choices()).get() }
        }
    }

    @Test("Substrate defaults to the original treatment; frequency defaults to 2 Hz")
    func defaults() throws {
        let d = try draft(fields())
        #expect(d.substrateDescription == "o STO(001)")
        #expect(d.sampleUID == "uid-1")
        #expect(d.numericTags["频率"] == Double(RegistryGrowthPulseMapper.defaultHz))
        #expect(d.numericDisplay["频率"] == "2 Hz")
    }

    @Test("An explicit frequency is kept")
    func explicitFrequency() throws {
        var f = fields()
        f.frequency = 5
        #expect(try draft(f).numericDisplay["频率"] == "5 Hz")
    }

    @Test("Every number field becomes a tag with its unit; empty fields make no tag")
    func numericTagsAndUnits() throws {
        var f = fields()
        f.temperature = 650
        f.pressure = 125
        f.sampleHeight = 81
        f.frontEnergy = 40
        f.laserVoltage = 25.2
        f.laserOutputEnergy = 250
        f.prePulseCount = 1000
        f.growthPulseCount = 3000
        let d = try draft(f)
        #expect(d.numericDisplay == [
            "温度": "650 °C", "氧压": "125 mT", "样品高度": "81 mm",
            "镜前能量": "40 mJ", "激光器电压": "25.2 kV", "激光器输出能量": "250 mJ",
            "预打次数": "1000", "生长次数": "3000", "频率": "2 Hz"
        ])
        #expect(d.numericTags["激光器电压"] == 25.2)
        #expect(try draft(fields()).numericTags.keys.sorted() == ["频率"])
    }

    @Test("Text fields and RHEED are kept as metadata, empty ones are left out")
    func metadata() throws {
        var f = fields()
        f.date = "2026-09-16"
        f.lab = "E3-L4"
        f.purpose = "降氧压"
        f.hasAttenuator = true
        f.rheed.grid = 3.92
        f.rheed.x2 = 5
        let m = try draft(f).metadata
        #expect(m["date"] == "2026-09-16")
        #expect(m["lab"] == "E3-L4")
        #expect(m["material"] == "SRO")
        #expect(m["purpose"] == "降氧压")
        #expect(m["attenuator"] == "yes")
        #expect(m["RHEED Grid"] == "3.92")
        #expect(m["RHEED X2"] == "5")
        #expect(m["note"] == nil)
        #expect(m["RHEED Focus"] == nil)
    }

    @Test("Same value, same number and unit text whether it comes from an Excel cell or the form")
    func parityWithRegistryImport() throws {
        // Excel cells (parsed by the Registry import path) vs. the form (raw number).
        let excel: [(key: String, cell: String, formKey: String, formValue: Double)] = [
            ("温度", "650 C", "温度", 650),
            ("氧压", "125 mT", "氧压", 125),
            ("能量", "250 mJ", "激光器输出能量", 250),
            ("能量", "40 mJ", "镜前能量", 40),
            ("电压", "25.2 kV", "激光器电压", 25.2)
        ]
        for row in excel {
            let imported = try #require(LibraryRegistryParser.numericEntry(canonicalKey: row.key, value: row.cell))
            #expect(imported.display == LibraryRegistryParser.numericDisplay(canonicalKey: row.formKey, number: row.formValue))
        }
    }

    @Test("Every unit used by a form tag comes from the one unit table")
    func unitsLiveInOneTable() {
        for tag in ["镜前能量", "激光器电压", "激光器输出能量", "样品高度", "频率", "温度", "氧压"] {
            #expect(LibraryRegistryParser.numericUnits[tag] != nil)
        }
    }

    @Test("Fields survive a JSON round trip (the shape phone submissions will use)")
    func codableRoundTrip() throws {
        var f = fields()
        f.temperature = 650
        f.rheed.focus = 5.04
        let back = try JSONDecoder().decode(NewSampleFields.self, from: JSONEncoder().encode(f))
        #expect(back == f)
    }

    @Test("One substrate: makeDrafts equals makeDraft and keeps the base id")
    func singleSubstrateUnchanged() throws {
        let f = fields()
        let drafts = try f.makeDrafts(sampleUID: "smp_abc", choices: choices()).get()
        #expect(drafts.count == 1)
        #expect(drafts[0].sampleUID == "smp_abc")
        #expect(drafts[0] == (try f.makeDraft(sampleUID: "smp_abc", choices: choices()).get()))
    }

    @Test("Several substrates make one draft each: same batch and growth record, stable ids")
    func multipleSubstrates() throws {
        var f = fields()
        f.temperature = 700
        f.extraSubstrates = [
            .init(treatment: "b", material: "STO", orientation: "001"),
            .init()
        ]
        let drafts = try f.makeDrafts(sampleUID: "smp_abc", choices: choices(), displayName: "ignored").get()
        #expect(drafts.count == 2)
        #expect(drafts.map(\.sampleUID) == ["smp_abc", "smp_abc-2"])
        #expect(Set(drafts.map(\.batchId)) == ["PN200"])
        #expect(drafts[0].substrateDescription == "o STO(001)")
        #expect(drafts[1].substrateDescription == "b STO(001)")
        #expect(drafts[0].numericTags == drafts[1].numericTags)
        #expect(drafts.allSatisfy { $0.displayName == nil })
        #expect(NativeSampleCreationService.isValidSampleUID(drafts[1].sampleUID))
    }

    @Test("A half-filled extra substrate is an error, not dropped")
    func halfFilledExtraSubstrate() {
        var f = fields()
        f.extraSubstrates = [.init(treatment: "b", material: "STO", orientation: "")]
        #expect(throws: CreateNativeSampleError.self) { try f.makeDrafts(sampleUID: "smp_abc", choices: choices()).get() }
    }

    @Test("A payload without extra substrates (old phone submissions) still decodes")
    func oldPayloadDecodes() throws {
        let json = Data(#"{"batch":"PN200","growthMaterial":"SRO","substrateMaterial":"STO","substrateOrientation":"001"}"#.utf8)
        let f = try JSONDecoder().decode(NewSampleFields.self, from: json)
        #expect(f.extraSubstrates.isEmpty)
        #expect(try f.makeDrafts(sampleUID: "smp_abc", choices: choices()).get().count == 1)
    }

    @Test("A registry rules file without the option lists still decodes (empty lists)")
    func oldRulesFileDecodes() throws {
        let json = """
        {"sampleHeaderAliases":[],"excludedSheetNames":[],"sampleCellSeparators":"/",
         "batchHeaderAliases":[],"substrateHeaderAliases":[],"numericKeyAliases":{},"metadataLookupAliases":{}}
        """
        let rules = try JSONDecoder().decode(FilenameRuleSet.RegistryRules.self, from: Data(json.utf8))
        #expect(rules.labOptions.isEmpty)
        #expect(rules.growthMaterialOptions.isEmpty)
    }
}

@Suite("New Sample Shared Form Definition")
struct NewSampleFormSchemaTests {
    private let schema = NewSampleFormSchema.shared

    @Test("Every number field's unit label matches the single unit table")
    func unitsMatchUnitTable() {
        for field in schema.numberFields {
            #expect(field.unit == (LibraryRegistryParser.numericUnits[field.tag] ?? ""), "unit mismatch for \(field.key)")
        }
    }

    @Test("Every field in the definition is understood by the shared model, so no entrance can drop one")
    func everyFieldIsSupported() {
        var f = NewSampleFields()
        for field in schema.numberFields {
            f.setNumber(12.5, forKey: field.key)
            #expect(f.number(forKey: field.key) == 12.5, "number field \(field.key) is not wired")
        }
        for field in schema.rheedFields {
            f.setRheed(7, forKey: field.key)
            #expect(f.rheedValue(forKey: field.key) == 7, "RHEED field \(field.key) is not wired")
        }
    }

    @Test("Every filled field reaches the sample: a tag per number field, metadata per RHEED field")
    func everyFieldReachesTheDraft() throws {
        var f = NewSampleFields()
        f.batch = "PN200"; f.growthMaterial = "SRO"; f.substrateMaterial = "STO"; f.substrateOrientation = "001"
        for field in schema.numberFields { f.setNumber(3, forKey: field.key) }
        for field in schema.rheedFields { f.setRheed(4, forKey: field.key) }
        let choices = NativeSampleSubstrateChoices(
            treatments: ["o"], materials: ["STO"], orientations: ["001"], defaultTreatment: "o"
        )
        let draft = try f.makeDraft(sampleUID: "smp_a", choices: choices).get()
        #expect(Set(draft.numericTags.keys) == Set(schema.numberFields.map(\.tag)))
        for field in schema.rheedFields { #expect(draft.metadata[field.metadataKey] == "4") }
    }

    @Test("Each required field in the definition is really required by the shared model")
    func requiredFieldsAreEnforced() {
        let choices = NativeSampleSubstrateChoices(
            treatments: ["o"], materials: ["STO"], orientations: ["001"], defaultTreatment: "o"
        )
        for item in schema.required {
            var f = NewSampleFields()
            f.batch = "PN200"; f.growthMaterial = "SRO"; f.substrateMaterial = "STO"; f.substrateOrientation = "001"
            switch item.key {
            case "batch": f.batch = ""
            case "growthMaterial": f.growthMaterial = ""
            case "substrateMaterial": f.substrateMaterial = ""
            case "substrateOrientation": f.substrateOrientation = ""
            default: Issue.record("unknown required key \(item.key)")
            }
            #expect(throws: CreateNativeSampleError.self, "\(item.key) should be required") {
                try f.makeDraft(sampleUID: "smp_a", choices: choices).get()
            }
        }
    }

    @Test("The phone page has no field list of its own")
    func phonePageHasNoSecondFieldList() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let js = try String(
            contentsOf: root.appendingPathComponent("Resources/WebLibraryTemplate/new-sample.js"), encoding: .utf8
        )
        #expect(!js.contains("NUMBER_FIELDS"))
        #expect(!js.contains("RHEED_FIELDS"))
        #expect(js.contains("form.numberFields"))
    }
}
