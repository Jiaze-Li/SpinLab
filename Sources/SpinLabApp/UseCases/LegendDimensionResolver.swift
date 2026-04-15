import Foundation

// MARK: - LegendDimensionResolver
//
// Data-driven resolver that determines which metadata dimension distinguishes
// a set of plot series (e.g. temperature, substrate, energy).
//
// The caller supplies:
//   1. A priority chain — an ordered list of (key, displayName, tier) entries.
//   2. Per-series metadata — each series carries a [String: String] dictionary
//      of dimension values (e.g. ["temperature": "300", "substrate": "STO"]).
//
// Algorithm:
//   For each tier (ascending):
//     Collect all keys at this tier whose values differ across series.
//     - Exactly 1 differs → resolved: that key is the legend dimension.
//     - Multiple differ   → ambiguous: warn user to choose manually.
//     - None differ       → continue to next tier.
//   After all tiers → indeterminate: warn (no distinguishing dimension found).
//
// Numeric tolerance: values that parse as Double are compared with relative
// tolerance (default 1%), so 59.999 and 60.0 are treated as equal.

struct LegendDimensionResolver {

    // MARK: - Public types

    /// One entry in the priority chain. Entries with the same `tier` are checked together.
    struct DimensionEntry: Codable, Hashable, Sendable {
        var key: String
        var displayName: String
        var tier: Int
    }

    /// Resolution result.
    enum Result: Equatable, Sendable {
        /// A single dimension was identified. `values` is index-aligned with the input metadata array.
        case resolved(dimension: DimensionEntry, values: [String])
        /// Multiple dimensions at the same tier vary simultaneously.
        case ambiguous(dimensions: [DimensionEntry])
        /// No configured dimension varies across the series.
        case indeterminate
    }

    // MARK: - Configuration

    /// The priority chain. Lower tier = higher priority.
    var chain: [DimensionEntry]

    /// Relative tolerance for numeric comparison (default 1%).
    var numericTolerance: Double = 0.01

    // MARK: - Default chain

    /// Built-in priority chain matching the user-defined ordering:
    ///   temperature > device = substrate = energy = pressure = growthTemperature > thickness
    static let defaultChain: [DimensionEntry] = [
        DimensionEntry(key: "temperature",       displayName: "Temperature (K)",        tier: 0),
        DimensionEntry(key: "device",             displayName: "Device",                 tier: 1),
        DimensionEntry(key: "substrate",          displayName: "Substrate",              tier: 1),
        DimensionEntry(key: "energy",             displayName: "Energy",                 tier: 1),
        DimensionEntry(key: "pressure",           displayName: "Pressure",               tier: 1),
        DimensionEntry(key: "growthTemperature",  displayName: "Growth Temperature",     tier: 1),
        DimensionEntry(key: "thickness",          displayName: "Thickness",              tier: 2),
    ]

    // MARK: - Resolve

    /// Determines the legend dimension from per-series metadata.
    ///
    /// - Parameter seriesMetadata: One dictionary per series, keyed by dimension key.
    ///   Missing keys are treated as empty string (unknown).
    /// - Returns: Resolution result.
    func resolve(seriesMetadata: [[String: String]]) -> Result {
        guard seriesMetadata.count >= 2 else {
            // Single series or empty — nothing to distinguish.
            if let first = seriesMetadata.first {
                // Return the highest-priority key that has a value, or indeterminate.
                for entry in chain.sorted(by: { $0.tier < $1.tier }) {
                    if let val = first[entry.key], !val.isEmpty {
                        return .resolved(dimension: entry, values: [val])
                    }
                }
            }
            return .indeterminate
        }

        // Group chain entries by tier, sorted ascending.
        let tiers = Dictionary(grouping: chain, by: \.tier)
            .sorted(by: { $0.key < $1.key })

        for (_, entries) in tiers {
            let varying = entries.filter { entry in
                dimensionVaries(key: entry.key, across: seriesMetadata)
            }
            if varying.count == 1 {
                let dim = varying[0]
                let values = seriesMetadata.map { $0[dim.key] ?? "" }
                return .resolved(dimension: dim, values: values)
            }
            if varying.count > 1 {
                return .ambiguous(dimensions: varying)
            }
            // None vary at this tier — continue.
        }

        return .indeterminate
    }

    // MARK: - Private

    /// Returns true if the values for `key` differ across any pair of series.
    /// Missing (empty) values are ignored — only non-empty values are compared.
    /// If all non-empty values are the same, the dimension does not vary.
    private func dimensionVaries(key: String, across metadata: [[String: String]]) -> Bool {
        let values = metadata.map { $0[key] ?? "" }
        let nonEmpty = values.filter { !$0.isEmpty }

        // All empty or only one non-empty → dimension not present or not comparable.
        if nonEmpty.count <= 1 { return false }

        // Try numeric comparison with tolerance on non-empty values.
        let numbers = nonEmpty.compactMap { Double($0) }
        if numbers.count == nonEmpty.count {
            guard let ref = numbers.first else { return false }
            return numbers.contains { !approximatelyEqual($0, ref) }
        }

        // String comparison on non-empty values.
        guard let ref = nonEmpty.first else { return false }
        return nonEmpty.contains { $0 != ref }
    }

    /// Approximate equality with relative tolerance.
    private func approximatelyEqual(_ a: Double, _ b: Double) -> Bool {
        if a == b { return true }
        let magnitude = max(abs(a), abs(b))
        if magnitude < 1e-12 { return true } // both near zero
        return abs(a - b) / magnitude <= numericTolerance
    }
}
