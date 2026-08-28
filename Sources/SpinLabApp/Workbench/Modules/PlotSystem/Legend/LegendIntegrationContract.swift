import Foundation

// MARK: - LegendIntegrationContract
//
// A low-risk pre-flight check that a workflow wired its plot series into the shared
// PlotSystem / LegendResolver contract correctly.
//
// The failure this guards against: a workflow that "works" (chart renders, tests pass)
// but whose legend shows an internal identity token (UUID / runID / candidateID /
// "sampleKey|runID") because it declared that token as the series' semantic/fallback
// label AND supplied no canonical dimension metadata, leaving LegendResolver with
// nothing to resolve.
//
// Contract for a multi-series workflow:
//   1. A series' stable identity and its semantic/fallback label are DIFFERENT concepts.
//      `seriesIdentityKey` must never also be the `semanticLabel`.
//   2. Canonical resolver-facing metadata (temperature / field / device / harmonic /
//      substrate / energy / pressure / growthTemperature / thickness) should be present
//      so LegendResolver can resolve a real dimension.
//
// This is intentionally a NON-FATAL, test-time diagnostic. It never inspects string
// shape to guess "this looks like a UUID" — a legitimate sample name may look like one.
// It only compares a series' declared label against its own declared identity tokens.

enum LegendIntegrationContract {

    /// Per-series projection into the legend contract's view of the world.
    struct SeriesInput {
        /// Stable identity key (namespaced workflow:tab:role:stableSemanticID, or a fallback).
        var identityKey: String
        /// Workflow-declared semantic / fallback label.
        var semanticLabel: String
        /// Full series metadata dictionary (canonical dimensions + identity bookkeeping).
        var metadata: [String: String]

        init(identityKey: String, semanticLabel: String, metadata: [String: String] = [:]) {
            self.identityKey = identityKey
            self.semanticLabel = semanticLabel
            self.metadata = metadata
        }
    }

    /// Extracts the contract view from rendered plot series, using the exact same identity
    /// resolution the render pipeline uses.
    static func seriesInputs(from series: [WorkbenchPlotSeries]) -> [SeriesInput] {
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentityKeys(for: series)
        return zip(series, identities).map { s, key in
            SeriesInput(identityKey: key, semanticLabel: s.label, metadata: s.metadata)
        }
    }

    /// Returns architecture diagnostics for a workflow's legend integration.
    /// Empty array == the integration satisfies the contract.
    static func diagnostics(for series: [SeriesInput]) -> [String] {
        guard series.count >= 2 else { return [] }
        var out: [String] = []

        // Identity bookkeeping keys that must never be used as a semantic label.
        let identityKeys = [
            WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey,
            WorkbenchSeriesOrderKeyResolver.sourceHitIDMetadataKey,
        ]

        for (i, entry) in series.enumerated() {
            let label = entry.semanticLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }

            var identityTokens: Set<String> = [entry.identityKey]
            for key in identityKeys {
                if let v = entry.metadata[key], !v.isEmpty { identityTokens.insert(v) }
            }
            if identityTokens.contains(label) {
                out.append("series[\(i)]: internal identity token is being used as the user-visible semantic label ('\(label)'). Identity and semantic label must be distinct concepts.")
            }
        }

        // Multi-series with zero canonical dimension metadata: LegendResolver has nothing to
        // resolve and every entry will fall back to the workflow-declared label.
        let carriesCanonical = series.contains { entry in
            WorkbenchSeriesMetadataBuilder.canonicalDimensionKeys.contains { entry.metadata[$0]?.isEmpty == false }
        }
        if !carriesCanonical {
            out.append("multi-series payload carries no canonical dimension metadata (temperature/field/device/harmonic/substrate/...). Route the workflow's semantic metadata through WorkbenchSeriesMetadataBuilder so LegendResolver can resolve a dimension.")
        }

        return out
    }

    /// Convenience for rendered payloads.
    static func diagnostics(for series: [WorkbenchPlotSeries]) -> [String] {
        diagnostics(for: seriesInputs(from: series))
    }
}
