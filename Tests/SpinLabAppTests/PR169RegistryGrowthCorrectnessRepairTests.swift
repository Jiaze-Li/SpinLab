import CoreXLSX
import Foundation
import Testing
@testable import SpinLabApp

/// PR #169 closeout — correctness repair pass 1. Covers the five items the
/// Claude/Codex PR reviews raised against `RegistryGrowthMutationService`,
/// `XLSXSheetValueReader`, and `RegistryGrowthDateMapper`:
///
/// 1. Reserved-row Apply must decode real shared strings (never
///    `sharedStrings: []`).
/// 2. Reserved composite identifiers must use Human Identifier (peer)
///    semantics, not raw equality.
/// 3. Composite-row Registry → Library read-contract validation must match
///    by identity, not `batchesById[item.batchId]`, and must validate
///    `expectedSampleKeys` by substrate identity rather than a literal
///    string set that embeds a possibly-different peer human identifier.
/// 4. A numeric Excel cell must survive `XLSXSheetValueReader.cellString`
///    even when the workbook also carries `sharedStrings.xml`.
/// 5. The Obsidian `YYYY-MM-DD` date parser must reject a shape/calendar-
///    invalid date rather than clamping it into range.
@Suite("PR169 RegistryGrowthMutationService correctness repair")
struct PR169RegistryGrowthCorrectnessRepairTests {
    // MARK: - Fixture plumbing (mirrors V545/V572's own helpers)

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
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
        return (XLSXWorkbookKit.readCellValue(cell: row, sharedStrings: workbook.sharedStrings), row.attribute(forName: "s")?.stringValue)
    }

    private func makeFullNote(
        path: String, batchId: String, date: String = "2026-08-20", material: String = "SRO",
        substrate: String = "STO(001)", temperature: String? = "650", distance: String? = "45",
        pressure: String? = "100", energy: String? = "1.2", pulse: String? = "200/3000"
    ) -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [.growthDate: claim(date, notePath: path, rawKey: "date")]
        if let temperature { growthClaims[.growthTemperature] = claim(temperature, notePath: path, rawKey: "temperature") }
        if let distance { growthClaims[.targetSubstrateDistance] = claim(distance, notePath: path, rawKey: "sample height") }
        if let pressure { growthClaims[.oxygenPressure] = claim(pressure, notePath: path, rawKey: "pressure") }
        if let energy { growthClaims[.laserEnergy] = claim(energy, notePath: path, rawKey: "energy") }
        if let pulse { growthClaims[.pulseCount] = claim(pulse, notePath: path, rawKey: "pulse") }
        return ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: growthClaims,
            rawFields: [claim(material, notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: substrate, provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: substrate), material: nil, orientation: nil)]
        )
    }

    // MARK: - A. Shared-string reserved 编号 + simple identifier → FILL Apply succeeds

    @Test("A. A reserved row whose 编号 cell is a genuine shared-string cell fills correctly")
    func sharedStringReservedSimpleIdentifierFills() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PR169-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForSharedStringReservedRow(to: url)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plan = try buildPlan(fixtureURL: url, notes: [makeFullNote(path: "lno9.md", batchId: "LNO9", material: "LNO")])
        let item = try #require(plan.items.first { $0.batchId == "LNO9" })
        guard case .fillReservedRow = item.action else {
            Issue.record("Expected .fillReservedRow, got \(item.action)")
            return
        }

        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO9"], registryURL: url)
        #expect(result.appliedBatchIds == ["LNO9"])

        let idCell = try readCell(url: url, sheet: "LNO", ref: "A2")
        #expect(idCell.value == "LNO9", "编号 must remain exactly what it was, never rewritten")
        let dateCell = try readCell(url: url, sheet: "LNO", ref: "B2")
        #expect(dateCell.value == "2026.8.20")

        let reparsed = try parseIndex(url)
        #expect(reparsed.batches.first { $0.id == "LNO9" } != nil)
    }

    // MARK: - B/C. Shared-string reserved composite 编号 → FILL Apply succeeds, read-contract passes

    @Test("B/C. Reserved composite 编号 PN111/SRO2 (shared-string) fills for incoming PN111 without rewriting 编号, and the real parser reconstructs exactly the intended Sample")
    func sharedStringReservedCompositeIdentifierFillsAndReadContractPasses() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PR169-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForSharedStringReservedRow(to: url)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Planner produces FILL for incoming "PN111" against the reserved
        // "PN111/SRO2" cell — same identity-aware row matching the planner
        // already uses (spec: peer human identifiers, not raw equality).
        let plan = try buildPlan(fixtureURL: url, notes: [makeFullNote(path: "pn111.md", batchId: "PN111")])
        let item = try #require(plan.items.first { $0.batchId == "PN111" })
        guard case let .fillReservedRow(targetSheet, rowNumber) = item.action else {
            Issue.record("Expected .fillReservedRow, got \(item.action)")
            return
        }
        #expect(targetSheet == "PLD-N样品")
        #expect(rowNumber == 2)
        #expect(!item.expectedSampleKeys.isEmpty)

        // Apply succeeds.
        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: ["PN111"], registryURL: url)
        #expect(result.appliedBatchIds == ["PN111"])

        // 编号 remains PN111/SRO2 — never rewritten.
        let idCell = try readCell(url: url, sheet: "PLD-N样品", ref: "A2")
        #expect(idCell.value == "PN111/SRO2")

        // Intended growth fields are filled (日期 is column C on PLD-N样品 —
        // see RegistryGrowthXLSXFixture.pldnHeaders).
        let dateCell = try readCell(url: url, sheet: "PLD-N样品", ref: "C2")
        #expect(dateCell.value == "2026.8.20")

        // The real LibraryRegistryParser reconstructs the Batch/Sample from
        // the composite raw cell, and the read-contract inside `apply`
        // already proved (before committing) that this Batch's Sample set
        // is exactly the intended one — no extra/missing physical Sample.
        let reparsed = try parseIndex(url)
        let batch = try #require(reparsed.batches.first { $0.id == "PN111/SRO2" })
        #expect(batch.sampleKeys.count == 1, "exactly one physical Sample — never split/duplicated across the two peer identifiers")
        #expect(reparsed.samples.filter { $0.batchId == "PN111/SRO2" }.count == 1)
    }

    // MARK: - D. Malformed composite identifier still fails closed

    @Test("D. A reserved row whose 编号 cell is wholly malformed fails closed at fillReservedRow, never guessed past")
    func malformedReservedIdentifierFailsClosed() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PR169-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForSharedStringReservedRow(to: url)
        defer { try? FileManager.default.removeItem(at: dir) }
        let originalBytes = try Data(contentsOf: url)

        // Row 3 on PLD-N样品 is a wholly malformed reserved cell ("???") —
        // construct the plan item directly (bypassing the planner, which
        // would never itself match this row to any incoming batch id) to
        // isolate the mutation service's own fail-closed identity check.
        let fingerprint = try XLSXWorkbookKit.contentFingerprint(of: url)
        let item = RegistryGrowthImportItem(
            batchId: "PN111", sourceNotePaths: ["forged.md"], targetSheetHint: "PLD-N样品",
            action: .fillReservedRow(targetSheet: "PLD-N样品", rowNumber: 3),
            columnValues: ["日期": "2026.8.20"], provenance: [], blankColumns: [],
            expectedSampleKeys: ["PN111||UNKNOWN|UNKNOWN"], warnings: [], blockingReasons: []
        )
        let plan = RegistryGrowthImportPlan(
            registryFingerprint: fingerprint, registrySourcePath: url.path, builtAt: .now,
            items: [item], diagnostics: [], existingCount: 0
        )

        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["PN111"], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes, "a failed identity check must never touch the file")
    }

    // MARK: - E. Numeric Excel 日期 cell survives a workbook that also carries sharedStrings.xml

    @Test("E. A genuinely numeric 日期 cell is still read as its Excel serial when the workbook also carries sharedStrings.xml")
    func numericDateSurvivesSharedStringsWorkbook() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PR169-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForNumericDateWithSharedStrings(to: url)
        defer { try? FileManager.default.removeItem(at: dir) }

        // LNO1's 日期 is a genuine numeric Excel serial (46236 == 2026-08-02)
        // and the workbook also has a non-empty xl/sharedStrings.xml (via
        // PLD-N样品's reserved shared-string 编号 cell). A differing
        // Obsidian date forces a structured `.conflict` — which can only
        // ever be produced if `row.columnValues["日期"]` was actually
        // populated, i.e. the numeric cell was NOT silently dropped by
        // `XLSXSheetValueReader.cellString` once `sharedStrings` was
        // non-nil.
        let plan = try buildPlan(fixtureURL: url, notes: [makeFullNote(path: "lno1.md", batchId: "LNO1", date: "2026-08-05", material: "LNO")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let dateDiff = try #require(item.existingDifferences.first { $0.field == .date })
        #expect(dateDiff.registryValue == "46236", "the raw numeric cell text must have been read, not silently dropped")
        #expect(dateDiff.obsidianValue == "2026.8.5")
    }

    // MARK: - F. Strict YYYY-MM-DD Gregorian validation

    @Test("F. RegistryGrowthDateMapper accepts only a real, strictly-shaped Gregorian YYYY-MM-DD date", arguments: [
        ("2026-02-28", true), ("2024-02-29", true), ("2026-08-02", true),
        ("2026-02-29", false), ("2026-02-31", false), ("26-08-02", false),
        ("2026-8-2", false), ("2026-13-01", false), ("not a date", false)
    ])
    func strictISODateValidation(_ input: String, expectedValid: Bool) throws {
        let iso = RegistryGrowthDateMapper.canonicalISODate(fromObsidianISODate: input)
        #expect((iso != nil) == expectedValid, "canonicalISODate(\"\(input)\") validity mismatch")
    }
}
