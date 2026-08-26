import Foundation

/// Canonical single-TOKEN decomposition into series + numeric suffix, e.g.
/// `"PN110"` → series `"PN"`, number `110`. This is the ONE grammar for a
/// human identifier token — `RegistryIdentifierCell` (below) is the only
/// place that splits a Registry "编号" cell into tokens before handing each
/// one to this parser; there is no second implementation of "series" or
/// "number" anywhere else.
enum RegistryBatchIdentity {
    struct Parsed: Equatable {
        let series: String
        let number: Int
    }

    /// `"PN110"` → series `"PN"`, number `110`. Strict grammar: letters, then
    /// digits — nothing else. A bare letters-only id (no trailing digits), a
    /// bare number (no alphabetic prefix), or a prefix that contains any
    /// non-letter character (`"PN@110"`, `"PN11X9"`, `"A_B1"`, `"???1"`) is
    /// not a valid human identifier and returns nil rather than guessing.
    static func parse(_ batchId: String) -> Parsed? {
        let upper = batchId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }
        let characters = Array(upper)
        var end = characters.count
        while end > 0, characters[end - 1].isNumber { end -= 1 }
        guard end > 0, end < characters.count else { return nil }
        let prefix = String(characters[0..<end])
        guard prefix.allSatisfy({ $0.isLetter }), let number = Int(String(characters[end...])) else { return nil }
        return Parsed(series: prefix, number: number)
    }

    static func series(for batchId: String) -> String? {
        parse(batchId)?.series
    }
}

/// One human identifier a Registry cell may name — a query/matching
/// identity, never the future machine identity. See the "Identity
/// direction" note at the bottom of this file.
struct HumanIdentifier: Sendable {
    /// The trimmed token as it appeared in the cell (e.g. `"SRO1"`).
    /// Representation/provenance only — never part of identity. Two
    /// `HumanIdentifier`s with the same `series`+`number` but different
    /// `raw` spellings compare and hash equal (see `Equatable`/`Hashable`
    /// below).
    var raw: String
    var series: String
    var number: Int
}

/// Domain identity is `series`+`number` only — `raw` is representation, not
/// identity, so it is deliberately excluded from both conformances below
/// (never a synthesized `Hashable` that would fold `raw` into equality).
extension HumanIdentifier: Equatable {
    static func == (lhs: HumanIdentifier, rhs: HumanIdentifier) -> Bool {
        lhs.series == rhs.series && lhs.number == rhs.number
    }
}

extension HumanIdentifier: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(series)
        hasher.combine(number)
    }
}

/// One malformed token found inside a Registry identifier cell, kept as an
/// explicit diagnostic rather than silently dropped or folded into a fake
/// series.
struct MalformedIdentifierRow: Hashable, Sendable {
    var rowNumber: Int
    var malformedTokens: [String]
}

/// Parses a Registry "编号" cell into 1..N human identifiers. `"/"` is the
/// ONLY identifier separator, and this is the ONE place that splits on it —
/// no other file re-implements `contains("/")` / `split("/")` / prefix
/// parsing for Registry identifier cells.
///
/// `"PN110/SRO1"` → identifiers `[PN110, SRO1]` referring to the same
/// Registry row. A token that doesn't match the `RegistryBatchIdentity`
/// grammar is reported in `malformedTokens`, never folded into a fake
/// series (e.g. `"PN110/???"` yields identifier `PN110` plus malformed
/// token `"???"` — never a series like `"PN110/PN"`).
///
/// Splits with `omittingEmptySubsequences: false` so an empty fragment
/// (`"PN110/"`, `"/PN110"`, `"PN110//SRO1"`) is never silently discarded —
/// it is reported as an explicit (empty-string) malformed token instead,
/// and — like every other malformed token — never contributes a routing
/// series.
enum RegistryIdentifierCell {
    struct Parsed: Equatable {
        var identifiers: [HumanIdentifier]
        var malformedTokens: [String]
    }

    static func parse(_ cell: String) -> Parsed {
        let tokens = cell
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var identifiers: [HumanIdentifier] = []
        var malformedTokens: [String] = []
        for token in tokens {
            guard !token.isEmpty else {
                malformedTokens.append(token)
                continue
            }
            if let parsed = RegistryBatchIdentity.parse(token) {
                identifiers.append(HumanIdentifier(raw: token, series: parsed.series, number: parsed.number))
            } else {
                malformedTokens.append(token)
            }
        }
        return Parsed(identifiers: identifiers, malformedTokens: malformedTokens)
    }
}

/// A pure, rebuildable per-sheet routing/numbering projection of a
/// `RegistryGrowthImportPlanner.RegistrySheetSnapshot`. Built once per
/// Registry scan, never a second source of truth — reconstructing this from
/// the same snapshot always yields the same profile.
struct RegistrySheetProfile {
    /// Every human-identifier series observed among this sheet's rows
    /// (reserved ID-only rows count same as populated ones; a row whose
    /// cell names more than one identifier, e.g. `"PN110/SRO1"`,
    /// contributes every one of its series). A sheet legitimately
    /// contains more than one series — "one sheet = one series" is not an
    /// invariant of this model — so `seriesObserved` is itself the
    /// routing-candidacy evidence, not merely diagnostic.
    var seriesObserved: Set<String> = []

    /// Rows indexed by series, then by numeric suffix — the identifier-
    /// aware replacement for a single `rowsByNumber[number]` table, which
    /// is unsafe once two different series can both land on the same
    /// number (e.g. `PN1` and `SRO1`). The value is an array, never a bare
    /// row, so two rows landing on the same `(series, number)` slot are
    /// preserved rather than one silently overwriting the other —
    /// duplicate detection reads the array's count. A row with identifiers
    /// `[PN110, SRO1]` is reachable both via `rowsBySeries["PN"][110]` and
    /// `rowsBySeries["SRO"][1]` — the same row object, never two rows.
    var rowsBySeries: [String: [Int: [RegistryGrowthImportPlanner.RegistryRowSnapshot]]] = [:]

    /// Rows whose identifier cell contained at least one token that does
    /// not parse under `RegistryBatchIdentity` (e.g. `"PN110/???"`) —
    /// kept as an explicit diagnostic so malformed Registry state is never
    /// silently swallowed for the sake of a routing/fill decision.
    var malformedRows: [MalformedIdentifierRow] = []

    /// Highest numeric suffix observed for `series` on this sheet
    /// (reserved rows count same as populated ones). Nil if `series` was
    /// never observed on this sheet. A structural fact only — carries no
    /// mutation or numbering-allocation semantics (never a sync watermark).
    func maxNumber(forSeries series: String) -> Int? {
        rowsBySeries[series]?.keys.max()
    }

    /// Builds a profile from one already-scanned sheet snapshot.
    /// `confirmedFallbackSeries` is only consulted when the sheet has zero
    /// identifiers at all (e.g. a header-only sheet like LSMO before its
    /// first import) — it must come from an already-confirmed routing rule
    /// (`RegistryGrowthRouting.confirmedFallbackSeries(forSheet:)`), never a
    /// new guess.
    static func build(
        from snapshot: RegistryGrowthImportPlanner.RegistrySheetSnapshot,
        confirmedFallbackSeries: String?
    ) -> RegistrySheetProfile {
        var rowsBySeries: [String: [Int: [RegistryGrowthImportPlanner.RegistryRowSnapshot]]] = [:]
        var observedSeries: Set<String> = []
        var malformedRows: [MalformedIdentifierRow] = []

        for row in snapshot.rows {
            for identifier in row.identifiers {
                observedSeries.insert(identifier.series)
                rowsBySeries[identifier.series, default: [:]][identifier.number, default: []].append(row)
            }
            if !row.malformedTokens.isEmpty {
                malformedRows.append(MalformedIdentifierRow(rowNumber: row.rowNumber, malformedTokens: row.malformedTokens))
            }
        }

        if observedSeries.isEmpty, let confirmedFallbackSeries {
            observedSeries.insert(confirmedFallbackSeries)
        }

        return RegistrySheetProfile(seriesObserved: observedSeries, rowsBySeries: rowsBySeries, malformedRows: malformedRows)
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

// MARK: - Identity direction (future phases, not implemented here)
//
// 1. Human identifiers are NOT machine identity. A physical Sample may have
//    multiple human identifiers (e.g. `PN110` and `SRO1` referring to the
//    same object).
// 2. The current `LibrarySample.id`/`sampleKey` is a legacy storage/
//    reconciliation key — not the final machine identity model.
// 3. Future model: `Sample { machineUID, humanIdentifiers[], semanticDescriptor,
//    legacy storageKey during migration }`. `machineUID` must be opaque,
//    stable, and persisted — never regenerated on every parse.
// 4. Future UID assignment belongs at the parsed Registry → persisted
//    Library reconciliation boundary (existing Sample → preserve
//    machineUID; new Sample → assign one), never inside
//    `LibraryRegistryParser`.
// 5. Migration is additive: Phase 1 (this commit) is `humanIdentifiers[]`
//    only; Phase 2 adds persisted `machineUID` alongside the legacy
//    storageKey; Phase 3 migrates logical references/diff/UI selection to
//    UID; Phase 4 migrates filesystem/drawer paths only if actually needed.
//    The `HumanIdentifier`/`RegistryIdentifierCell` layer introduced here
//    must survive all of those phases unchanged.
