import Foundation

/// Canonical batch-id decomposition into series + numeric suffix. This is
/// the ONE parser used by `RegistrySheetProfile` construction, routing, and
/// rowsByNumber lookup — there is no second implementation of "series" or
/// "number" anywhere else.
enum RegistryBatchIdentity {
    struct Parsed: Equatable {
        let series: String
        let number: Int
    }

    /// `"PN110"` → series `"PN"`, number `110`. Deterministic only: a bare
    /// letters-only id (no trailing digits) or a bare number (no alphabetic
    /// prefix) is not a numbered batch identity and returns nil rather than
    /// guessing.
    static func parse(_ batchId: String) -> Parsed? {
        let upper = batchId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }
        let characters = Array(upper)
        var end = characters.count
        while end > 0, characters[end - 1].isNumber { end -= 1 }
        guard end > 0, end < characters.count else { return nil }
        var prefix = String(characters[0..<end])
        while let last = prefix.last, last == "-" || last == "_" || last == " " {
            prefix.removeLast()
        }
        guard !prefix.isEmpty, let number = Int(String(characters[end...])) else { return nil }
        return Parsed(series: prefix, number: number)
    }

    static func series(for batchId: String) -> String? {
        parse(batchId)?.series
    }
}

/// A pure, rebuildable per-sheet routing/numbering projection of a
/// `RegistryGrowthImportPlanner.RegistrySheetSnapshot`. Built once per
/// Registry scan, never a second source of truth — reconstructing this from
/// the same snapshot always yields the same profile.
struct RegistrySheetProfile {
    /// Every batch series observed among this sheet's rows (reserved
    /// ID-only rows count same as populated ones). Diagnostic/raw evidence
    /// only — it explains *why* `series` below is nil for a mixed sheet
    /// (`seriesObserved.count > 1`), and is never itself the basis for a
    /// routing decision. `RegistryGrowthRouting.resolveTargetSheet` decides
    /// candidacy from `series`, not from this set: a sheet is never chosen
    /// as a NEW/FILL target for a series just because it happens to
    /// contain one stray row of that series.
    var seriesObserved: Set<String> = []

    /// The single numbered batch series this sheet is declared to
    /// represent (e.g. `"LNO"`, `"NNO"`, `"PN"`) — the "one sheet = one
    /// series" model. Nil when the sheet's rows carry more than one series
    /// (fail-closed: never take the first/majority) or when it has no
    /// numbered rows and no already-confirmed routing rule names it. This
    /// is a declarative fact for reporting/empty-sheet classification, not
    /// what routing candidacy is decided from.
    var series: String?

    /// Registry rows keyed by their batch id's numeric suffix. The value is
    /// an array, never a bare row, so two rows landing on the same key are
    /// preserved rather than one silently overwriting the other — duplicate
    /// detection reads the array's count.
    var rowsByNumber: [Int: [RegistryGrowthImportPlanner.RegistryRowSnapshot]] = [:]

    /// Highest numeric suffix represented by any row on this sheet
    /// (reserved rows count same as populated ones). Nil for a
    /// header-only/empty sheet. A structural fact only — carries no
    /// mutation or numbering-allocation semantics.
    var maxNumber: Int? { rowsByNumber.keys.max() }

    /// Builds a profile from one already-scanned sheet snapshot.
    /// `confirmedFallbackSeries` is only consulted when the sheet has zero
    /// numbered rows (e.g. a header-only sheet like LSMO before its first
    /// import) — it must come from an already-confirmed routing rule
    /// (`RegistryGrowthRouting.confirmedFallbackSeries(forSheet:)`), never a
    /// new guess.
    static func build(
        from snapshot: RegistryGrowthImportPlanner.RegistrySheetSnapshot,
        confirmedFallbackSeries: String?
    ) -> RegistrySheetProfile {
        var rowsByNumber: [Int: [RegistryGrowthImportPlanner.RegistryRowSnapshot]] = [:]
        var observedSeries: Set<String> = []
        for row in snapshot.rows {
            guard let parsed = RegistryBatchIdentity.parse(row.batchId) else { continue }
            observedSeries.insert(parsed.series)
            rowsByNumber[parsed.number, default: []].append(row)
        }

        let series: String?
        switch observedSeries.count {
        case 0:
            series = confirmedFallbackSeries
        case 1:
            series = observedSeries.first
        default:
            // Mixed series inside one routable sheet: the sheet's own
            // declared identity fails closed. Never take the first/majority.
            series = nil
        }

        return RegistrySheetProfile(seriesObserved: observedSeries, series: series, rowsByNumber: rowsByNumber)
    }

    /// Builds one profile per already-scanned sheet. Pure and read-only —
    /// derives entirely from the single `scanRoutableSheets` scan, never
    /// reopens the workbook.
    static func buildProfiles(
        from snapshots: [String: RegistryGrowthImportPlanner.RegistrySheetSnapshot]
    ) -> [String: RegistrySheetProfile] {
        var profiles: [String: RegistrySheetProfile] = [:]
        for (sheetName, snapshot) in snapshots {
            let fallback = RegistryGrowthRouting.confirmedFallbackSeries(forSheet: sheetName)
            profiles[sheetName] = build(from: snapshot, confirmedFallbackSeries: fallback)
        }
        return profiles
    }
}
