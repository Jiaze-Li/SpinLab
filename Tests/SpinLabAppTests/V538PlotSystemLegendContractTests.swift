import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V538PlotSystemLegendContractTests
//
// Reusable, workflow-agnostic contract for how any workflow wires plot series into the
// shared LegendResolver / PlotSystem. Not specific to Scaling vs Angle — it exists so a
// future workflow that "renders fine but shows a UUID in the legend" fails a test here.
//
// The contract:
//   - A series' internal identity and its user-visible semantic label are different things.
//   - Canonical dimension metadata (device / harmonic / temperature / ...) drives the legend.
//   - `LegendIntegrationContract` flags a multi-series payload that supplies neither.

@Suite("v5.3.8 — PlotSystem legend integration contract")
struct V538PlotSystemLegendContractTests {

    private func series(
        identity: String,
        fallbackLabel: String,
        metadata canonical: [String: String]
    ) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(
            label: fallbackLabel,
            x: [0],
            y: [0],
            renderMode: .scatter,
            metadata: WorkbenchSeriesIdentityMetadata.metadata(
                base: canonical,
                seriesIdentityKey: identity
            )
        )
    }

    private func resolve(_ s: [WorkbenchPlotSeries])
        -> (labels: [String], dimension: String?, status: LegendResolutionStatus) {
        let r = LegendResolver.resolveDimension(
            semanticLabels: s.map(\.label),
            seriesMetadata: s.map(\.metadata)
        )
        return (r.labels, r.legendDimensionDisplayName, r.status)
    }

    // MARK: - Case A — Device varies

    @Test("Case A — device varies, identities are distinct UUID-style tokens, fallback labels identical → resolved(Device)")
    func caseADeviceVaries() {
        let shared = "series"
        let s = [
            series(identity: "3w:svangle:series:\(UUID())", fallbackLabel: shared,
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(device: "0deg")),
            series(identity: "3w:svangle:series:\(UUID())", fallbackLabel: shared,
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(device: "30deg")),
            series(identity: "3w:svangle:series:\(UUID())", fallbackLabel: shared,
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(device: "90deg")),
        ]
        let r = resolve(s)
        #expect(r.status == .resolved(dimension: "Device"))
        #expect(r.labels == ["0deg", "30deg", "90deg"])

        // No resolved label is an internal identity token.
        let identities = Set(s.compactMap { $0.metadata["seriesIdentityKey"] })
        for label in r.labels { #expect(!identities.contains(label)) }

        #expect(LegendIntegrationContract.diagnostics(for: s).isEmpty)
    }

    // MARK: - Case B — Harmonic varies

    @Test("Case B — harmonic 1ω vs 3ω still resolves through the shared resolver")
    func caseBHarmonicVaries() {
        let s = [
            series(identity: "3w:rahe:series:a", fallbackLabel: "R vs T",
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(temperature: "80", harmonic: "1ω")),
            series(identity: "3w:rahe:series:b", fallbackLabel: "R vs T",
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(temperature: "80", harmonic: "3ω")),
        ]
        let r = resolve(s)
        #expect(r.status == .resolved(dimension: "Harmonic"))
        #expect(r.labels == ["1ω", "3ω"])
        #expect(LegendIntegrationContract.diagnostics(for: s).isEmpty)
    }

    // MARK: - Case C — no semantic metadata + identity used as fallback label

    @Test("Case C — identity used as semantic label with empty canonical metadata → contract diagnostic")
    func caseCIdentityLeakIsFlagged() {
        let idA = "3w:bad:series:\(UUID())"
        let idB = "3w:bad:series:\(UUID())"
        let s = [
            series(identity: idA, fallbackLabel: idA, metadata: [:]),
            series(identity: idB, fallbackLabel: idB, metadata: [:]),
        ]

        let diagnostics = LegendIntegrationContract.diagnostics(for: s)
        #expect(!diagnostics.isEmpty)
        #expect(diagnostics.contains { $0.contains("identity token") })
        #expect(diagnostics.contains { $0.contains("no canonical dimension metadata") })

        // And the resolver itself has nothing to resolve — it does NOT invent a dimension.
        let r = resolve(s)
        #expect(r.status == .notApplicable || r.status == .indeterminate)
    }

    @Test("Contract passes for a correctly-wired multi-series payload")
    func contractPassesForGoodIntegration() {
        let s = [
            series(identity: "3w:svangle:series:angle-0", fallbackLabel: "0deg",
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(device: "0deg")),
            series(identity: "3w:svangle:series:angle-30", fallbackLabel: "30deg",
                   metadata: WorkbenchSeriesMetadataBuilder.buildDerived(device: "30deg")),
        ]
        #expect(LegendIntegrationContract.diagnostics(for: s).isEmpty)
    }

    @Test("Single-series payloads are outside the multi-series contract")
    func singleSeriesIsExempt() {
        let one = [series(identity: "x", fallbackLabel: "x", metadata: [:])]
        #expect(LegendIntegrationContract.diagnostics(for: one).isEmpty)
    }
}
