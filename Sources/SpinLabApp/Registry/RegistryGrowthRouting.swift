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
    ///    has at least one row of the same series in its `seriesObserved`
    ///    (including reserved ID-only rows, which count as evidence just as
    ///    much as fully populated ones);
    /// 2. `targetSheet(forBatchId:materialEvidence:)` as fallback evidence,
    ///    only consulted when observed evidence is silent (zero candidates)
    ///    or, when observed evidence is unique, to detect a conflict.
    ///
    /// `profiles` must be keyed by sheet name and only ever contain sheets
    /// this phase is allowed to write into — the caller is responsible for
    /// building it (via `RegistrySheetProfile.buildProfiles(from:)`) from
    /// `RegistryGrowthImportPlanner.routableSheetNames` snapshots. This
    /// function never expands that write boundary; it only decides *which*
    /// of those already-allowed sheets a given batch belongs to. Candidacy
    /// is decided from `seriesObserved` (raw row-level evidence), not from
    /// `profile.series` — a sheet may legitimately carry a stray row of
    /// another series and still be correct evidence for that series.
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
            .filter { profiles[$0]?.seriesObserved.contains(series) ?? false }
            .sorted()

        switch candidateSheets.count {
        case 0:
            if let explicit { return .resolved(sheet: explicit) }
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
}

/// Deterministic, tested mapper from an Obsidian ISO date string
/// (`YYYY-MM-DD`) to the Registry's existing display date format. Spec §7:
/// never falls back to file mtime, "today", or a guess from the batch
/// number — an unparseable date is a hard blocking condition upstream, not
/// this mapper's problem to paper over.
enum RegistryGrowthDateMapper {
    /// The Registry's observed display format, matching what's already
    /// written into the 日期 column in the real workbook (e.g. "2026.8.18").
    /// Kept isolated here so it's the single place to adjust if a sheet is
    /// found to use a different display convention.
    static func registryDisplayString(fromISODate iso: String) -> String? {
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return "\(year).\(month).\(day)"
    }
}
