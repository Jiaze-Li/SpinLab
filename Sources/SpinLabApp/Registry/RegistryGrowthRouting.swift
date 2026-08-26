import Foundation

// MARK: - Routing, field mapping, and date formatting rules for Phase 5A
//
// Every rule here is deliberately hard-coded to the sheets/columns Jack
// confirmed exist today (spec §5/§6) — no rule invents a target sheet or a
// column that isn't already present in the real Registry, and nothing here
// creates a sheet. An unroutable batch or an unmapped-but-required field is
// `.blocked`, never guessed.

enum RegistryGrowthRouting {
    /// Batch-id prefix → target sheet, for the material-family sheets whose
    /// prefix alone is unambiguous.
    static let prefixRoutes: [(prefix: String, sheet: String)] = [
        ("LNO", "LNO"),
        ("NCO", "NCO"),
        ("NNO", "NNO"),
        ("LSMO", "LSMO")
    ]

    /// PN-prefixed batches only route to PLD-N样品 when Obsidian evidence
    /// says the growth material is SRO — PN alone is not sufficient (spec §5).
    static let pnPrefix = "PN"
    static let pnSRORoutedSheet = "PLD-N样品"
    static let sroMaterialTokens: Set<String> = ["SRO", "SrRuO3", "SrRuO₃"]

    /// Resolve a target sheet name for a batch id, given whatever material
    /// evidence Obsidian offered. Returns nil (unroutable) rather than
    /// guessing when the batch matches no known prefix, or matches PN
    /// without confirmed SRO evidence.
    static func targetSheet(forBatchId batchId: String, materialEvidence: Set<String>) -> String? {
        let upper = batchId.uppercased()
        for route in prefixRoutes where upper.hasPrefix(route.prefix) {
            return route.sheet
        }
        if upper.hasPrefix(pnPrefix) {
            let normalizedEvidence = Set(materialEvidence.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            let hasSRO = normalizedEvidence.contains { evidence in
                sroMaterialTokens.contains { $0.caseInsensitiveCompare(evidence) == .orderedSame }
            }
            return hasSRO ? pnSRORoutedSheet : nil
        }
        return nil
    }

    /// Canonical token for a growth-material claim/cell value, for identity
    /// comparison (PR #169 repair pass 5 item 1) — reuses the confirmed SRO
    /// alias set above (the only existing normalization rule for growth
    /// material names) rather than inventing a new alias table. Any other
    /// material has no confirmed alias, so it canonicalizes to its own
    /// trimmed-uppercase form — a plain case/whitespace-insensitive compare,
    /// never a fresh guess at equivalence.
    static func canonicalGrowthMaterialToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if sroMaterialTokens.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "SRO"
        }
        return trimmed.uppercased()
    }

    /// The series an already-confirmed routing rule associates with
    /// `sheet`, used ONLY as `RegistrySheetProfile`'s fallback when a sheet
    /// has zero numbered rows to observe a series from (e.g. LSMO before
    /// its first import). Never a new mapping — reuses exactly the
    /// prefix/PN rules above.
    static func confirmedFallbackSeries(forSheet sheet: String) -> String? {
        if let route = prefixRoutes.first(where: { $0.sheet == sheet }) { return route.prefix }
        if sheet == pnSRORoutedSheet { return pnPrefix }
        return nil
    }

    // MARK: - Content-aware routing (batch-series evidence)
    //
    // `targetSheet(forBatchId:materialEvidence:)` above is a hard-coded
    // prefix/material rule table. It stays exactly as written and is reused
    // below as *fallback* evidence only — it never becomes the primary
    // signal. The primary signal is which routable sheet's *existing* batch
    // ids already carry the same series as the incoming batch, since the
    // real Registry's historical numbering is the more reliable source of
    // truth than a hard-coded prefix table (e.g. a PN series sheet is not
    // necessarily named after a material).

    /// Extracts the alphabetic batch-series prefix from a batch id by
    /// stripping its trailing numeric suffix, e.g. `"PN110"` → `"PN"`,
    /// `"LNO14"` → `"LNO"`. Thin wrapper over the one canonical
    /// series+number parser (`RegistryBatchIdentity`) — kept as its own
    /// entry point since it's part of this type's existing public surface.
    static func batchSeries(for batchId: String) -> String? {
        RegistryBatchIdentity.series(for: batchId)
    }

    /// One resolved routing outcome for `resolveTargetSheet`. Never a bare
    /// `String?` — callers need to distinguish "no evidence at all" from
    /// "evidence exists but is ambiguous/conflicting," which must each
    /// surface as a distinct blocking reason rather than collapsing into a
    /// single unroutable case.
    enum TargetResolution: Equatable {
        case resolved(sheet: String)
        case unroutable
        case ambiguous(batchSeries: String, candidateSheets: [String])
        case conflict(batchSeries: String, observedSheet: String, explicitSheet: String)
    }

    /// Resolves the target sheet for `batchId` using, in priority order:
    /// 1. observed series evidence — which of the already-`routableSheetNames`
    ///    sheets (per `profiles`, built once from the single Registry scan)
    ///    has this series among its `seriesObserved` (including reserved
    ///    ID-only rows, which contribute to that evidence just as much as
    ///    fully populated ones);
    /// 2. `targetSheet(forBatchId:materialEvidence:)` as fallback evidence,
    ///    only consulted when observed evidence is silent (zero candidates)
    ///    or, when observed evidence is unique, to detect a conflict.
    ///
    /// A sheet may legitimately observe more than one series (multi-series
    /// sheets are valid, e.g. a `PN110/SRO1` row contributes both `PN` and
    /// `SRO` to the same sheet's `seriesObserved`) — that alone never makes
    /// the sheet invalid. When more than one *sheet* observes the same
    /// series, candidacy is ambiguous and this fails closed rather than
    /// picking the first/majority sheet.
    ///
    /// `profiles` must be keyed by sheet name and only ever contain sheets
    /// this phase is allowed to write into — the caller is responsible for
    /// building it (via `RegistrySheetProfile.buildProfiles(from:)`) from
    /// `RegistryGrowthImportPlanner.routableSheetNames` snapshots. This
    /// function never expands that write boundary; it only decides *which*
    /// of those already-allowed sheets a given batch belongs to.
    static func resolveTargetSheet(
        batchId: String,
        profiles: [String: RegistrySheetProfile],
        materialEvidence: Set<String>
    ) -> TargetResolution {
        let explicit = targetSheet(forBatchId: batchId, materialEvidence: materialEvidence)

        guard let series = batchSeries(for: batchId) else {
            if let explicit { return .resolved(sheet: explicit) }
            return .unroutable
        }

        let candidateSheets = RegistryGrowthImportPlanner.routableSheetNames
            .filter { profiles[$0]?.seriesObserved.contains(series) == true }
            .sorted()

        switch candidateSheets.count {
        case 0:
            if let explicit {
                // A profile that exists but has no evidence at all for
                // `series` must fail closed rather than let the explicit
                // fallback bypass it. A sheet with no profile entry at all
                // (absent from the workbook) is a different, pre-existing
                // condition — surfaced downstream as `targetSheetNotFound`,
                // not here.
                if let profile = profiles[explicit], !profile.seriesObserved.contains(series) {
                    return .unroutable
                }
                return .resolved(sheet: explicit)
            }
            return .unroutable
        case 1:
            let observed = candidateSheets[0]
            if let explicit, explicit != observed {
                return .conflict(batchSeries: series, observedSheet: observed, explicitSheet: explicit)
            }
            return .resolved(sheet: observed)
        default:
            return .ambiguous(batchSeries: series, candidateSheets: candidateSheets)
        }
    }
}

/// Header-driven mapping from a semantic growth field to the Registry
/// column header text it is confirmed to correspond to (spec §6). The
/// planner looks up each target sheet's actual header row and only writes a
/// column whose header text is present in this table — it never assumes a
/// column position/index.
enum RegistryGrowthFieldMapping {
    enum Field: String, CaseIterable, Sendable {
        case batchId
        case date
        case substrate
        case material
        case growthTemperature
        case targetSubstrateDistance
        case oxygenPressure
        case laserEnergy
        case pulseCount
    }

    /// Confirmed Registry column headers this field may be written into.
    /// Header-driven, not position-driven — PLD-N样品's schema is not
    /// identical to the material-specific sheets (spec §6), so the planner
    /// resolves the actual column per-sheet via the sheet's own header row,
    /// using this table only to decide *which header text* to look for.
    static let confirmedHeaders: [Field: [String]] = [
        .batchId: ["编号"],
        .date: ["日期"],
        .substrate: ["substrate", "衬底"],
        .material: ["靶"],
        .growthTemperature: ["生长温度"],
        .targetSubstrateDistance: ["靶机距"],
        .oxygenPressure: ["氧压"],
        .laserEnergy: ["能量"],
        .pulseCount: ["预打/生长次数", "预打", "生长次数"]
    ]

    /// Fields that must be resolvable for an item to be executable at all.
    /// Spec §8: batchId, date, growth material/target, target sheet,
    /// substrate. (Target sheet is checked separately by the router, not a
    /// column-mapping concern.)
    static let requiredFields: Set<Field> = [.batchId, .date, .material, .substrate]

    /// Resolves the actual column header present on `headerRow` for `field`,
    /// trying each confirmed alias in order. Returns nil if none of the
    /// confirmed aliases exist as an actual header on this sheet.
    static func header(for field: Field, availableHeaders: Set<String>) -> String? {
        (confirmedHeaders[field] ?? []).first { availableHeaders.contains($0) }
    }

    /// Human-readable label for a growth field surfaced in warning/conflict
    /// text — never the internal `ObsidianGrowthField` case name. Reuses
    /// this table's own confirmed Registry headers as the canonical label
    /// wherever a corresponding `Field` case exists.
    static func humanLabel(for field: ObsidianGrowthField) -> String {
        switch field {
        case .growthDate: return confirmedHeaders[.date]?.first ?? "日期"
        case .growthTemperature: return confirmedHeaders[.growthTemperature]?.first ?? "生长温度"
        case .oxygenPressure: return confirmedHeaders[.oxygenPressure]?.first ?? "氧压"
        case .laserEnergy: return confirmedHeaders[.laserEnergy]?.first ?? "能量"
        case .pulseCount: return confirmedHeaders[.pulseCount]?.first ?? "预打/生长次数"
        case .targetSubstrateDistance: return confirmedHeaders[.targetSubstrateDistance]?.first ?? "靶机距"
        case .growthEnvironment: return "生长"
        }
    }

    /// Human-readable label for the growth-material field, which is not an
    /// `ObsidianGrowthField` case (spec: material/substrate have no Phase 4
    /// reconciliation — see `RegistryGrowthImportPlanner`).
    static let materialHumanLabel: String = confirmedHeaders[.material]?.first ?? "靶"

    /// Human-readable label for any `Field`, including `.batchId`/
    /// `.substrate` which have no `ObsidianGrowthField` counterpart (PR
    /// #169 cumulative-review repair item 3 — required-header blocking
    /// needs a label for every `requiredFields` entry, not just the ones
    /// `humanLabel(for: ObsidianGrowthField)` already covers).
    static func humanLabel(forField field: Field) -> String {
        confirmedHeaders[field]?.first ?? field.rawValue
    }
}

/// Deterministic, tested mapper from an Obsidian ISO date string
/// (`YYYY-MM-DD`) to the Registry's existing display date format. Spec §7:
/// never falls back to file mtime, "today", or a guess from the batch
/// number — an unparseable date is a hard blocking condition upstream, not
/// this mapper's problem to paper over.
enum RegistryGrowthDateMapper {
    /// Strict `YYYY-MM-DD` shape — exactly four year digits, two month
    /// digits, two day digits — followed by a real Gregorian calendar-date
    /// check (leap years included). Rejects `2026-2-2` (wrong digit width),
    /// `26-08-02` (wrong year width), and `2026-02-31`/`2026-02-29` on a
    /// non-leap year (not a real date) — never silently clamped or guessed.
    private static func parseISOComponents(_ iso: String) -> (year: Int, month: Int, day: Int)? {
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})$"#) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges == 4,
              let yearRange = Range(match.range(at: 1), in: trimmed),
              let monthRange = Range(match.range(at: 2), in: trimmed),
              let dayRange = Range(match.range(at: 3), in: trimmed),
              let year = Int(trimmed[yearRange]), let month = Int(trimmed[monthRange]), let day = Int(trimmed[dayRange]),
              isValidGregorianDate(year: year, month: month, day: day) else {
            return nil
        }
        return (year, month, day)
    }

    private static func isValidGregorianDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        let isLeapYear = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let daysInMonth = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...daysInMonth[month - 1]).contains(day)
    }

    /// The Registry's observed display format, matching what's already
    /// written into the 日期 column in the real workbook (e.g. "2026.8.18").
    /// Kept isolated here so it's the single place to adjust if a sheet is
    /// found to use a different display convention.
    static func registryDisplayString(fromISODate iso: String) -> String? {
        guard let c = parseISOComponents(iso) else { return nil }
        return "\(c.year).\(c.month).\(c.day)"
    }

    /// The obsidian side of an Existing semantic-date comparison —
    /// `yyyy-MM-dd`, zero-padded, so it can be compared directly against
    /// `semanticISODate(rawValue:isNumericCell:)` below. Never guesses a
    /// missing component; an unparseable ISO string returns nil.
    static func canonicalISODate(fromObsidianISODate iso: String) -> String? {
        guard let c = parseISOComponents(iso) else { return nil }
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    /// Parses the Registry's own textual "yyyy.M.d" display convention back
    /// to `yyyy-MM-dd` — the inverse of `registryDisplayString(fromISODate:)`.
    /// Only valid when the Registry cell is stored as text carrying its own
    /// full year (never a year-omitting display string like "8月2日").
    static func isoDate(fromRegistryDisplayString display: String) -> String? {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Converts an Excel date serial (the underlying numeric value of a
    /// numeric-typed date cell) to `yyyy-MM-dd`, using the standard Excel
    /// 1900 date system epoch (1899-12-30) — the conventional epoch that
    /// also reproduces Excel's fictitious 1900-02-29 leap-year bug, so it
    /// stays consistent with what Excel itself displays for a given serial.
    /// This is what lets a Registry cell whose *display* format omits the
    /// year (e.g. "8月2日" via a custom `m月d日` number format) still be
    /// compared by its true underlying date — the serial always carries the
    /// full year even when the display format hides it.
    static func isoDate(fromExcelSerial serial: Double) -> String? {
        guard serial.isFinite, serial > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        calendar.timeZone = utc
        guard let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)) else { return nil }
        guard let date = calendar.date(byAdding: .day, value: Int(serial), to: epoch) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Resolves a Registry date cell's semantic `yyyy-MM-dd`, given its raw
    /// text and whether the underlying cell is numerically typed. Numeric
    /// cells are read as Excel date serials (always carrying the full
    /// date, regardless of a year-omitting display format); text cells are
    /// parsed via the Registry's own "yyyy.M.d" convention (which always
    /// carries its own year). Returns nil — never guessed — for anything
    /// else, e.g. text that itself omits the year.
    static func semanticISODate(rawValue: String, isNumericCell: Bool) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isNumericCell, let serial = Double(trimmed) {
            return isoDate(fromExcelSerial: serial)
        }
        return isoDate(fromRegistryDisplayString: trimmed)
    }

    // MARK: - Partial date components (Phase 5.4.5 compatible-completion)

    /// A date known only up to its calendar components — `year` is nil when
    /// the source genuinely never carried one (the production Registry's
    /// year-omitting `M月D日` text convention), never inferred from context
    /// (no section-header/current-year guessing).
    struct PartialComponents: Equatable, Sendable {
        var year: Int?
        var month: Int
        var day: Int
    }

    /// Parses a Registry 日期 cell's raw text into partial components.
    /// Handles the full "yyyy.M.d" text convention (year known) and the
    /// real production year-omitting Chinese form "M月D日" (year nil) — the
    /// same shared-string shape observed on the LNO/PLD-N样品 sheets
    /// immediately below a "20XX年" section-header row, but never resolved
    /// against that header (spec: not interpreted as any specific year).
    /// Returns nil for anything else, including a numeric Excel serial cell
    /// (`semanticISODate` already resolves that case with full precision;
    /// callers needing that path should use it directly, not this parser).
    static func partialComponents(fromRegistryRawText raw: String) -> PartialComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = isoDate(fromRegistryDisplayString: trimmed), let c = parseISOComponents(iso) {
            return PartialComponents(year: c.year, month: c.month, day: c.day)
        }
        guard let match = firstDateMatch(pattern: #"^(\d{1,2})月(\d{1,2})日$"#, in: trimmed),
              let month = Int(match.0), let day = Int(match.1),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return PartialComponents(year: nil, month: month, day: day)
    }

    /// Partial components for an Obsidian ISO claim — always fully known
    /// (Obsidian growth claims always carry a year).
    static func partialComponents(fromObsidianISODate iso: String) -> PartialComponents? {
        guard let c = parseISOComponents(iso) else { return nil }
        return PartialComponents(year: c.year, month: c.month, day: c.day)
    }

    /// The canonical Registry write-facing string for a partial date —
    /// requires a known year (never invents one); nil otherwise.
    static func registryDisplayString(fromComponents c: PartialComponents) -> String? {
        guard let year = c.year else { return nil }
        return "\(year).\(c.month).\(c.day)"
    }

    private static func firstDateMatch(pattern: String, in string: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let result = regex.firstMatch(in: string, options: [], range: nsRange),
              result.numberOfRanges == 3,
              let r1 = Range(result.range(at: 1), in: string),
              let r2 = Range(result.range(at: 2), in: string) else { return nil }
        return (String(string[r1]), String(string[r2]))
    }
}
