import Foundation
import Testing
@testable import SpinLabApp

/// Task 12: unit reconciliation and the AHE candidate verdicts (pure, no Library, no lease).
@Suite("Task 12 AHE Sample Result candidates")
struct Task12AHECandidateTests {

    // MARK: - Units

    @Test("same unit writes as is; known SI prefixes convert exactly; 0.05 T is 50 mT, never 0.00005")
    func unitConversion() {
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "T") == .identical(value: 0.05))
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "mT").writableValue == 50)
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "µT").writableValue == 50_000)
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "μT").writableValue == 50_000)   // Greek mu
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "uT").writableValue == 50_000)
        #expect(ResultUnitConversion.convert(2.5, from: "Ω", to: "mΩ").writableValue == 2500)
        #expect(ResultUnitConversion.convert(2500, from: "Ω", to: "kΩ").writableValue == 2.5)
        #expect(ResultUnitConversion.convert(2_500_000, from: "Ω", to: "MΩ").writableValue == 2.5)
        #expect(ResultUnitConversion.convert(3, from: "Ω", to: "Ohm") == .identical(value: 3))
        #expect(ResultUnitConversion.convert(3, from: "Ω", to: "\u{2126}") == .identical(value: 3))  // ohm sign
        #expect(ResultUnitConversion.convert(0, from: "T", to: "mT").writableValue == 0)              // zero is a value
    }

    @Test("mΩ and MΩ are different units; capital-prefixed tesla and everything unknown is refused")
    func unitCaseAndRefusal() {
        #expect(ResultUnitConversion.convert(1, from: "Ω", to: "mΩ").writableValue == 1000)
        #expect(ResultUnitConversion.convert(1, from: "Ω", to: "MΩ").writableValue == 1e-6)
        for unit in ["", "   ", "G", "gauss", "MT", "kT", "K", "V", "Ω·cm", "%"] {
            let outcome = ResultUnitConversion.convert(0.05, from: "T", to: unit)
            #expect(outcome.writableValue == nil, "\(unit) must be refused")
        }
        // Incompatible quantity.
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "Ω").writableValue == nil)
        #expect(ResultUnitConversion.convert(3, from: "Ω", to: "T").writableValue == nil)
        #expect(ResultUnitConversion.convert(3, from: "Ω", to: "Oe").writableValue == nil)
    }

    @Test("Oe follows the existing 1 Oe = 1e-4 T convention; non-finite and overflow are refused")
    func oerstedAndNonFinite() {
        #expect(ResultUnitConversion.convert(0.05, from: "T", to: "Oe").writableValue == 500)
        #expect(ResultUnitConversion.convert(.nan, from: "T", to: "T").writableValue == nil)
        #expect(ResultUnitConversion.convert(.infinity, from: "T", to: "mT").writableValue == nil)
        #expect(ResultUnitConversion.convert(1e305, from: "Ω", to: "µΩ").writableValue == nil)
    }

    // MARK: - Candidate verdicts

    private func selection(
        key: String = "S1", file: String = "/data/a.dat", channel: AHEChannel = .ch1,
        conditions: [String: String] = ["temperature": "80K"], batch: String = "PN1", hit: String = "hit-a"
    ) -> AHEPlotSelectionItem {
        AHEPlotSelectionItem(sampleKey: key, sourceFilePath: file, channel: channel, conditions: conditions,
                             workflowID: "AHE", sampleSubstrate: "STO", batchID: batch, hitID: hit)
    }

    private func series(for selection: AHEPlotSelectionItem, x: [Double] = [-1, 0, 1], y: [Double] = [-1, 0, 1]) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(
            label: "\(selection.sampleKey) | \(selection.channel.rawValue)", x: x, y: y,
            sourceRef: selection.sourceFilePath, sampleID: selection.sampleKey,
            metadata: [
                WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey:
                    BuildAHEResultCandidatesUseCase.seriesIdentityKey(for: selection),
                WorkbenchSeriesOrderKeyResolver.sourceHitIDMetadataKey: selection.hitID,
            ])
    }

    private func metrics(_ key: String = "S1", hc: Double = 0.05, rAHE: Double = 2) -> [String: AHEExtractedMetric] {
        [key: AHEExtractedMetric(sampleKey: key, hc: hc, rAHE: rAHE)]
    }

    @Test("one surviving curve yields a candidate whose conditions come from that curve's own selection")
    func conditionsFollowSurvivingCurve() {
        // The first selection's file produced no curve (skipped by ingestion); the second one did.
        let skipped = selection(file: "/data/skipped.dat", conditions: ["temperature": "10K"], hit: "hit-skipped")
        let survivor = selection(file: "/data/b.dat", channel: .ch2, conditions: ["temperature": "80K"], batch: "PN9", hit: "hit-b")
        let verdicts = BuildAHEResultCandidatesUseCase().execute(
            selections: [skipped, survivor], correctedSeries: [series(for: survivor)], metrics: metrics())
        guard case let .available(base)? = verdicts["S1"] else { Issue.record("expected candidate"); return }
        #expect(base.conditions == ["temperature": "80K"])
        #expect(base.sourceBatchID == "PN9")
        #expect(base.inputSummary == "b.dat · ch2")
        #expect(base.hc == 0.05 && base.rAHE == 2)
    }

    @Test("several curves for one Sample are refused, even if only one value would otherwise be kept")
    func multipleCurvesRefused() {
        let a = selection(channel: .ch1), b = selection(channel: .ch2)
        let verdicts = BuildAHEResultCandidatesUseCase().execute(
            selections: [a, b], correctedSeries: [series(for: a), series(for: b)], metrics: metrics())
        guard case .unavailable? = verdicts["S1"] else { Issue.record("expected refusal"); return }
    }

    @Test("too few points, non-finite metrics and ambiguous or missing source are refused; zero is a real value")
    func refusals() {
        let sel = selection()
        let useCase = BuildAHEResultCandidatesUseCase()
        // One point → the extractor's placeholder (0, 0) is not a result.
        guard case .unavailable? = useCase.execute(
            selections: [sel], correctedSeries: [series(for: sel, x: [1], y: [1])], metrics: metrics(hc: 0, rAHE: 0))["S1"]
        else { Issue.record("one point"); return }
        // Non-finite.
        guard case .unavailable? = useCase.execute(
            selections: [sel], correctedSeries: [series(for: sel)], metrics: metrics(hc: .nan))["S1"]
        else { Issue.record("nan"); return }
        guard case .unavailable? = useCase.execute(
            selections: [sel], correctedSeries: [series(for: sel)], metrics: metrics(rAHE: .infinity))["S1"]
        else { Issue.record("inf"); return }
        // Two selections that both match the surviving curve (duplicate hit) → source not unique.
        guard case .unavailable? = useCase.execute(
            selections: [sel, sel], correctedSeries: [series(for: sel)], metrics: metrics())["S1"]
        else { Issue.record("ambiguous"); return }
        // No matching selection at all.
        guard case .unavailable? = useCase.execute(
            selections: [selection(file: "/data/other.dat")], correctedSeries: [series(for: sel)], metrics: metrics())["S1"]
        else { Issue.record("missing"); return }
        // A genuine zero with enough points is available.
        guard case let .available(base)? = useCase.execute(
            selections: [sel], correctedSeries: [series(for: sel)], metrics: metrics(hc: 0, rAHE: 0))["S1"]
        else { Issue.record("zero"); return }
        #expect(base.hc == 0 && base.rAHE == 0)
    }

    @Test("unknown conditions stay empty rather than being invented")
    func unknownConditionsStayEmpty() {
        let sel = selection(conditions: [:])
        let verdicts = BuildAHEResultCandidatesUseCase().execute(
            selections: [sel], correctedSeries: [series(for: sel)], metrics: metrics())
        guard case let .available(base)? = verdicts["S1"] else { Issue.record("expected candidate"); return }
        #expect(base.conditions.isEmpty)
    }
}
