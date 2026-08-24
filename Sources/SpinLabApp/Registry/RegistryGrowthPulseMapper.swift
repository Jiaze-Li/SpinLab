import Foundation

/// Canonical Registry-facing interpretation and formatting for the
/// "预打/生长次数" (pre-ablation / growth pulse count) column — Phase 5.4.4.
/// Confirmed domain rule: an omitted pulse frequency means the confirmed
/// default of 2 Hz. This is the ONE place that owns that rule — the Ready
/// write-facing mapping (`RegistryGrowthImportPlanner`), the actual
/// candidate workbook write (`RegistryGrowthMutationService`, which writes
/// `RegistryGrowthImportItem.columnValues` verbatim), and the Existing
/// comparison/display all go through this mapper rather than each
/// repeating ad hoc regex/string handling.
enum RegistryGrowthPulseMapper {
    static let defaultHz = 2

    struct Pulse: Equatable {
        var preCount: Int
        var preHz: Int
        var growthCount: Int
        var growthHz: Int
    }

    /// Parses a pulse string in either shorthand ("1000/3000") or explicit
    /// Registry notation ("1000 (2Hz) /3000 (2Hz)") form. An omitted
    /// `(NHz)` group defaults to `defaultHz`; an explicit one is preserved
    /// verbatim, never overwritten. Returns nil for anything that doesn't
    /// match this shape — never guessed past (spec: "if an unfamiliar pulse
    /// string cannot be safely parsed, preserve current fail-safe
    /// behavior; do not guess equivalence").
    static func parse(_ raw: String) -> Pulse? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d+)\s*(?:\(\s*(\d+)\s*Hz\s*\))?\s*/\s*(\d+)\s*(?:\(\s*(\d+)\s*Hz\s*\))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { return nil }

        func intGroup(_ index: Int) -> Int? {
            guard let groupRange = Range(match.range(at: index), in: trimmed) else { return nil }
            return Int(trimmed[groupRange])
        }

        guard let preCount = intGroup(1), let growthCount = intGroup(3) else { return nil }
        let preHz = intGroup(2) ?? defaultHz
        let growthHz = intGroup(4) ?? defaultHz
        return Pulse(preCount: preCount, preHz: preHz, growthCount: growthCount, growthHz: growthHz)
    }

    /// The canonical Registry write-facing string for a semantic pulse
    /// value — the ONE representation used for Ready preview, the actual
    /// candidate workbook write, and Existing comparison/display.
    static func registryDisplayString(_ pulse: Pulse) -> String {
        "\(pulse.preCount) (\(pulse.preHz)Hz) /\(pulse.growthCount) (\(pulse.growthHz)Hz)"
    }

    /// Convenience: parses a raw pulse string (e.g. an Obsidian claim) and
    /// formats it in canonical Registry notation. Returns nil if `raw`
    /// cannot be safely parsed — callers keep their existing fail-safe
    /// fallback (the raw string, unchanged) for that case.
    static func registryDisplayString(fromRawClaim raw: String) -> String? {
        parse(raw).map(registryDisplayString)
    }
}
