import CoreXLSX
import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5C: `RegistryGrowthMutationService.apply(existingFieldEdits:)`
/// safety coverage (spec §7/§8/§9/§16). Every test mutates a fresh temp
/// *copy* of the from-scratch fixture — never a real Registry file — and
/// reuses `RegistryGrowthXLSXFixture` exactly like
/// `V545RegistryGrowthMutationServiceTests`.
@Suite("V5.7.2 RegistryGrowthMutationService Existing field edits")
struct V572RegistryGrowthExistingMutationTests {
    // MARK: - Fixture plumbing

    private func makeFixtureCopy() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V572-mut-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.build(to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    /// LNO1 (fixture row 2: 日期=2026.1.1, substrate=STO(001), 靶=LNO,
    /// 生长温度=650, 靶机距=45, 氧压=100, 能量=1.2, 预打/生长次数=200/3000)
    /// with a genuine date conflict (dot-format Registry dates never agree
    /// with `SampleDossierBuilder`'s ISO-only date comparator — see
    /// `V572RegistryGrowthExistingDiffTests`) and a genuine temperature
    /// conflict (700 vs 650).
    private func makeLNO1ConflictNote(path: String = "lno1.md", date: String = "2026-08-12", temperature: String = "700") -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: "LNO1", identity: .unresolvedSample,
            growthClaims: [
                .growthDate: claim(date, notePath: path, rawKey: "date"),
                .growthTemperature: claim(temperature, notePath: path, rawKey: "temperature"),
                .targetSubstrateDistance: claim("45", notePath: path, rawKey: "sample height"),
                .oxygenPressure: claim("100", notePath: path, rawKey: "pressure"),
                .laserEnergy: claim("1.2", notePath: path, rawKey: "energy")
            ],
            rawFields: [claim("LNO", notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil)]
        )
    }

    private func makeVault(notes: [ObsidianNoteRecord]) -> ObsidianVaultIndex {
        var batchesById: [String: ObsidianVaultIndex.BatchRecord] = [:]
        for note in notes {
            guard let batchId = note.batchId else { continue }
            var record = batchesById[batchId] ?? ObsidianVaultIndex.BatchRecord(batchId: batchId, growthClaims: [:], notePaths: [])
            for (field, claim) in note.growthClaims { record.growthClaims[field, default: []].append(claim) }
            record.notePaths.append(note.notePath)
            batchesById[batchId] = record
        }
        return ObsidianVaultIndex(sourceRootPath: "/tmp/vault", noteCount: notes.count, batches: Array(batchesById.values), samples: [], diagnostics: [], notes: notes)
    }

    private func buildPlan(fixtureURL: URL, notes: [ObsidianNoteRecord]) throws -> RegistryGrowthImportPlan {
        let vault = makeVault(notes: notes)
        let settings = LibrarySettings(rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil, registrySourcePath: fixtureURL.path, backupPath: nil, backupLastSyncedAt: nil, allowedBatchPrefixes: [], lastRefreshAt: nil)
        return try withBundledRules { provider in
            let library = try LibraryRegistryParser(ruleProvider: provider).parse(xlsxURL: fixtureURL, settings: settings).index
            let dossier = SampleDossierBuilder.build(library: library, obsidian: vault)
            return try RegistryGrowthImportPlanner(ruleProvider: provider).build(vault: vault, dossier: dossier, registryURL: fixtureURL)
        }
    }

    private func makeMutationService() -> RegistryGrowthMutationService {
        RegistryGrowthMutationService(ruleProvider: InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly()))
    }

    private func parseIndex(_ url: URL) throws -> LibraryIndex {
        let settings = LibrarySettings(rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil, registrySourcePath: url.path, backupPath: nil, backupLastSyncedAt: nil, allowedBatchPrefixes: [], lastRefreshAt: nil)
        return try withBundledRules { provider in
            try LibraryRegistryParser(ruleProvider: provider).parse(xlsxURL: url, settings: settings).index
        }
    }

    private func readCell(url: URL, sheet: String, ref: String) throws -> (value: String?, style: String?) {
        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let workbook = try XLSXWorkbookKit.loadWorkbook(in: workDir)
        let path = try XLSXWorkbookKit.worksheetPath(named: sheet, workbook: workbook)
        let doc = try XLSXWorkbookKit.loadXML(at: workDir.appending(path: path))
        guard let row = try doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']/*[local-name()='c' and @r='\(ref)']").first as? XMLElement else {
            return (nil, nil)
        }
        return (XLSXWorkbookKit.readCellValue(cell: row, sharedStrings: []), row.attribute(forName: "s")?.stringValue)
    }

    private func dateDiff(from item: RegistryGrowthImportItem) throws -> RegistryGrowthExistingDifference {
        try #require(item.existingDifferences.first { $0.field == .date })
    }

    private func temperatureDiff(from item: RegistryGrowthImportItem) throws -> RegistryGrowthExistingDifference {
        try #require(item.existingDifferences.first { $0.field == .growthTemperature })
    }

    // MARK: - A. Update one Existing field: only that cell changes

    @Test("A. Updating one Existing field touches only that cell — same row, same 编号, no append/duplicate")
    func updateOneFieldTouchesOnlyThatCell() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let diff = try dateDiff(from: item)

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: diff.registryValue, finalValue: diff.obsidianValue
        )
        let beforeId = try readCell(url: url, sheet: "LNO", ref: "A2")
        let beforeTemp = try readCell(url: url, sheet: "LNO", ref: "E2")

        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)

        #expect(result.existingFieldEditBatchIds == ["LNO1"])
        #expect(result.appliedBatchIds.isEmpty)
        let afterDate = try readCell(url: url, sheet: "LNO", ref: "B2")
        #expect(afterDate.value == "2026.8.12")
        let afterId = try readCell(url: url, sheet: "LNO", ref: "A2")
        #expect(afterId == beforeId, "编号 must never change")
        let afterTemp = try readCell(url: url, sheet: "LNO", ref: "E2")
        #expect(afterTemp == beforeTemp, "an untouched field on the same row must be byte-identical")

        // No append: LNO still has exactly its original 4 data rows (no new
        // row at 6), and no duplicate row for LNO1.
        let reparsed = try parseIndex(url)
        #expect(reparsed.batches.filter { $0.id == "LNO1" }.count == 1)
    }

    // MARK: - B. Update two fields in the same Existing row

    @Test("B. Updating two fields in the same Existing row changes both exact cells and nothing else")
    func updateTwoFieldsBothCellsChange() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let dDiff = try dateDiff(from: item)
        let tDiff = try temperatureDiff(from: item)

        let edits = [
            RegistryGrowthExistingFieldEdit(batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: dDiff.header, field: dDiff.field, originalRegistryValue: dDiff.registryValue, finalValue: dDiff.obsidianValue),
            RegistryGrowthExistingFieldEdit(batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: tDiff.header, field: tDiff.field, originalRegistryValue: tDiff.registryValue, finalValue: tDiff.obsidianValue)
        ]
        let beforeRemark = try readCell(url: url, sheet: "LNO", ref: "K2")

        _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: edits, registryURL: url)

        #expect(try readCell(url: url, sheet: "LNO", ref: "B2").value == "2026.8.12")
        #expect(try readCell(url: url, sheet: "LNO", ref: "E2").value == "700")
        let afterRemark = try readCell(url: url, sheet: "LNO", ref: "K2")
        #expect(afterRemark == beforeRemark)

        // K/L. Reads back through the real parser, numeric projection intact.
        let reparsed = try parseIndex(url)
        let lno1 = try #require(reparsed.batches.first { $0.id == "LNO1" })
        #expect(lno1.metadata["日期"] == "2026.8.12")
        #expect(lno1.numericTags["温度"] == 700)
    }

    // MARK: - C. Composite identifier

    @Test("C. Composite Registry cell PN110/SRO1 — an edit whose batchId is PN110 succeeds on the same row")
    func compositeIdentifierEditSucceeds() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V572-mut-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForMultiSeriesSheet(to: url)
        defer { try? FileManager.default.removeItem(at: dir) }

        // PN110/SRO1 lives on PLD-N样品 row 2: 靶=SRO, 日期=2026.8.10, substrate=STO(001).
        // `SampleDossierBuilder` joins Library/Obsidian batches by exact
        // batchId equality (Phase 4 spec §12) and does not itself know that
        // a composite Registry cell's "PN110" token refers to the same
        // record as `LibraryRegistryParser`'s own (unsplit) batch key — so
        // this test constructs the plan item directly, exactly like
        // `V572RegistryGrowthExistingEditStateTests`, to isolate what it
        // actually covers: the mutation service's OWN composite-identity
        // row matching (`RegistryIdentifierCell.parse` +
        // `RegistryBatchIdentity.parse`), not the planner's dossier join.
        let diff = RegistryGrowthExistingDifference(field: .date, header: "日期", registryValue: "2026.8.10", obsidianValue: "2026.8.15")
        let item = RegistryGrowthImportItem(
            batchId: "PN110", sourceNotePaths: ["pn110.md"], targetSheetHint: "PLD-N样品",
            action: .skipExisting(targetSheet: "PLD-N样品", rowNumber: 2),
            columnValues: [:], provenance: [], blankColumns: [], expectedSampleKeys: [],
            warnings: [], existingDifferences: [diff], blockingReasons: []
        )
        let fingerprint = try XLSXWorkbookKit.contentFingerprint(of: url)
        let plan = RegistryGrowthImportPlan(
            registryFingerprint: fingerprint, registrySourcePath: url.path, builtAt: .now,
            items: [item], diagnostics: [], existingCount: 0
        )

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "PN110", targetSheet: "PLD-N样品", rowNumber: 2, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: diff.registryValue, finalValue: diff.obsidianValue
        )
        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)

        #expect(result.existingFieldEditBatchIds == ["PN110"])
        let idCell = try readCell(url: url, sheet: "PLD-N样品", ref: "A2")
        #expect(idCell.value == "PN110/SRO1", "编号 must never be rewritten by this editor")
        let dateCell = try readCell(url: url, sheet: "PLD-N样品", ref: "C2")
        #expect(dateCell.value == "2026.8.15")
    }

    // MARK: - D. Edit for a field not present in planned differences → rejected

    @Test("D. An edit whose header was never a planned difference is rejected before any write")
    func editForUnplannedFieldRejected() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: "氧压",
            field: .oxygenPressure, originalRegistryValue: "100", finalValue: "999"
        )
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    // MARK: - E. Edit targeting the wrong row/sheet → rejected

    @Test("E. An edit whose targetSheet/rowNumber does not match the planned Existing row is rejected")
    func editWithWrongRowRejected() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let diff = try dateDiff(from: item)

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 999, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: diff.registryValue, finalValue: diff.obsidianValue
        )
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    // MARK: - F. Original Registry value no longer matches plan → rejected

    @Test("F. An edit whose originalRegistryValue is stale relative to the plan is rejected")
    func staleOriginalRegistryValueRejected() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let diff = try dateDiff(from: item)

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: "not-the-real-original-value", finalValue: diff.obsidianValue
        )
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    // MARK: - G. Stale fingerprint aborts before any mutation

    @Test("G. A stale plan fingerprint aborts an Existing field edit before any mutation")
    func staleFingerprintAbortsExistingEdit() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let diff = try dateDiff(from: item)

        try "manually edited".data(using: .utf8)!.write(to: url, options: .atomic)
        let mutatedBytes = try Data(contentsOf: url)

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: diff.registryValue, finalValue: diff.obsidianValue
        )
        #expect(throws: RegistryGrowthMutationError.self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == mutatedBytes)
    }

    // MARK: - Never allows editing 编号

    @Test("编号 may never be edited through this path, even if a caller forges an edit naming it")
    func batchIdFieldEditRejected() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: "编号",
            field: .batchId, originalRegistryValue: "LNO1", finalValue: "LNO1-HACKED"
        )
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    // MARK: - Empty Final value is rejected, never a silent clear

    @Test("An edit whose finalValue is empty/whitespace-only is rejected, never written as a clear")
    func emptyFinalValueRejected() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let diff = try dateDiff(from: item)

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: diff.registryValue, finalValue: "   "
        )
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    // MARK: - Zero Ready selections + one Existing edit still applies

    @Test("Zero Ready selections but one Existing field edit still applies (Apply 1 works)")
    func zeroReadySelectionsStillApplies() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1ConflictNote()])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let diff = try dateDiff(from: item)

        let edit = RegistryGrowthExistingFieldEdit(
            batchId: "LNO1", targetSheet: "LNO", rowNumber: 2, columnHeader: diff.header,
            field: diff.field, originalRegistryValue: diff.registryValue, finalValue: diff.obsidianValue
        )
        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: [], existingFieldEdits: [edit], registryURL: url)
        #expect(result.appliedBatchIds.isEmpty)
        #expect(result.existingFieldEditBatchIds == ["LNO1"])
    }
}
