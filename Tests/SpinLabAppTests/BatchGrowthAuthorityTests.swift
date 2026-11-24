import Foundation
import Testing
@testable import SpinLabApp

@Suite("Task 10B: Batch Growth Parameter Authority & Sample Notes")
struct BatchGrowthAuthorityTests {
    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SpinLab-Task10B-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeV2Root() throws -> (URL, LibraryStore) {
        let root = try makeTempRoot()
        let store = LibraryStore()
        try store.initializeV2Library(at: root)
        return (root, store)
    }

    private func testChoices() -> NativeSampleSubstrateChoices {
        NativeSampleSubstrateChoices(
            treatments: ["o", "b"], materials: ["STO", "LAO"], orientations: ["001", "110"], defaultTreatment: "o"
        )
    }

    @Test("Canonical growth schema uses 生长温度 and 生长脉冲频率; bare 温度 and 厚度 are cleaned up")
    func canonicalDefinitionAndOwnershipCleanup() {
        let schemaTags = NewSampleFormSchema.shared.numberFields.map(\.tag)
        #expect(schemaTags.contains("生长温度"))
        #expect(schemaTags.contains("生长脉冲频率"))
        #expect(!schemaTags.contains("温度"))
        #expect(!schemaTags.contains("频率"))

        let ruleBook = LibraryFieldOwnershipRuleBook.shared
        #expect(ruleBook.scope(for: "生长温度") == .batch)
        #expect(ruleBook.scope(for: "生长脉冲频率") == .batch)
        #expect(ruleBook.scope(for: "温度") == .unknown)
        #expect(ruleBook.scope(for: "temperature") == .unknown)

        let aliases = withBundledRules { $0.registryRules()?.numericKeyAliases ?? [:] }
        #expect(LibraryRegistryParser.normalizeNumericKey("生长温度", aliases: aliases) == "生长温度")
        #expect(LibraryRegistryParser.normalizeNumericKey("生长脉冲频率", aliases: aliases) == "生长脉冲频率")
        #expect(LibraryRegistryParser.normalizeNumericKey("频率", aliases: aliases) == "生长脉冲频率")
        #expect(LibraryRegistryParser.normalizeNumericKey("厚度", aliases: aliases) == nil)
        #expect(LibraryRegistryParser.normalizeNumericKey("温度", aliases: aliases) == nil)
        #expect(LibraryRegistryParser.numericUnits["厚度"] == nil)
        #expect(LibraryRegistryParser.numericUnits["生长温度"] == "°C")
        #expect(LibraryRegistryParser.numericUnits["生长脉冲频率"] == "Hz")
    }

    @Test("V2 stores growth parameters exclusively on Batch; multi-sample and same-substrate samples share Batch and update together")
    func v2BatchGrowthAuthorityAndQuerySync() async throws {
        let (root, store) = try makeV2Root()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = NativeSampleCreationService()
        let settings = LibrarySettings(rootPath: root.path, allowedBatchPrefixes: [])

        var f1 = NewSampleFields()
        f1.date = "2026-11-24"
        f1.lab = "E3-L4"
        f1.growthMaterial = "SRO"
        f1.batch = "PN301"
        f1.substrateMaterial = "STO"
        f1.substrateOrientation = "001"
        f1.temperature = 680
        f1.pressure = 120
        f1.frequency = 5
        f1.hasAttenuator = true
        f1.rheed.grid = 3.5

        let d1 = try f1.makeDraft(sampleUID: "smp_a001", choices: testChoices()).get()
        let r1 = service.createSample(draft: d1, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample1, batch1, _) = r1 else {
            Issue.record("Expected sample1 creation to succeed: \(String(describing: r1))")
            return
        }

        // Same Batch, identical substrate, distinct UID (K3)
        var f2 = NewSampleFields()
        f2.batch = "PN301"
        f2.growthMaterial = "SRO"
        f2.substrateMaterial = "STO"
        f2.substrateOrientation = "001"
        f2.temperature = 999 // must not overwrite existing batch
        let d2 = try f2.makeDraft(sampleUID: "smp_a002", choices: testChoices()).get()
        let r2 = service.createSample(draft: d2, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample2, batch2, _) = r2 else {
            Issue.record("Expected sample2 creation to succeed: \(String(describing: r2))")
            return
        }

        #expect(sample1.id == "smp_a001")
        #expect(sample2.id == "smp_a002")
        #expect(sample1.numericTags.isEmpty && sample1.numericDisplay.isEmpty)
        #expect(sample2.numericTags.isEmpty && sample2.numericDisplay.isEmpty)
        #expect(sample1.metadata["date"] == nil && sample1.metadata["lab"] == nil)
        #expect(batch1.numericTags["生长温度"] == 680)
        #expect(batch1.numericTags["氧压"] == 120)
        #expect(batch1.numericTags["生长脉冲频率"] == 5)
        #expect(batch1.metadata["date"] == "2026-11-24")
        #expect(batch1.metadata["attenuator"] == "yes")
        #expect(batch2.numericTags["生长温度"] == 680)

        // Detail & Search read from Batch
        let computation = LibraryViewComputationService()
        let sections1 = computation.makeDetailSections(for: sample1, batch: batch2)
        #expect(sections1.numericFields.contains(where: { $0.label == "生长温度" && $0.value == "680 °C" }))

        let match680 = LibrarySearchFilters(
            batchText: "", substrateText: "", keywordText: "",
            oxygen: nil, temperature: 680, energy: nil,
            oxygenTolerance: nil, temperatureTolerance: 1, energyTolerance: nil
        )
        #expect(computation.matchesSearch(sample: sample1, batch: batch2, filters: match680))
        #expect(computation.matchesSearch(sample: sample2, batch: batch2, filters: match680))

        // Update Batch growth parameter -> both samples reflect change immediately
        var updatedBatch = batch2
        updatedBatch.numericTags["生长温度"] = 720
        updatedBatch.numericDisplay["生长温度"] = "720 °C"
        try store.updateBatch(updatedBatch, rootURL: root)

        let reloadedIndex = try store.readOnlyCompleteIndex(rootURL: root)
        let reloadedBatch = try #require(reloadedIndex.batches.first(where: { $0.id == "PN301" }))
        #expect(!computation.matchesSearch(sample: sample1, batch: reloadedBatch, filters: match680))
        let match720 = LibrarySearchFilters(
            batchText: "", substrateText: "", keywordText: "",
            oxygen: nil, temperature: 720, energy: nil,
            oxygenTolerance: nil, temperatureTolerance: 1, energyTolerance: nil
        )
        #expect(computation.matchesSearch(sample: sample1, batch: reloadedBatch, filters: match720))
        #expect(computation.matchesSearch(sample: sample2, batch: reloadedBatch, filters: match720))

        let actor = SpinLabDataActor()
        let actorDisplay = try await actor.lookupSampleNumericDisplay(libraryRootPath: root.path, sampleKey: "smp_a002")
        #expect(actorDisplay["生长温度"] == "720 °C")
    }

    @Test("Sample notes preserve legacy purpose/note on first display without disk write, and persist across restart")
    func sampleNotesAndLegacyPhoneSubmission() throws {
        let (root, store) = try makeV2Root()
        defer { try? FileManager.default.removeItem(at: root) }

        // Old phone submission JSON with purpose and note
        let legacyPhoneJSON = Data("""
        {
          "batch": "PN302",
          "growthMaterial": "SRO",
          "substrateMaterial": "STO",
          "substrateOrientation": "001",
          "purpose": "Test interface",
          "note": "Annealed 30 min"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(NewSampleFields.self, from: legacyPhoneJSON)
        let draft = try decoded.makeDraft(sampleUID: "smp_b001", choices: testChoices()).get()

        let service = NativeSampleCreationService()
        let settings = LibrarySettings(rootPath: root.path, allowedBatchPrefixes: [])
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(created, _, _) = outcome else {
            Issue.record("Expected creation to succeed: \(String(describing: outcome))")
            return
        }

        // First display joins legacy purpose/note without writing sample.notes to disk
        #expect(created.notes == nil)
        #expect(created.initialDisplayNotes == "Test interface\nAnnealed 30 min")

        // Saving edited notes writes sample.notes while keeping legacy metadata intact
        var edited = created
        edited.notes = "Updated user note"
        try store.updateSample(edited, rootURL: root, changeSource: "manual_edit")

        let reloaded = try store.readOnlyCompleteIndex(rootURL: root)
        let found = try #require(reloaded.samples.first(where: { $0.id == "smp_b001" }))
        #expect(found.notes == "Updated user note")
        #expect(found.initialDisplayNotes == "Updated user note")
        #expect(found.metadata["purpose"] == "Test interface")
        #expect(found.metadata["note"] == "Annealed 30 min")
    }

    @Test("Legacy V1 batch-vs-sample numeric conflict is reported without auto-picking a side")
    func v1ConflictDetection() {
        let batch = LibraryBatch(
            id: "PN100", displayName: "PN100", sheetName: "",
            metadata: [:], numericTags: ["生长温度": 650], numericDisplay: ["生长温度": "650 °C"],
            sampleKeys: ["s1"], updatedAt: Date()
        )
        let sample = LibrarySample(
            id: "s1", displayName: "s1", batchId: "PN100",
            substrateRaw: "STO(001)", substrateDisplay: "STO(001)",
            substrateTokens: [], substrateTags: [],
            metadata: [:], numericTags: ["生长温度": 700], numericDisplay: ["生长温度": "700 °C"],
            updatedAt: Date()
        )
        let conflicts = batch.growthConflicts(with: sample)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].key == "生长温度")
        #expect(conflicts[0].batchValue == 650)
        #expect(conflicts[0].sampleValue == 700)
    }
}
