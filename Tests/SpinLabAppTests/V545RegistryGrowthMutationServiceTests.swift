import CoreXLSX
import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5A: `RegistryGrowthMutationService` coverage. Every test here
/// mutates a fresh temp *copy* of the from-scratch fixture — never a real
/// Registry file. Style/backup/atomic-replace/validation behavior is the
/// focus; planning behavior is covered in
/// `V545RegistryGrowthImportPlannerTests`.
@Suite("V5.4.5 RegistryGrowthMutationService")
struct V545RegistryGrowthMutationServiceTests {
    // MARK: - Fixture plumbing

    private func makeFixtureCopy() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V545-mut-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.build(to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    private func makeNote(
        path: String, batchId: String, date: String = "2026-08-20", material: String = "LNO",
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

    /// Like `makeNote`, but carries two distinct substrate entries on one
    /// note — exercises the planner's real multi-substrate → multiple
    /// `expectedSampleKeys` path (spec §6 test: "multi-substrate exact
    /// SampleKey set passes").
    private func makeMultiSubstrateNote(path: String, batchId: String) -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [.growthDate: claim("2026-08-20", notePath: path, rawKey: "date")]
        growthClaims[.growthTemperature] = claim("650", notePath: path, rawKey: "temperature")
        growthClaims[.targetSubstrateDistance] = claim("45", notePath: path, rawKey: "sample height")
        growthClaims[.oxygenPressure] = claim("100", notePath: path, rawKey: "pressure")
        growthClaims[.laserEnergy] = claim("1.2", notePath: path, rawKey: "energy")
        growthClaims[.pulseCount] = claim("200/3000", notePath: path, rawKey: "pulse")
        return ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: growthClaims,
            rawFields: [claim("LNO", notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [
                ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil),
                ObsidianSubstrateEntry(raw: "MgO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "MgO(001)"), material: nil, orientation: nil)
            ]
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
        // See V545RegistryGrowthImportPlannerTests: isolated rules provider,
        // not the shared mutable singleton, to avoid racing other tests.
        // The planner also needs it now (its own `LibrarySubstrateParser`
        // for `expectedSampleKeys`), so both share one `withBundledRules`.
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

    // MARK: - 11. Style id preserved when filling a reserved row

    @Test("11. Filling a reserved row preserves that row's other untouched cell styles")
    func stylePreservedOnReservedRowFill() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // NNO4's 编号 cell carries style "5" pre-mutation (see fixture).
        let before = try readCell(url: url, sheet: "NNO", ref: "A2")
        #expect(before.style == "5")

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nno4.md", batchId: "NNO4")])
        _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["NNO4"], registryURL: url)

        let after = try readCell(url: url, sheet: "NNO", ref: "A2")
        #expect(after.style == "5", "编号 cell's pre-existing style must survive an unrelated column write in the same row")
        #expect(after.value == "NNO4")
    }

    // MARK: - 12. Appended row inherits style

    @Test("12. Appended row inherits the nearest normal row's per-cell style, not its values")
    func appendedRowInheritsStyle() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // LNO1 (row 2) has 生长温度 (column E) styled "7" in the fixture.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)

        // LNO2 lands on the next row after the fixture's 4 existing LNO rows (row 6).
        let appended = try readCell(url: url, sheet: "LNO", ref: "E6")
        #expect(appended.style == "7", "appended row should inherit the template row's per-cell style")
        #expect(appended.value == "650", "appended cell must carry LNO2's own value, never the template row's value")
    }

    // MARK: - 13. Unrelated cell values unchanged

    @Test("13. Unrelated existing cells (value and style) are untouched by an append")
    func unrelatedCellsUnchangedOnAppend() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let beforeRemark = try readCell(url: url, sheet: "LNO", ref: "K2")
        let beforeStyle = try readCell(url: url, sheet: "LNO", ref: "E2")

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)

        let afterRemark = try readCell(url: url, sheet: "LNO", ref: "K2")
        let afterStyle = try readCell(url: url, sheet: "LNO", ref: "E2")
        #expect(afterRemark.value == beforeRemark.value)
        #expect(afterStyle.style == beforeStyle.style)
        #expect(afterStyle.value == beforeStyle.value)
    }

    // MARK: - 14. No new sheet

    @Test("14. Apply never creates a new sheet")
    func noNewSheetCreated() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try sheetNames(of: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)

        let after = try sheetNames(of: url)
        #expect(before == after)
    }

    @Test("14b. Attempting to apply an item whose target sheet doesn't exist throws before writing anything")
    func missingSheetRefusedAtApplyTime() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V545-mut-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.build(includeLSMO: false, to: url)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lsmo1.md", batchId: "LSMO1", material: "LSMO")])
        // The planner already marks this blocked (sheet missing), so apply
        // must refuse it as not-executable rather than silently no-op'ing.
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LSMO1"], registryURL: url)
        }
    }

    // MARK: - 15/16. Failed validation / failed backup leave original unchanged

    @Test("15. A stale (already-applied) item fails fast, original file byte-identical")
    func staleItemFailsWithoutMutating() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)

        var plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        // Corrupt the plan's own item list to simulate an item the mutation
        // service must refuse (skipExisting is never executable).
        plan.items = plan.items.map { item in
            var copy = item
            if copy.batchId == "LNO2" { copy.action = .skipExisting(targetSheet: "LNO", rowNumber: 2) }
            return copy
        }
        #expect(throws: (any Error).self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    // MARK: - 17. Stale plan fingerprint aborts apply

    @Test("17. Registry changed since plan was built → apply aborts, original untouched")
    func staleFingerprintAbortsApply() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])

        // Simulate a manual edit to the workbook after the plan was built.
        try "manually edited".data(using: .utf8)!.write(to: url, options: .atomic)
        let mutatedBytes = try Data(contentsOf: url)

        #expect(throws: RegistryGrowthMutationError.self) {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)
        }
        #expect(try Data(contentsOf: url) == mutatedBytes, "aborted apply must not touch the (already-changed) file further")
    }

    // MARK: - 18. Successful apply creates a backup

    @Test("18. Successful apply writes a timestamped backup of the pre-mutation original")
    func successfulApplyCreatesBackup() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)

        #expect(FileManager.default.fileExists(atPath: result.backupPath))
        #expect(try Data(contentsOf: URL(fileURLWithPath: result.backupPath)) == originalBytes)
        #expect(result.appliedBatchIds == ["LNO2"])
    }

    // MARK: - 19. Candidate reparses through CoreXLSX / 20. Post-apply parser sees new batch

    @Test("19/20. Applied Registry re-parses via CoreXLSX and the new batch is visible through LibraryRegistryParser")
    func appliedRegistryReparsesAndIsVisible() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno2.md", batchId: "LNO2"),
            makeNote(path: "nno4.md", batchId: "NNO4")
        ])
        _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2", "NNO4"], registryURL: url)

        #expect(XLSXFile(filepath: url.path) != nil)

        let reparsed = try parseIndex(url)
        let batchIds = Set(reparsed.batches.map(\.id))
        #expect(batchIds.contains("LNO2"))
        #expect(batchIds.contains("NNO4"))
        let lno2 = try #require(reparsed.batches.first { $0.id == "LNO2" })
        #expect(lno2.metadata["日期"] == "2026.8.20")
    }

    @Test("Apply is all-or-nothing per call: two batches on the same sheet both land")
    func multipleItemsSameSheetBothApplied() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno2.md", batchId: "LNO2"),
            makeNote(path: "lno3.md", batchId: "LNO3")
        ])
        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2", "LNO3"], registryURL: url)
        #expect(Set(result.appliedBatchIds) == Set(["LNO2", "LNO3"]))

        let reparsed = try parseIndex(url)
        let batchIds = Set(reparsed.batches.map(\.id))
        #expect(batchIds.contains("LNO2"))
        #expect(batchIds.contains("LNO3"))
    }

    // MARK: - 20b. Library read-contract gate (Phase 5A review blocker #3, extended)
    //
    // Obsidian→Registry success invariant: the committed Registry must be a
    // valid input to Registry→Library (`LibraryRegistryParser`) and produce
    // the expected Batch/Sample identity for every applied item. This is
    // checked on the *candidate* file before the atomic replace — a failing
    // candidate must never become the real Registry — and, redundantly, on
    // the real file afterward via `postApplyValidate` (same shared check,
    // called twice).

    @Test("20b. Expected Sample key missing from candidate → apply throws before replace, real Registry byte-identical")
    func expectedSampleKeyMissingBlocksReplace() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)

        var plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        // The Batch row itself would write and reparse fine on its own
        // (covered by test 19/20) — this simulates the specific failure mode
        // blocker #3 targets: a Batch that would exist after write, but a
        // canonical Sample the planner expected does not, which a Batch-only
        // check would miss. Because the candidate is now validated *before*
        // the atomic replace, this must be caught pre-write: the real
        // Registry is never touched.
        plan.items = plan.items.map { item in
            var copy = item
            if copy.batchId == "LNO2" {
                copy.expectedSampleKeys.append("LNO2||BOGUS-SUBSTRATE-NEVER-PARSED|UNKNOWN")
            }
            return copy
        }

        var thrownDescription = ""
        do {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)
            Issue.record("expected apply to throw before replacing the real Registry")
        } catch {
            thrownDescription = String(describing: error)
        }
        #expect(thrownDescription.contains("BOGUS-SUBSTRATE-NEVER-PARSED"))
        #expect(try Data(contentsOf: url) == originalBytes, "candidate failing the expected-Sample-keys check must never replace the real Registry")
    }

    @Test("22. Batch id corrupted in the written row → candidate fails Library read-contract, real Registry byte-identical")
    func batchUnreadableInCandidateBlocksReplace() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)

        let batchIdHeader = try #require(RegistryGrowthFieldMapping.header(for: .batchId, availableHeaders: Set(RegistryGrowthXLSXFixture.materialSheetHeaders)))
        var plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        // Corrupts only the *written* id cell, leaving `item.batchId` (what
        // the mutation service resolves/validates against) as "LNO2" — this
        // simulates a candidate where the Batch the planner meant to write
        // is not actually the one that ends up readable.
        plan.items = plan.items.map { item in
            var copy = item
            if copy.batchId == "LNO2" {
                copy.columnValues[batchIdHeader] = "ZZZ-NOT-A-BATCH"
            }
            return copy
        }

        var thrownDescription = ""
        do {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)
            Issue.record("expected apply to throw before replacing the real Registry")
        } catch {
            thrownDescription = String(describing: error)
        }
        #expect(thrownDescription.contains("not readable"))
        #expect(try Data(contentsOf: url) == originalBytes, "candidate whose applied Batch id is unreadable must never replace the real Registry")
    }

    @Test("23. Candidate produces an unexpected extra Sample key for the same batch → apply throws before replace")
    func unexpectedExtraSampleKeyBlocksReplace() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let originalBytes = try Data(contentsOf: url)

        var plan = try buildPlan(fixtureURL: url, notes: [makeMultiSubstrateNote(path: "lno2.md", batchId: "LNO2")])
        let lno2 = try #require(plan.items.first { $0.batchId == "LNO2" })
        // The planner legitimately expects two canonical Sample keys here
        // (STO(001) and MgO(001)); truncate to one so the candidate's
        // actually-parsed Sample set carries a key the plan never declared.
        #expect(lno2.expectedSampleKeys.count == 2, "fixture note must carry two distinct substrate entries for this test to be meaningful")
        plan.items = plan.items.map { item in
            var copy = item
            if copy.batchId == "LNO2" {
                copy.expectedSampleKeys = [copy.expectedSampleKeys[0]]
            }
            return copy
        }

        var thrownDescription = ""
        do {
            _ = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)
            Issue.record("expected apply to throw before replacing the real Registry")
        } catch {
            thrownDescription = String(describing: error)
        }
        #expect(thrownDescription.contains("unexpected"))
        #expect(try Data(contentsOf: url) == originalBytes, "candidate carrying an unexpected extra Sample key must never replace the real Registry")
    }

    @Test("24. Multi-substrate batch whose exact Sample key set matches expected → commits normally")
    func multiSubstrateExactSampleKeySetCommits() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let plan = try buildPlan(fixtureURL: url, notes: [makeMultiSubstrateNote(path: "lno2.md", batchId: "LNO2")])
        let lno2 = try #require(plan.items.first { $0.batchId == "LNO2" })
        #expect(lno2.expectedSampleKeys.count == 2)

        let result = try makeMutationService().apply(plan: plan, selectedBatchIds: ["LNO2"], registryURL: url)
        #expect(result.appliedBatchIds == ["LNO2"])

        // 25. Final post-replace validation still ran (reuses the same
        // Library-read-contract check as the pre-replace candidate gate) —
        // the real, now-replaced Registry reparses to exactly the expected
        // Sample key set for this batch.
        let reparsed = try parseIndex(url)
        let lno2Batch = try #require(reparsed.batches.first { $0.id == "LNO2" })
        #expect(Set(lno2Batch.sampleKeys) == Set(lno2.expectedSampleKeys))
    }

    // MARK: - 21. Same-directory atomic staging (Phase 5A review blocker #2)

    @Test("21. commitTransaction stages the candidate beside sourceURL, never in workDir's (system temp) directory")
    func transactionStagesCandidateBesideSource() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // `prepareWorkingDirectory` always unzips into system temp — a
        // different directory tree from the fixture's own (simulated
        // OneDrive/CloudStorage) directory. If the candidate ever gets
        // staged beside `workDir` instead of beside `sourceURL`, this
        // divergence makes the bug observable.
        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }
        #expect(workDir.deletingLastPathComponent() != url.deletingLastPathComponent())

        var observedCandidateDir: URL?
        _ = try XLSXWorkbookKit.commitTransaction(workDir: workDir, sourceURL: url) { candidateURL in
            observedCandidateDir = candidateURL.deletingLastPathComponent()
            #expect(FileManager.default.fileExists(atPath: candidateURL.path))
        }

        #expect(observedCandidateDir == url.deletingLastPathComponent(), "candidate must be staged in sourceURL's own directory")
        #expect(observedCandidateDir != workDir.deletingLastPathComponent(), "candidate must not be staged beside workDir (system temp)")
    }

    // MARK: - Helpers

    private func sheetNames(of url: URL) throws -> [String] {
        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let workbook = try XLSXWorkbookKit.loadWorkbook(in: workDir)
        return try XLSXWorkbookKit.sheetNames(workbook: workbook)
    }
}
