import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5.4.4: semantic normalization for the Existing false-positive
/// classes presentation-format string comparison alone can't catch —
/// Registry dates whose *display* format omits the year (a genuine Excel
/// date serial under a "m月d日" number format) and the confirmed
/// omitted-pulse-frequency-means-2Hz domain rule. Never re-derives the
/// upstream SampleDossier `.conflict` candidate — every test here exercises
/// the same `RegistryGrowthImportPlanner.existingRowDifferences` final
/// equality guard `V572RegistryGrowthExistingDiffTests` covers, just with
/// fixture rows that exercise the new semantic paths specifically.
@Suite("V5.4.4 Registry semantic date/pulse normalization")
struct V544RegistryGrowthSemanticNormalizationTests {
    private func makeFixtureRegistry() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V544-semantic-registry-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForSemanticDateAndPulse(to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    /// Every fixture row (LNO1..LNO6) carries 生长温度=650, 靶机距=45,
    /// 氧压=100, 能量=1.2 — matching claims for those keeps only date/pulse
    /// in `.conflict`, exactly like `V572RegistryGrowthExistingDiffTests`.
    private func makeNote(
        batchId: String,
        path: String,
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
            notePath: path, batchId: batchId, identity: .unresolvedSample,
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

    // MARK: - Date: A. Numeric serial with the same underlying date agrees

    @Test("Date A. Registry numeric date serial for 2026-08-02 vs Obsidian 2026-08-02 → no structured difference")
    func numericDateSameYearIsSuppressed() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-08-02")])

        #expect(plan.items.first { $0.batchId == "LNO1" } == nil, "same underlying date must compact into existingCount")
        #expect(plan.existingCount == 1)
    }

    // MARK: - Date: B. Numeric serial with a genuinely different year

    @Test("Date B. Registry numeric date serial for 2025-08-02 vs Obsidian 2026-08-02 → genuine difference")
    func numericDateDifferentYearIsReal() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO2", path: "lno2.md", date: "2026-08-02")])

        let item = try #require(plan.items.first { $0.batchId == "LNO2" })
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .date)
        #expect(diff.obsidianValue == "2026.8.2")
        #expect(plan.existingCount == 0)
    }

    // MARK: - Date: C. Registry text date already carries its own year

    @Test("Date C. Registry text date 2026.8.2 vs Obsidian 2026-08-02 → no structured difference")
    func textDateWithYearIsSuppressed() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO3", path: "lno3.md", date: "2026-08-02")])

        #expect(plan.items.first { $0.batchId == "LNO3" } == nil)
        #expect(plan.existingCount == 1)
    }

    // MARK: - Date: D. Unresolvable Registry date is never guessed equal

    @Test("Date D. An unparseable Obsidian date claim keeps the fallback-warning path, never a guessed equality")
    func unresolvableDateNeverGuessesEqual() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // Not a well-formed ISO date — `RegistryGrowthDateMapper.registryDisplayString`
        // returns nil for this, so the existing fallback-warning path applies
        // (never suppressed, never a materialized difference either).
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "not-a-date")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.isEmpty)
        #expect(!item.warnings.isEmpty)
        #expect(plan.existingCount == 0, "a fallback-warning item is not clean Existing — never compacted")
    }

    // MARK: - Date: E. Production case — yearless shared-string text, no trustworthy year anywhere

    /// Reproduces the exact production row that motivated this suite: the
    /// real Registry workbook (confirmed by extracting its raw
    /// `xl/worksheets/*.xml` / `xl/sharedStrings.xml`) stores 日期 for this
    /// row as a genuine `t="s"` shared-string cell whose text is the bare
    /// "8月2日" — not a numeric date serial (that's Date A/B above) and not
    /// the "yyyy.M.d" text convention (Date C). No other column in the row
    /// carries a year either. `RegistryGrowthDateMapper.semanticISODate`
    /// correctly returns nil for this (a non-numeric cell whose text
    /// doesn't parse as "yyyy.M.d"), so this must surface as a real,
    /// materialized Existing difference — never a guessed equality, and
    /// never silently dropped into a fallback warning either, since the
    /// Registry cell value that produced the `.conflict` verdict IS
    /// resolvable (just not equal without guessing the year).
    @Test("Date E. Registry yearless shared-string '8月2日' (production representation) vs Obsidian 2026-08-02 → remains a real difference")
    func productionYearlessSharedStringDateRemainsRealDifference() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V544-production-shared-string-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForProductionYearlessSharedStringDate(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-08-02")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .date)
        #expect(diff.registryValue == "8月2日")
        #expect(diff.obsidianValue == "2026.8.2")
        #expect(plan.existingCount == 0, "an unresolvable yearless date must never compact away as if it were confirmed equal")
    }

    // MARK: - Pulse: A. Registry explicit-2Hz vs Obsidian shorthand

    @Test("Pulse A. Registry '1000 (2Hz) /3000 (2Hz)' vs Obsidian '1000/3000' → no structured difference")
    func explicitDefaultHzAgreesWithShorthand() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO4", path: "lno4.md", pulse: "1000/3000")])

        #expect(plan.items.first { $0.batchId == "LNO4" } == nil)
        #expect(plan.existingCount == 1)
    }

    // MARK: - Pulse: B. Registry shorthand vs Obsidian shorthand (trivial)

    @Test("Pulse B. Registry '1000/3000' vs Obsidian '1000/3000' → no structured difference")
    func shorthandAgreesWithShorthand() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO5", path: "lno5.md", pulse: "1000/3000")])

        #expect(plan.items.first { $0.batchId == "LNO5" } == nil)
        #expect(plan.existingCount == 1)
    }

    // MARK: - Pulse: C. Genuine difference, canonical display on both sides

    @Test("Pulse C. Registry '1000 (2Hz) /3000 (2Hz)' vs Obsidian '1000/4000' → genuine difference, canonical display")
    func genuineDifferenceShowsCanonicalObsidianValue() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO4", path: "lno4.md", pulse: "1000/4000")])

        let item = try #require(plan.items.first { $0.batchId == "LNO4" })
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .pulseCount)
        #expect(diff.registryValue == "1000 (2Hz) /3000 (2Hz)")
        #expect(diff.obsidianValue == "1000 (2Hz) /4000 (2Hz)")
    }

    // MARK: - Pulse: D. Explicit non-default frequency is never normalized away

    @Test("Pulse D. Registry '1000 (5Hz) /3000 (2Hz)' vs Obsidian '1000/3000' → genuine difference (explicit 5 Hz != default)")
    func explicitNonDefaultHzIsNeverIgnored() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO6", path: "lno6.md", pulse: "1000/3000")])

        let item = try #require(plan.items.first { $0.batchId == "LNO6" })
        #expect(item.existingDifferences.count == 1)
        let diff = try #require(item.existingDifferences.first)
        #expect(diff.field == .pulseCount)
        #expect(diff.registryValue == "1000 (5Hz) /3000 (2Hz)")
        #expect(diff.obsidianValue == "1000 (2Hz) /3000 (2Hz)")
    }

    // MARK: - Pulse: E/F. Ready preview shows (and writes) the canonical value

    @Test("Pulse E/F. Ready preview for a new batch with shorthand pulse shows the canonical write value")
    func readyPreviewShowsCanonicalPulseValue() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let note = ObsidianNoteRecord(
            notePath: "lno7.md", batchId: "LNO7", identity: .unresolvedSample,
            growthClaims: [
                .growthDate: claim("2026-01-01", notePath: "lno7.md", rawKey: "date"),
                .pulseCount: claim("1000/3000", notePath: "lno7.md", rawKey: "pulse")
            ],
            rawFields: [claim("LNO", notePath: "lno7.md", rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: "lno7.md", rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil)]
        )
        let plan = try buildPlan(fixtureURL: url, notes: [note])

        let item = try #require(plan.items.first { $0.batchId == "LNO7" })
        #expect(item.action == .appendNewRow(targetSheet: "LNO"))
        #expect(item.columnValues["预打/生长次数"] == "1000 (2Hz) /3000 (2Hz)")
    }

    // MARK: - Pulse: G. False-positive removal increases existingCount

    @Test("Pulse G. Removing a false-positive pulse difference increases existingCount by exactly one")
    func falsePositiveRemovalIncreasesExistingCount() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let planWithConflict = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO4", path: "lno4.md", pulse: "1000/4000")])
        #expect(planWithConflict.existingCount == 0)
        #expect(planWithConflict.items.contains { $0.batchId == "LNO4" })

        let planAgreeing = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO4", path: "lno4.md", pulse: "1000/3000")])
        #expect(planAgreeing.existingCount == 1)
        #expect(!planAgreeing.items.contains { $0.batchId == "LNO4" })
    }
}
