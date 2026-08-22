import Foundation
import Testing
@testable import SpinLabApp

/// Focused coverage for the `RegistrySheetProfile` read-model layer added
/// on top of the ac697ef content-aware Registry Growth routing: one
/// Registry scan → `RegistrySheetSnapshot` → `RegistrySheetProfile` →
/// routing, so routing no longer rescans every sheet's rows per incoming
/// batch. See `V545RegistryGrowthContentAwareRoutingTests` for the
/// end-to-end (fixture-backed) routing behavior this layer must not
/// regress.
@Suite("V5.4.5 Registry sheet profile")
struct V545RegistrySheetProfileTests {
    private typealias Snapshot = RegistryGrowthImportPlanner.RegistrySheetSnapshot
    private typealias RowSnapshot = RegistryGrowthImportPlanner.RegistryRowSnapshot

    private func row(_ rowNumber: Int, _ batchId: String, reserved: Bool = false) -> RowSnapshot {
        RowSnapshot(rowNumber: rowNumber, batchId: batchId, isReserved: reserved)
    }

    // MARK: - A. Canonical numbered identity

    @Test("RegistryBatchIdentity.parse extracts series and numeric suffix")
    func canonicalIdentityParsing() {
        #expect(RegistryBatchIdentity.parse("PN110") == .init(series: "PN", number: 110))
        #expect(RegistryBatchIdentity.parse("LNO14") == .init(series: "LNO", number: 14))
        #expect(RegistryBatchIdentity.parse("NNO8") == .init(series: "NNO", number: 8))
        #expect(RegistryBatchIdentity.parse("LSMO1") == .init(series: "LSMO", number: 1))
    }

    @Test("RegistryBatchIdentity.parse fails deterministically for malformed or non-numbered ids")
    func malformedIdentityParsing() {
        #expect(RegistryBatchIdentity.parse("PN") == nil)
        #expect(RegistryBatchIdentity.parse("ABCXYZ") == nil)
        #expect(RegistryBatchIdentity.parse("110") == nil)
        #expect(RegistryBatchIdentity.parse("") == nil)
    }

    // MARK: - B. Single-series profile

    @Test("A sheet with one observed series produces series + rowsByNumber + maxNumber")
    func singleSeriesProfile() {
        let snapshot = Snapshot(
            sheetName: "LNO",
            availableHeaders: ["编号"],
            rows: [row(2, "LNO1"), row(3, "LNO2"), row(4, "LNO14")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: "LNO")
        #expect(profile.series == "LNO")
        #expect(Set(profile.rowsByNumber.keys) == [1, 2, 14])
        #expect(profile.maxNumber == 14)
    }

    // MARK: - C. Reserved rows contribute to rowsByNumber and maxNumber

    @Test("Reserved ID-only rows appear in rowsByNumber and count toward maxNumber")
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
        #expect(profile.series == "NNO")
        #expect(profile.maxNumber == 8)
        let reservedRow6 = try #require(profile.rowsByNumber[6]?.first)
        #expect(reservedRow6.isReserved)
    }

    // MARK: - E. Header-only (empty) sheet falls back to confirmed routing rule

    @Test("A header-only sheet has empty rowsByNumber and nil maxNumber, using only the confirmed fallback series")
    func headerOnlySheetProfile() {
        let snapshot = Snapshot(sheetName: "LSMO", availableHeaders: ["编号"], rows: [])
        let profile = RegistrySheetProfile.build(
            from: snapshot,
            confirmedFallbackSeries: RegistryGrowthRouting.confirmedFallbackSeries(forSheet: "LSMO")
        )
        #expect(profile.series == "LSMO")
        #expect(profile.rowsByNumber.isEmpty)
        #expect(profile.maxNumber == nil)
    }

    @Test("An empty sheet with no confirmed routing rule has a nil series")
    func emptySheetWithoutFallbackRuleHasNilSeries() {
        let snapshot = Snapshot(sheetName: "PLD-N样品", availableHeaders: ["编号"], rows: [])
        // PLD-N样品 has no prefix-route entry of its own (it's the PN
        // material-evidence special case, not a name-derived fallback), so
        // an empty PLD-N样品 sheet must not silently infer a series.
        let profile = RegistrySheetProfile.build(
            from: snapshot,
            confirmedFallbackSeries: RegistryGrowthRouting.confirmedFallbackSeries(forSheet: "NOT-A-CONFIRMED-SHEET")
        )
        #expect(profile.series == nil)
    }

    // MARK: - F. Observed series from existing rows (PLD-N样品 / PN)

    @Test("PLD-N样品's existing PN rows establish profile.series == PN")
    func observedPNSeriesFromExistingRows() {
        let snapshot = Snapshot(
            sheetName: "PLD-N样品",
            availableHeaders: ["编号"],
            rows: [row(2, "PN100"), row(3, "PN101"), row(4, "PN109")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: nil)
        #expect(profile.series == "PN")
        #expect(profile.maxNumber == 109)
    }

    // MARK: - G. Duplicate row safety

    @Test("Two rows landing on the same numbered slot are both retained, not collapsed")
    func duplicateRowsAreNotCollapsed() throws {
        let snapshot = Snapshot(
            sheetName: "LNO",
            availableHeaders: ["编号"],
            rows: [row(2, "LNO1"), row(3, "LNO1")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: "LNO")
        let slot = try #require(profile.rowsByNumber[1])
        #expect(slot.count == 2)
        #expect(Set(slot.map(\.rowNumber)) == [2, 3])
    }

    // MARK: - H. Mixed-series sheet fails closed

    @Test("A routable sheet with two different numbered series has a nil declared series (fail closed), though both series remain observed evidence")
    func mixedSeriesSheetFailsClosed() {
        let snapshot = Snapshot(
            sheetName: "NNO",
            availableHeaders: ["编号"],
            rows: [row(2, "NNO1"), row(3, "QX50")]
        )
        let profile = RegistrySheetProfile.build(from: snapshot, confirmedFallbackSeries: "NNO")
        // The sheet's own declared identity is ambiguous — never take the
        // first/majority series as a silent choice.
        #expect(profile.series == nil)
        // Rows are still indexed (no data loss), and both series remain
        // recorded in `seriesObserved` — diagnostic evidence only, never a
        // basis for routing (a mixed sheet is never a valid NEW/FILL
        // candidate for either series — see
        // V545RegistryGrowthContentAwareRoutingTests' "Mixed-*" tests).
        #expect(profile.seriesObserved == ["NNO", "QX"])
        #expect(profile.rowsByNumber[1]?.first?.batchId == "NNO1")
        #expect(profile.rowsByNumber[50]?.first?.batchId == "QX50")
    }

    @Test("resolveTargetSheet candidacy is decided from profile.series, never from seriesObserved")
    func routingCandidacyUsesDeclaredSeriesNotObserved() {
        // NNO mixes NNO+QX rows (declared series nil, but QX is still
        // present in seriesObserved). If candidacy were ever decided from
        // seriesObserved, an incoming QX batch would wrongly resolve to
        // NNO. It must not.
        let mixedSnapshot = Snapshot(
            sheetName: "NNO",
            availableHeaders: ["编号"],
            rows: [row(2, "NNO1"), row(3, "QX50")]
        )
        let mixedProfile = RegistrySheetProfile.build(from: mixedSnapshot, confirmedFallbackSeries: "NNO")
        #expect(mixedProfile.seriesObserved.contains("QX"))
        #expect(mixedProfile.series == nil)

        let profiles = ["NNO": mixedProfile]
        let resolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "QX51", profiles: profiles, materialEvidence: [])
        #expect(resolution == .unroutable)
    }

    // MARK: - buildProfiles: one profile per scanned sheet, purely derived

    @Test("buildProfiles derives one profile per snapshot without a second workbook scan")
    func buildProfilesDerivesOnePerSheet() {
        let snapshots: [String: Snapshot] = [
            "LNO": Snapshot(sheetName: "LNO", availableHeaders: ["编号"], rows: [row(2, "LNO1"), row(3, "LNO14")]),
            "LSMO": Snapshot(sheetName: "LSMO", availableHeaders: ["编号"], rows: [])
        ]
        let profiles = RegistrySheetProfile.buildProfiles(from: snapshots)
        #expect(profiles["LNO"]?.series == "LNO")
        #expect(profiles["LNO"]?.maxNumber == 14)
        #expect(profiles["LSMO"]?.series == "LSMO")
        #expect(profiles["LSMO"]?.maxNumber == nil)
    }
}
