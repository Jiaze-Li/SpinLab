import Foundation
import Testing
@testable import SpinLabApp

/// V5.7.1 — compact clean Existing items out of the Obsidian → Registry
/// preview. A clean, populated, exact-existing Registry row is
/// synchronization history (Button A will do nothing for it): the planner
/// must count it in `RegistryGrowthImportPlan.existingCount` rather than
/// materializing it as a `RegistryGrowthImportItem` in `items`. Anything the
/// planner cannot conclude is "unambiguously nothing to do" — duplicates,
/// reserved rows, historical holes, existing rows with an Obsidian/Registry
/// conflict — must stay visible. See `RegistryGrowthImportPlanner`'s
/// `isCleanExisting` helper.
@Suite("V5.7.1 RegistryGrowthImportPlanner compact Existing")
struct V571RegistryGrowthImportCompactExistingTests {
    // MARK: - Fixture plumbing

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    /// A bare stub note: only a batch id, no growth claims at all. Used for
    /// batches that already have a populated Registry row — no Obsidian
    /// evidence is needed to identify or skip them (spec: skipExisting is
    /// independent of Obsidian completeness), and carrying zero claims
    /// guarantees the dossier reconciliation never manufactures a spurious
    /// conflict warning that would keep the item visible.
    private func stubNote(path: String, batchId: String) -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: [:], rawFields: [], testStatus: [:], sampleObservations: [], substrateEntries: []
        )
    }

    /// A fully-evidenced note for a batch that should become a new/ready
    /// item.
    private func fullNote(path: String, batchId: String, material: String = "LNO", substrate: String = "STO(001)") -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [:]
        growthClaims[.growthDate] = claim("2026-08-20", notePath: path, rawKey: "date")
        growthClaims[.growthTemperature] = claim("650", notePath: path, rawKey: "temperature")
        growthClaims[.targetSubstrateDistance] = claim("45", notePath: path, rawKey: "sample height")
        growthClaims[.oxygenPressure] = claim("100", notePath: path, rawKey: "pressure")
        growthClaims[.laserEnergy] = claim("1.2", notePath: path, rawKey: "energy")
        growthClaims[.pulseCount] = claim("200/3000", notePath: path, rawKey: "pulse")

        return ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: growthClaims,
            rawFields: [claim(material, notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(
                raw: substrate,
                provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: substrate),
                material: nil, orientation: nil
            )]
        )
    }

    private func makeVault(notes: [ObsidianNoteRecord]) -> ObsidianVaultIndex {
        var batchesById: [String: ObsidianVaultIndex.BatchRecord] = [:]
        for note in notes {
            guard let batchId = note.batchId else { continue }
            var record = batchesById[batchId] ?? ObsidianVaultIndex.BatchRecord(batchId: batchId, growthClaims: [:], notePaths: [])
            for (field, claim) in note.growthClaims {
                record.growthClaims[field, default: []].append(claim)
            }
            record.notePaths.append(note.notePath)
            batchesById[batchId] = record
        }
        return ObsidianVaultIndex(
            sourceRootPath: "/tmp/vault", noteCount: notes.count,
            batches: Array(batchesById.values), samples: [], diagnostics: [], notes: notes
        )
    }

    private func buildPlan(fixtureURL: URL, notes: [ObsidianNoteRecord]) throws -> RegistryGrowthImportPlan {
        let vault = makeVault(notes: notes)
        let settings = LibrarySettings(
            rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil,
            registrySourcePath: fixtureURL.path, backupPath: nil, backupLastSyncedAt: nil,
            allowedBatchPrefixes: [], lastRefreshAt: nil
        )
        return try withBundledRules { provider in
            let library = try LibraryRegistryParser(ruleProvider: provider).parse(xlsxURL: fixtureURL, settings: settings).index
            let dossier = SampleDossierBuilder.build(library: library, obsidian: vault)
            return try RegistryGrowthImportPlanner(ruleProvider: provider).build(vault: vault, dossier: dossier, registryURL: fixtureURL)
        }
    }

    private func item(_ plan: RegistryGrowthImportPlan, _ batchId: String) -> RegistryGrowthImportItem? {
        plan.items.first { $0.batchId == batchId }
    }

    // MARK: - A. 100 clean existing batches → none in items, existingCount == 100

    @Test("A. 100 clean existing batches never occupy items; existingCount == 100")
    func bulkCleanExistingSuppressed() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-a-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        let numbers = Array(1...100)
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: numbers, to: url
        )
        let notes = numbers.map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        #expect(plan.items.isEmpty)
        #expect(plan.existingCount == 100)
    }

    // MARK: - B/I. 100 existing + 3 new → items has only the 3 new ones

    @Test("B. 100 existing + 3 new → plan.items contains only the 3 actionable items; existingCount == 100")
    func bulkExistingPlusNewBatches() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-b-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        let existingNumbers = Array(1...100)
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: existingNumbers, to: url
        )
        var notes = existingNumbers.map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        notes.append(contentsOf: [
            fullNote(path: "ex101.md", batchId: "EX101"),
            fullNote(path: "ex102.md", batchId: "EX102"),
            fullNote(path: "ex103.md", batchId: "EX103")
        ])
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        #expect(plan.items.count == 3)
        #expect(Set(plan.items.map(\.batchId)) == ["EX101", "EX102", "EX103"])
        #expect(plan.items.allSatisfy { $0.action == .appendNewRow(targetSheet: "NCO") })
        #expect(plan.existingCount == 100)
    }

    // MARK: - I. Item count tracks actionable items, not bulk existing scale

    @Test("I. Growing the bulk existing count does not grow plan.items")
    func itemCountDoesNotScaleWithExistingBulk() throws {
        for existingCount in [50, 300] {
            let url = FileManager.default.temporaryDirectory.appending(path: "V571-i-\(existingCount)-\(UUID().uuidString).xlsx")
            defer { try? FileManager.default.removeItem(at: url) }
            let existingNumbers = Array(1...existingCount)
            try RegistryGrowthXLSXFixture.buildForCompactExisting(
                seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: existingNumbers, to: url
            )
            var notes = existingNumbers.map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
            notes.append(fullNote(path: "exnew.md", batchId: "EX\(existingCount + 1)"))
            let plan = try buildPlan(fixtureURL: url, notes: notes)

            #expect(plan.items.count == 1)
            #expect(plan.existingCount == existingCount)
        }
    }

    // MARK: - C. Reserved row → NOT suppressed, remains Ready/fillReservedRow

    @Test("C. A reserved-ID-only row stays a Ready fillReservedRow item, never counted as existing")
    func reservedRowStaysVisible() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-c-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO",
            populatedNumbers: Array(1...20), reservedNumbers: [200], to: url
        )
        var notes = (1...20).map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        notes.append(fullNote(path: "ex200.md", batchId: "EX200"))
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        let reserved = try #require(item(plan, "EX200"))
        #expect(reserved.action == .fillReservedRow(targetSheet: "NCO", rowNumber: 22))
        #expect(reserved.isExecutable)
        #expect(plan.existingCount == 20)
    }

    // MARK: - D. Historical hole is never treated as existing just because it's below maxNumber

    @Test("D. A number below maxNumber with no actual Registry row is not Existing")
    func historicalHoleNotExisting() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-d-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        // A prefix outside the hard-coded prefix/PN-SRO routing table, so
        // this test exercises pure observed-series routing rather than the
        // legacy fallback rule (spec: incoming batches route via exact
        // Registry-row evidence, not maxNumber heuristics).
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: [108, 109, 111], to: url
        )
        let notes = [
            stubNote(path: "ex108.md", batchId: "EX108"),
            stubNote(path: "ex109.md", batchId: "EX109"),
            stubNote(path: "ex111.md", batchId: "EX111"),
            fullNote(path: "ex110.md", batchId: "EX110")
        ]
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        let hole = try #require(item(plan, "EX110"))
        if case .blocked = hole.action {
            Issue.record("EX110 must not be blocked/Existing merely because 110 < maxNumber 111; expected appendNewRow")
        }
        #expect(hole.action == .appendNewRow(targetSheet: "NCO"))
        #expect(plan.existingCount == 3)
    }

    // MARK: - E. Duplicate exact row → NOT suppressed, Blocked

    @Test("E. A duplicated exact Registry row stays visible as Blocked, never counted as existing")
    func duplicateRowStaysBlockedAndVisible() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-e-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO",
            populatedNumbers: Array(1...20), duplicateBatchIds: ["EX300"], to: url
        )
        var notes = (1...20).map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        notes.append(fullNote(path: "ex300.md", batchId: "EX300"))
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        let duplicate = try #require(item(plan, "EX300"))
        guard case let .blocked(reasons) = duplicate.action else {
            Issue.record("expected EX300 to be blocked as a duplicate row")
            return
        }
        #expect(reasons.contains { if case .duplicateRegistryRow(let sheet, _) = $0 { return sheet == "NCO" }; return false })
        #expect(plan.existingCount == 20)
    }

    // MARK: - F. Blocked items are never suppressed regardless of reason

    @Test("F. Blocked items (e.g. a routing/date failure among otherwise-clean existing batches) stay visible")
    func blockedItemsAmongBulkExistingStayVisible() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-f-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: Array(1...20), to: url
        )
        var notes = (1...20).map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        // A brand-new batch with no Registry row and no Obsidian date —
        // must be Blocked, never silently dropped like a clean Existing row.
        notes.append(stubNote(path: "ex999.md", batchId: "EX999"))
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        let blocked = try #require(item(plan, "EX999"))
        guard case .blocked = blocked.action else {
            Issue.record("expected EX999 to be blocked, not silently suppressed")
            return
        }
        #expect(plan.existingCount == 20)
    }

    // MARK: - G. A clean existing row is never writable/selectable

    @Test("G. A clean existing batch cannot be applied — the mutation service reports itemNotFound")
    func cleanExistingBatchNeverApplicable() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-g-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: Array(1...5), to: url
        )
        let notes = (1...5).map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        let plan = try buildPlan(fixtureURL: url, notes: notes)
        #expect(item(plan, "EX1") == nil)

        withBundledRules { provider in
            #expect(throws: RegistryGrowthMutationError.self) {
                _ = try RegistryGrowthMutationService(ruleProvider: provider).apply(plan: plan, selectedBatchIds: ["EX1"], registryURL: url)
            }
        }
    }

    // MARK: - H. No ordinary Existing item list — only the compact count

    @Test("H. No plan item maps to the Existing UI filter for a clean bulk-existing batch; the count is the only signal")
    func noExistingFilterListForCleanBulk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V571-h-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        let numbers = Array(1...40)
        try RegistryGrowthXLSXFixture.buildForCompactExisting(
            seriesPrefix: "EX", sheetName: "NCO", populatedNumbers: numbers, to: url
        )
        let notes = numbers.map { stubNote(path: "ex\($0).md", batchId: "EX\($0)") }
        let plan = try buildPlan(fixtureURL: url, notes: notes)

        let existingFilterItems = plan.items.filter { RegistryGrowthImportPresentation.filter(for: $0) == .existing }
        #expect(existingFilterItems.isEmpty)
        #expect(plan.existingCount == 40)
    }
}
