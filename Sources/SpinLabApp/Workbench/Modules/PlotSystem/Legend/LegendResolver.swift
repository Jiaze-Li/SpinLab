import Foundation

// MARK: - LegendResolver
//
// The single authority for final legend display text (v5.5.8 legend-ownership
// consolidation).
//
// Ownership contract:
//   - Workflows supply series data, canonical resolver-facing metadata (temperature,
//     field, device, harmonic, substrate, energy, pressure, growthTemperature,
//     thickness), a stable series identity, and a declared semantic/fallback label
//     (their best literal or math-markup guess at a human-readable name).
//   - The render pipeline supplies user rename overrides (from the series-order /
//     rename UI), keyed by the same stable series identity.
//   - `LegendResolver` is the ONLY place that decides what text a series' legend
//     entry ultimately shows. It applies, in strict priority order:
//       1. user override
//       2. automatic tier-based dimension resolution (LegendDimensionResolver) — either
//          a single distinguishing dimension, or, when multiple dimensions vary at the
//          same tier, a composite label combining all of them in configured chain order
//       3. the shared fallback policy — the workflow-declared semantic label
//   - `WorkbenchPlotLayout` and `WorkbenchChartRenderer` consume the returned labels
//     verbatim. They must not re-derive or override legend semantics.
//
// This does not replace `LegendDimensionResolver` — it wraps it as the tier-chain
// engine for outcome (2), and owns outcomes (1) and (3) explicitly so no other file
// needs to reimplement "what wins" logic.

/// Outcome of a legend resolution pass. Every case still yields display labels —
/// resolution "failing" never means workflow-owned text leaks through uncontrolled;
/// it means the shared fallback policy (declared semantic label) was selected.
enum LegendResolutionStatus: Equatable, Sendable {
    /// A single canonical dimension distinguishes the series.
    case resolved(dimension: String)
    /// Multiple dimensions vary at the same priority tier. The module combines them into
    /// one composite label per series (e.g. "100 mJ / 150 mT"), in configured chain order —
    /// this is a deterministic resolution, not a failure state requiring manual choice.
    case resolvedComposite(dimensions: [String])
    /// No configured dimension varies across the series.
    case indeterminate
    /// Automatic multi-series resolution does not apply (single series, or no metadata
    /// at all) — the declared semantic label is used directly.
    case notApplicable
}

/// Input contract: everything the Legend module needs to decide final legend text.
struct LegendResolutionInput: Sendable {
    /// Per-series resolver-facing input. Order is index-aligned with the caller's series array.
    struct SeriesEntry: Sendable {
        /// Stable series identity — used only to look up `userOverrides`, never as label content.
        var identityKey: String
        /// Workflow-declared semantic/fallback label (literal text or `math:`-markup expression).
        /// Selected by this module as the final label whenever automatic resolution does not
        /// produce a distinguishing value for this series.
        var semanticLabel: String
        /// Canonical resolver-facing metadata (temperature, field, device, harmonic, substrate,
        /// energy, pressure, growthTemperature, thickness, ...). Workflow-specific identity/
        /// bookkeeping fields (tabKey, seriesRole, stableSemanticID, seriesIdentityKey) must not
        /// be placed here — they must never participate in dimension inference.
        var metadata: [String: String]

        init(identityKey: String, semanticLabel: String, metadata: [String: String] = [:]) {
            self.identityKey = identityKey
            self.semanticLabel = semanticLabel
            self.metadata = metadata
        }
    }

    var series: [SeriesEntry]
    /// User rename overrides, keyed by stable identity key. Highest priority, always wins.
    var userOverrides: [String: String] = [:]
    /// Resolver priority chain. Defaults to the shared chain — do not fork per workflow.
    var chain: [LegendDimensionResolver.DimensionEntry] = LegendDimensionResolver.defaultChain
}

/// Output contract: the only thing layout/rendering are allowed to draw.
struct LegendResolutionOutput: Sendable {
    /// Final display labels, index-aligned with `LegendResolutionInput.series`.
    var labels: [String]
    /// Display name of the resolved/ambiguous/indeterminate legend dimension banner, if any.
    var legendDimensionDisplayName: String?
    var status: LegendResolutionStatus
    var warnings: [String]
}

enum LegendResolver {

    /// Full resolution pass: the canonical entry point implementing the priority order
    /// (user override > automatic tier resolution > shared fallback) in one call.
    static func resolve(_ input: LegendResolutionInput) -> LegendResolutionOutput {
        let series = input.series
        guard !series.isEmpty else {
            return LegendResolutionOutput(labels: [], legendDimensionDisplayName: nil, status: .notApplicable, warnings: [])
        }

        // Priority 3 (shared fallback), computed first as the baseline every other
        // priority layers on top of: the workflow-declared semantic label.
        var labels = series.map(\.semanticLabel)
        var dimensionName: String?
        var status: LegendResolutionStatus = .notApplicable
        var warnings: [String] = []

        // Priority 2: automatic tier-based dimension resolution. Only applicable to
        // multi-series payloads carrying at least some canonical metadata.
        if series.count >= 2 {
            let seriesMeta = series.map(\.metadata)
            if seriesMeta.contains(where: { !$0.isEmpty }) {
                let tierResult = LegendDimensionResolver(chain: input.chain).resolve(seriesMetadata: seriesMeta)
                (labels, dimensionName, status, warnings) = Self.apply(
                    tierResult, fallbackLabels: labels
                )
            }
        }

        // Priority 1: user rename overrides, applied last so they always win.
        for i in series.indices {
            if let custom = input.userOverrides[series[i].identityKey] {
                labels[i] = custom
            }
        }

        return LegendResolutionOutput(labels: labels, legendDimensionDisplayName: dimensionName, status: status, warnings: warnings)
    }

    // MARK: - Pipeline-staged helpers
    //
    // WorkbenchRenderPipeline needs the automatic-resolution step to run BEFORE layout is
    // computed (so `legendRow.originalLabel` reflects the auto-resolved-but-not-yet-renamed
    // label, keeping rename-panel geometry/identity stable) and the user-override step to run
    // AFTER layout (so measured width for the renamed text is computed from the override
    // string, not baked into `originalLabel`). These two helpers are the same priority-2 and
    // priority-1 rules `resolve(_:)` applies internally, exposed as staged steps so the pipeline
    // never has to reimplement "what wins" itself — it only calls into this module.

    /// Priority 2 in isolation: automatic tier-based resolution, no user overrides.
    /// Returns resolved labels alongside the legend dimension banner name and warnings.
    static func resolveDimension(
        semanticLabels: [String],
        seriesMetadata: [[String: String]],
        chain: [LegendDimensionResolver.DimensionEntry] = LegendDimensionResolver.defaultChain
    ) -> (labels: [String], legendDimensionDisplayName: String?, status: LegendResolutionStatus, warnings: [String]) {
        guard semanticLabels.count >= 2, seriesMetadata.contains(where: { !$0.isEmpty }) else {
            return (semanticLabels, nil, .notApplicable, [])
        }
        let tierResult = LegendDimensionResolver(chain: chain).resolve(seriesMetadata: seriesMetadata)
        return Self.apply(tierResult, fallbackLabels: semanticLabels)
    }

    /// Priority 1 in isolation: user rename overrides are the only rule allowed to change a
    /// label after automatic resolution has already run. Keyed by series index.
    static func applyUserOverrides(_ labels: [String], overrides: [Int: String]) -> [String] {
        guard !overrides.isEmpty else { return labels }
        return labels.enumerated().map { i, label in overrides[i] ?? label }
    }

    // MARK: - Private

    /// Shared placeholder for a missing value within an otherwise-populated composite label
    /// (e.g. one series lacks "pressure" while its siblings have it: "100 mJ / —").
    static let missingValuePlaceholder = "—"

    private static func apply(
        _ result: LegendDimensionResolver.Result,
        fallbackLabels: [String]
    ) -> (labels: [String], legendDimensionDisplayName: String?, status: LegendResolutionStatus, warnings: [String]) {
        var labels = fallbackLabels
        switch result {
        case .resolved(let dim, let values):
            for i in labels.indices where i < values.count && !values[i].isEmpty {
                labels[i] = values[i]
            }
            return (labels, dim.displayName, .resolved(dimension: dim.displayName), [])
        case .ambiguous(let dims, let values):
            let names = dims.map(\.displayName).joined(separator: " / ")
            // Shared fallback policy: a series with none of the varying dimensions populated
            // falls back to its declared semantic label (never an all-placeholder composite);
            // otherwise each missing component becomes the shared placeholder, never a
            // malformed/truncated join.
            for i in labels.indices where i < values.count {
                let seriesValues = values[i]
                guard seriesValues.contains(where: { !$0.isEmpty }) else { continue }
                labels[i] = seriesValues
                    .map { $0.isEmpty ? Self.missingValuePlaceholder : $0 }
                    .joined(separator: " / ")
            }
            return (labels, names, .resolvedComposite(dimensions: dims.map(\.displayName)), [])
        case .indeterminate:
            let warning = "Legend: no distinguishing dimension found across selected samples."
            return (labels, "⚠ No distinguishing dimension", .indeterminate, [warning])
        }
    }
}
