import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5C: `RegistryGrowthImportPlanner`'s structured Existing field
/// differences (spec §1/§2/§14). Never re-derives conflict decisions —
/// every test here confirms the structured `existingDifferences` array
/// mirrors the SAME `SampleDossierBuilder`/`DossierFieldReconciliation`
/// verdict `RegistryGrowthImportPlanner` already reused for the free-text
/// warning it replaces, just with the exact Registry row's own value
/// (`RegistryRowSnapshot.columnValues`) and the canonically-mapped Obsidian
/// value (`RegistryGrowthDateMapper` for dates) attached.
@Suite("V5.7.2 RegistryGrowthImportPlanner Existing structured differences")
struct V572RegistryGrowthExistingDiffTests {
    private func makeFixtureRegistry() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V572-registry-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.build(to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    /// LNO1 (the fixture's fully-populated row: 日期=2026.1.1, substrate=
    /// STO(001), 靶=LNO, 生长温度=650, 靶机距=45, 氧压=100, 能量=1.2,
    /// 预打/生长次数=200/3000) is used as the Existing row throughout.
    /// `date`/`pulse` default to `nil` (no Obsidian claim at all — an
    /// `obsidianOnly`/absent reconciliation, never a difference) rather than
    /// a "matching" value: `SampleDossierBuilder`'s own date/pulse
    /// normalization compares against the Registry's raw display string
    /// (dot-separated dates, compound "预打/生长次数"), so passing a claim
    /// through unrelated fields is the only way to isolate "this field has
    /// zero Obsidian evidence" from "this field agrees" for this fixture —
    /// the four magnitude-normalized fields below (temperature/distance/
    /// pressure/energy) are what exercise real agreement.
    private func makeLNO1Note(
        path: String = "lno1.md",
        date: String? = nil,
        pulse: String? = nil
    ) -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [
            .growthTemperature: claim("650", notePath: path, rawKey: "temperature"),
            .targetSubstrateDistance: claim("45", notePath: path, rawKey: "sample height"),
            .oxygenPressure: claim("100", notePath: path, rawKey: "pressure"),
            .laserEnergy: claim("1.2", notePath: path, rawKey: "energy")
        ]
        if let date { growthClaims[.growthDate] = claim(date, notePath: path, rawKey: "date") }
        if let pulse { growthClaims[.pulseCount] = claim(pulse, notePath: path, rawKey: "pulse") }
        return ObsidianNoteRecord(
            notePath: path, batchId: "LNO1", identity: .unresolvedSample,
            growthClaims: growthClaims,
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

    // MARK: - A. Single conflict → one structured difference

    @Test("A. Existing date conflict produces a structured difference with the exact Registry and mapped Obsidian values")
    func singleDateConflictProducesStructuredDifference() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(date: "2026-08-12")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(RegistryGrowthImportPresentation.filter(for: item) == .existing)
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .date)
        #expect(diff.header == "日期")
        #expect(diff.registryValue == "2026.1.1")
        // G. Obsidian value is produced by the ONE existing date mapper
        // (`RegistryGrowthDateMapper`), never a second ad hoc formatter.
        #expect(diff.obsidianValue == RegistryGrowthDateMapper.registryDisplayString(fromISODate: "2026-08-12"))
        #expect(diff.obsidianValue == "2026.8.12")
    }

    // MARK: - B. Two conflicts → two structured differences

    @Test("B. Two disagreeing fields produce two structured differences")
    func twoConflictsProduceTwoStructuredDifferences() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(date: "2026-08-12", pulse: "500/2400")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.count == 2)
        let headers = Set(item.existingDifferences.map(\.header))
        #expect(headers == ["日期", "预打/生长次数"])
        let pulseDiff = try #require(item.existingDifferences.first { $0.header == "预打/生长次数" })
        #expect(pulseDiff.registryValue == "200/3000")
        #expect(pulseDiff.obsidianValue == "500/2400")
    }

    // MARK: - C/D. Agreement → no structured difference, compacted into existingCount

    @Test("C/D. Full agreement produces zero structured differences and is compacted into existingCount")
    func fullAgreementIsCompacted() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note()])

        #expect(plan.items.first { $0.batchId == "LNO1" } == nil, "clean Existing item must not occupy plan.items")
        #expect(plan.existingCount == 1)
    }

    // MARK: - E. Existing with differences stays visible

    @Test("E. An Existing item with differences is never compacted away")
    func existingWithDifferencesStaysVisible() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(date: "2026-08-12")])

        #expect(plan.items.contains { $0.batchId == "LNO1" })
        #expect(plan.existingCount == 0)
    }

    // MARK: - False-positive equality guard (5.4.3 follow-up)

    /// The dossier's upstream `.conflict` verdict for `growthDate` is
    /// produced against a raw-string library value that never goes through
    /// `RegistryGrowthDateMapper` (see `SampleDossierBuilder.reconcile`) —
    /// so an Obsidian ISO date that maps to the SAME display string as the
    /// exact Registry cell must still collapse to "no difference" once both
    /// sides are compared through the canonical mapper.
    @Test("G. Date claim that maps to the exact Registry display string produces no structured difference")
    func dateFalsePositiveIsSuppressed() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // LNO1's Registry 日期 is "2026.1.1" — "2026-01-01" maps to the same string.
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(date: "2026-01-01")])

        let item = plan.items.first { $0.batchId == "LNO1" }
        #expect(item == nil, "no structured date difference should keep this item out of plan.items")
        #expect(plan.existingCount == 1)
    }

    /// Mirrors the date case for `pulseCount`: the dossier's library-side
    /// value for this field is derived from an unrelated thickness/`厚度`
    /// numeric parse (see `LibraryRegistryParser.numericValue`), so it can
    /// disagree with the exact Registry cell even when the Obsidian claim
    /// IS the exact Registry cell string.
    @Test("H. Pulse claim identical to the exact Registry cell produces no structured difference")
    func pulseFalsePositiveIsSuppressed() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // LNO1's Registry 预打/生长次数 is "200/3000".
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(pulse: "200/3000")])

        let item = plan.items.first { $0.batchId == "LNO1" }
        #expect(item == nil, "no structured pulse difference should keep this item out of plan.items")
        #expect(plan.existingCount == 1)
    }

    @Test("I. A genuine pulse difference still produces exactly one structured difference with both exact values")
    func genuinePulseDifferenceStillMaterializes() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(pulse: "500/800")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .pulseCount)
        #expect(diff.registryValue == "200/3000")
        #expect(diff.obsidianValue == "500/800")
    }

    @Test("J. Mixed case: date collapses to equal, pulse genuinely differs — only pulse appears")
    func mixedCaseOnlyGenuineDifferenceAppears() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(date: "2026-01-01", pulse: "500/800")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .pulseCount)
        #expect(diff.header == "预打/生长次数")
    }

    // MARK: - F. Left-side field summary derives from structured differences

    @Test("F. existingDifferenceFieldLabels derives from existingDifferences, in order")
    func fieldSummaryDerivesFromStructuredDifferences() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeLNO1Note(date: "2026-08-12", pulse: "500/2400")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })

        let labels = RegistryGrowthImportPresentation.existingDifferenceFieldLabels(for: item)
        #expect(labels == item.existingDifferences.map(\.header))
        #expect(Set(labels) == ["日期", "预打/生长次数"])
    }
}
