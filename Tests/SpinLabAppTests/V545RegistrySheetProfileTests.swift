import Foundation
import Testing
@testable import SpinLabApp

/// Focused coverage for the `RegistrySheetProfile` / `HumanIdentifier` read-
/// model layer added on top of the ac697ef content-aware Registry Growth
/// routing. A Registry "编号" cell may name 1..N human identifiers
/// (`"PN110/SRO1"`) that all point to the same Registry row — "one sheet =
/// one series" is no longer an invariant; multi-series sheets are valid. See
/// `V545RegistryGrowthContentAwareRoutingTests` for the end-to-end
/// (fixture-backed) routing behavior this layer must not regress.
@Suite("V5.4.5 Registry sheet profile")
struct V545RegistrySheetProfileTests {
    private typealias Snapshot = RegistryGrowthImportPlanner.RegistrySheetSnapshot
    private typealias RowSnapshot = RegistryGrowthImportPlanner.RegistryRowSnapshot

    private func row(_ rowNumber: Int, _ batchId: String, reserved: Bool = false) -> RowSnapshot {
        let parsed = RegistryIdentifierCell.parse(batchId)
        return RowSnapshot(rowNumber: rowNumber, batchId: batchId, isReserved: reserved, identifiers: parsed.identifiers, malformedTokens: parsed.malformedTokens)
    }

    // MARK: - A/B/C. Canonical single-token identity

    @Test("RegistryBatchIdentity.parse extracts series and numeric suffix")
    func canonicalIdentityParsing() {
        #expect(RegistryBatchIdentity.parse("PN110") == .init(series: "PN", number: 110))
        #expect(RegistryBatchIdentity.parse("LNO14") == .init(series: "LNO", number: 14))
        #expect(RegistryBatchIdentity.parse("NNO8") == .init(series: "NNO", number: 8))
        #expect(RegistryBatchIdentity.parse("LSMO1") == .init(series: "LSMO", number: 1))
        #expect(RegistryBatchIdentity.parse("S9") == .init(series: "S", number: 9))
    }

    @Test("RegistryBatchIdentity.parse fails deterministically for malformed or non-numbered ids")
    func malformedIdentityParsing() {
        #expect(RegistryBatchIdentity.parse("PN") == nil)
        #expect(RegistryBatchIdentity.parse("ABCXYZ") == nil)
        #expect(RegistryBatchIdentity.parse("110") == nil)
        #expect(RegistryBatchIdentity.parse("") == nil)
    }

    // MARK: - A. Single identifier cell

    @Test("A. \"PN110\" parses to one identifier PN/110")
    func singleIdentifierCell() {
        let parsed = RegistryIdentifierCell.parse("PN110")
        #expect(parsed.identifiers == [HumanIdentifier(raw: "PN110", series: "PN", number: 110)])
        #expect(parsed.malformedTokens.isEmpty)
    }

    // MARK: - B. Composite identifier cell

    @Test("B. \"PN110/SRO1\" parses to two identifiers PN/110 and SRO/1")
    func compositeIdentifierCell() {
        let parsed = RegistryIdentifierCell.parse("PN110/SRO1")
        #expect(parsed.identifiers == [
            HumanIdentifier(raw: "PN110", series: "PN", number: 110),
            HumanIdentifier(raw: "SRO1", series: "SRO", number: 1)
        ])
        #expect(parsed.malformedTokens.isEmpty)
    }

    // MARK: - C. Short series tokens

    @Test("C. \"PN11/S9\" parses to PN/11 and S/9")
    func shortSeriesIdentifierCell() {
        let parsed = RegistryIdentifierCell.parse("PN11/S9")
        #expect(parsed.identifiers == [
            HumanIdentifier(raw: "PN11", series: "PN", number: 11),
            HumanIdentifier(raw: "S9", series: "S", number: 9)
        ])
    }

    // MARK: - D. Whitespace around tokens/separator

    @Test("D. Whitespace around tokens and the separator is trimmed")
    func whitespaceTolerantIdentifierCell() {
        let parsed = RegistryIdentifierCell.parse(" PN110 / SRO1 ")
        #expect(parsed.identifiers == [
            HumanIdentifier(raw: "PN110", series: "PN", number: 110),
            HumanIdentifier(raw: "SRO1", series: "SRO", number: 1)
        ])
        #expect(parsed.malformedTokens.isEmpty)
    }

    // MARK: - E. Malformed token never fabricates a fake series

    @Test("E. A malformed token is reported as a diagnostic, never folded into a fake series")
    func malformedTokenDoesNotFabricateSeries() {
        let parsed = RegistryIdentifierCell.parse("PN110/???")
        #expect(parsed.identifiers == [HumanIdentifier(raw: "PN110", series: "PN", number: 110)])
        #expect(parsed.malformedTokens == ["???"])
        // Never a series like "PN110/PN" or "PN110/???".
        #expect(!parsed.identifiers.contains { $0.series.contains("/") })
    }

    // MARK: - Single/composite profile construction

    @Test("A sheet with one observed series produces seriesObserved + rowsBySeries + maxNumber(forSeries:)")
    func singleSeriesProfile() {
        let snapshot = Snapshot(
            sheetName: "LNO",
            availableHeaders: ["编号"],
            rows: [row(2, "LNO1"), row(3, "LNO2"), row(4, "LNO14")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: "LNO")
        #expect(profile.seriesObserved == ["LNO"])
        #expect(Set(profile.rowsBySeries["LNO"]?.keys ?? [:].keys) == [1, 2, 14])
        #expect(profile.maxNumber(forSeries: "LNO") == 14)
    }

    @Test("Reserved ID-only rows appear in rowsBySeries and count toward maxNumber")
    func reservedRowsCountTowardMaxNumber() throws {
        let snapshot = Snapshot(
            sheetName: "NNO",
            availableHeaders: ["编号"],
            rows: [
                row(2, "NNO1"), row(3, "NNO2"), row(4, "NNO3"),
                row(5, "NNO4", reserved: true), row(6, "NNO5", reserved: true),
                row(7, "NNO6", reserved: true), row(8, "NNO7", reserved: true),
                row(9, "NNO8", reserved: true)
            ]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: "NNO")
        #expect(profile.seriesObserved == ["NNO"])
        #expect(profile.maxNumber(forSeries: "NNO") == 8)
        let reservedRow6 = try #require(profile.rowsBySeries["NNO"]?[6]?.first)
        #expect(reservedRow6.isReserved)
    }

    @Test("A header-only sheet has empty rowsBySeries and nil maxNumber, using only the confirmed fallback series")
    func headerOnlySheetProfile() {
        let snapshot = Snapshot(sheetName: "LSMO", availableHeaders: ["编号"], rows: [])
        let profile = RegistrySheetProfile.build(
            from: snapshot,
            confirmedFallbackSeries: RegistryGrowthRouting.confirmedFallbackSeries(forSheet: "LSMO")
        )
        #expect(profile.seriesObserved == ["LSMO"])
        #expect(profile.rowsBySeries.isEmpty)
        #expect(profile.maxNumber(forSeries: "LSMO") == nil)
    }

    @Test("An empty sheet with no confirmed routing rule has empty seriesObserved")
    func emptySheetWithoutFallbackRuleHasNoSeries() {
        let snapshot = Snapshot(sheetName: "PLD-N样品", availableHeaders: ["编号"], rows: [])
        let profile = RegistrySheetProfile.build(
            from: snapshot,
            confirmedFallbackSeries: RegistryGrowthRouting.confirmedFallbackSeries(forSheet: "NOT-A-CONFIRMED-SHEET")
        )
        #expect(profile.seriesObserved.isEmpty)
    }

    @Test("PLD-N样品's existing PN rows establish PN as observed series")
    func observedPNSeriesFromExistingRows() {
        let snapshot = Snapshot(
            sheetName: "PLD-N样品",
            availableHeaders: ["编号"],
            rows: [row(2, "PN100"), row(3, "PN101"), row(4, "PN109")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: nil)
        #expect(profile.seriesObserved == ["PN"])
        #expect(profile.maxNumber(forSeries: "PN") == 109)
    }

    @Test("Two rows landing on the same series+number slot are both retained, not collapsed")
    func duplicateRowsAreNotCollapsed() throws {
        let snapshot = Snapshot(
            sheetName: "LNO",
            availableHeaders: ["编号"],
            rows: [row(2, "LNO1"), row(3, "LNO1")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: "LNO")
        let slot = try #require(profile.rowsBySeries["LNO"]?[1])
        #expect(slot.count == 2)
        #expect(Set(slot.map(\.rowNumber)) == [2, 3])
    }

    // MARK: - F. Multi-series sheet is a VALID profile

    @Test("F. A sheet with PN110/SRO1 and PN111/SRO2 is a valid multi-series profile {PN, SRO}, not invalid/mixed")
    func multiSeriesSheetIsValid() {
        let snapshot = Snapshot(
            sheetName: "PLD-N样品",
            availableHeaders: ["编号"],
            rows: [row(2, "PN110/SRO1"), row(3, "PN111/SRO2")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: nil)
        #expect(profile.seriesObserved == ["PN", "SRO"])
        #expect(profile.rowsBySeries["PN"]?[110]?.first?.rowNumber == 2)
        #expect(profile.rowsBySeries["SRO"]?[1]?.first?.rowNumber == 2)
        #expect(profile.rowsBySeries["PN"]?[111]?.first?.rowNumber == 3)
        #expect(profile.rowsBySeries["SRO"]?[2]?.first?.rowNumber == 3)
        #expect(profile.malformedRows.isEmpty)
        // Both PN and SRO must be valid routing candidacy evidence for this
        // sheet — see routingCandidacyIncludesEveryObservedSeries below and
        // V545RegistryGrowthContentAwareRoutingTests' multi-series tests.
    }

    @Test("A row with a malformed token still contributes its valid identifier, plus an explicit diagnostic")
    func malformedTokenRowStillIndexesValidIdentifier() {
        let snapshot = Snapshot(
            sheetName: "PLD-N样品",
            availableHeaders: ["编号"],
            rows: [row(2, "PN110/???")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: nil)
        #expect(profile.seriesObserved == ["PN"])
        #expect(profile.rowsBySeries["PN"]?[110]?.first?.rowNumber == 2)
        #expect(profile.malformedRows == [MalformedIdentifierRow(rowNumber: 2, malformedTokens: ["???"])])
    }

    @Test("resolveTargetSheet candidacy considers every series a multi-series sheet observes")
    func routingCandidacyIncludesEveryObservedSeries() {
        let snapshot = Snapshot(
            sheetName: "PLD-N样品",
            availableHeaders: ["编号"],
            rows: [row(2, "PN110/SRO1"), row(3, "PN111/SRO2")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: nil)
        let profiles = ["PLD-N样品": profile]

        let pnResolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "PN114", profiles: profiles, materialEvidence: ["SRO"])
        #expect(pnResolution == .resolved(sheet: "PLD-N样品"))

        let sroResolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "SRO3", profiles: profiles, materialEvidence: [])
        #expect(sroResolution == .resolved(sheet: "PLD-N样品"))
    }

    // MARK: - buildProfiles: one profile per scanned sheet, purely derived

    @Test("buildProfiles derives one profile per snapshot without a second workbook scan")
    func buildProfilesDerivesOnePerSheet() {
        let snapshots: [String: Snapshot] = [
            "LNO": Snapshot(sheetName: "LNO", availableHeaders: ["编号"], rows: [row(2, "LNO1"), row(3, "LNO14")]),
            "LSMO": Snapshot(sheetName: "LSMO", availableHeaders: ["编号"], rows: [])
        ]
        let profiles = RegistrySheetProfile.buildProfiles(from: snapshots)
        #expect(profiles["LNO"]?.seriesObserved == ["LNO"])
        #expect(profiles["LNO"]?.maxNumber(forSeries: "LNO") == 14)
        #expect(profiles["LSMO"]?.seriesObserved == ["LSMO"])
        #expect(profiles["LSMO"]?.maxNumber(forSeries: "LSMO") == nil)
    }

    // MARK: - M. Historical hole is unaffected by maxNumber semantics

    @Test("M. maxNumber is a structural fact only, never a sync watermark: a hole below it stays a hole")
    func historicalHoleIsNotMaskedByMaxNumber() {
        // Registry has PN108, PN109, PN111 — PN110 was never written. Even
        // though maxNumber(forSeries: "PN") == 111, PN110 must not be
        // treated as already-covered by that watermark; exact-match lookup
        // (identifier-based, not a numeric-range check) is what decides
        // Existing vs New, and PN110 has no row at all.
        let snapshot = Snapshot(
            sheetName: "PLD-N样品",
            availableHeaders: ["编号"],
            rows: [row(2, "PN108"), row(3, "PN109"), row(4, "PN111")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: nil)
        #expect(profile.maxNumber(forSeries: "PN") == 111)
        #expect(profile.rowsBySeries["PN"]?[110] == nil)
    }
}
