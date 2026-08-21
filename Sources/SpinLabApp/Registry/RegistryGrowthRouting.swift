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
